#!/usr/bin/env bash
set -uo pipefail

# Keeps Claude (web, desktop, CLI) reachable only through the Happ VPN tunnel.
# Without the tunnel every packet to a Claude address is dropped by pf and the
# Claude domains do not resolve at all.
#
# Runs as a root LaunchDaemon (see platform/nix/darwin-configuration.nix) and
# every TICK seconds:
#   1. finds the Happ interface by its address (198.18.0.0/15), because the utunN
#      number moves between 5, 6 and 7 across reconnects and reboots;
#   2. rewrites the pf anchor `block ... on ! <happ iface> to <claude_ips>` — no
#      Happ interface means the rule has no `on` and blocks everywhere;
#   3. refreshes <claude_ips> from DoH every REFRESH seconds;
#   4. keeps /etc/resolver/<domain> pointing at the local forwarder
#      (claude-isolation-dns.py), so lookups of Claude names leave only via Happ.
#
# Usage: claude-isolation [run|on|off|status]
#   off — emergency valve: flush the anchor, drop the resolver files, and make the
#         daemon idle until `on`. A reboot does not clear the flag.

ANCHOR="claude-isolation"
STATE_DIR="/var/db/claude-isolation"
IPS_FILE="$STATE_DIR/ips"
SEEN_FILE="$STATE_DIR/ips.seen"
DISABLED_FLAG="$STATE_DIR/disabled"
RESOLVER_DIR="/etc/resolver"
UPSTREAM="1.1.1.1"
LOCAL_DNS_PORT=5354
TICK=5
REFRESH=120
# NOTE: addresses stay in the table this long after the last sighting, so a CDN
# rotation does not open a hole between two refreshes.
KEEP=21600

# Anthropic's own ranges: the table is never empty, so the very first start is
# fail-closed even before Happ is up for the first refresh.
ANTHROPIC_NETS=(160.79.104.0/23 2607:6bc0::/48)

# Everything under these domains resolves through the local forwarder.
RESOLVER_DOMAINS=(claude.ai anthropic.com claude.com)
# Names whose addresses go into the table; extend when a new Claude host shows up.
HOSTS=(
  claude.ai www.claude.ai claude.com platform.claude.com code.claude.com
  support.claude.com api.anthropic.com console.anthropic.com
  statsig.anthropic.com mcp-proxy.anthropic.com www.anthropic.com
)

log() { printf '%s [claude-isolation] %s\n' "$(date '+%F %T')" "$*"; }

happ_iface() {
  local i
  for i in $(ifconfig -l); do
    [[ $i == utun* ]] || continue
    if ifconfig "$i" inet 2>/dev/null | grep -Eq 'inet 198\.(18|19)\.'; then
      echo "$i"
      return
    fi
  done
}

# Resolves HOSTS over DoH (TCP/443 — plain UDP DNS does not pass the tunnel) and
# merges the answers into IPS_FILE as "<ip> <last seen epoch>".
refresh_ips() {
  local now fails=0 got=0 h t out tmp
  now=$(date +%s)
  tmp=$(mktemp "$STATE_DIR/new.XXXXXX") || return 1
  for h in "${HOSTS[@]}"; do
    for t in A AAAA; do
      if ! out=$(curl -fsS --max-time 4 -H 'accept: application/dns-json' \
        "https://$UPSTREAM/dns-query?name=$h&type=$t" 2>/dev/null); then
        fails=$((fails + 1))
        ((fails >= 3)) && break 2
        continue
      fi
      # NOTE: 198.18/15 is Happ's fake-ip range — a table entry there would
      # whitelist nothing and block nothing.
      jq -r '.Answer[]? | select(.type==1 or .type==28) | .data' <<<"$out" 2>/dev/null |
        grep -Ev '^198\.1[89]\.' | awk -v now="$now" 'NF {print $1, now}' >>"$tmp"
    done
  done
  got=$(wc -l <"$tmp")
  if ((got == 0)); then
    rm -f "$tmp"
    log "refresh: no answers (failures: $fails), table kept"
    return 1
  fi
  merge_into_ips "$tmp"
}

# Merges "<ip> <epoch>" lines from $1 into IPS_FILE, newest sighting wins, expired
# entries drop out. Consumes $1.
merge_into_ips() {
  cat "$IPS_FILE" "$1" |
    awk -v cut=$(($(date +%s) - KEEP)) '$2 >= cut {t[$1] = $2} END {for (k in t) print k, t[k]}' |
    sort >"$IPS_FILE.new" && mv "$IPS_FILE.new" "$IPS_FILE"
  rm -f "$1"
}

# The forwarder appends every address it hands out for a Claude name to SEEN_FILE,
# so hosts missing from HOSTS (CDN names, new subdomains) still reach the table.
# The rename makes the hand-over atomic: the forwarder reopens the file per write.
merge_seen() {
  [[ -s $SEEN_FILE ]] || return 0
  mv "$SEEN_FILE" "$SEEN_FILE.work" && merge_into_ips "$SEEN_FILE.work"
}

render_rules() {
  local on="" ips
  [[ -n $1 ]] && on="on ! $1"
  ips=$(
    {
      printf '%s\n' "${ANTHROPIC_NETS[@]}"
      awk 'NF {print $1}' "$IPS_FILE" 2>/dev/null
    } | paste -sd, -
  )
  echo "table <claude_ips> persist { $ips }"
  echo "block drop out quick $on from any to <claude_ips>"
  # The forwarder's upstream: with the tunnel down a lookup must not leave via en0.
  echo "block drop out quick $on proto tcp from any to $UPSTREAM port { 53, 853 }"
}

LAST_RULES=""
apply_rules() {
  local rules
  rules=$(render_rules "$1")
  [[ $rules == "$LAST_RULES" ]] && return
  if pfctl -q -a "$ANCHOR" -f - <<<"$rules" 2>&1; then
    LAST_RULES=$rules
    log "anchor loaded (iface: ${1:-none}, addresses: $(wc -l <"$IPS_FILE" | tr -d ' '))"
  else
    log "anchor load FAILED"
  fi
}

# The anchor only works once the main ruleset references it. /etc/pf.conf is
# Apple's and gets rewritten by OS updates, so it is extended in memory, never edited.
ensure_pf() {
  if ! pfctl -sr 2>/dev/null | grep -q "anchor \"$ANCHOR\""; then
    { cat /etc/pf.conf; printf 'anchor "%s"\n' "$ANCHOR"; } | pfctl -q -f - 2>&1
    LAST_RULES=""
    log "main ruleset extended with the anchor"
  fi
  # NOTE: -E, not -e. macOS components enable pf with a token and `-X` it off when
  # the last token goes; an enable without a token is switched off with theirs.
  # The Status check keeps tokens from piling up.
  pfctl -si 2>/dev/null | grep -q 'Status: Enabled' || pfctl -E 2>&1
}

flush_dns_cache() {
  dscacheutil -flushcache
  killall -HUP mDNSResponder 2>/dev/null
}

ensure_resolvers() {
  local d want changed=0
  want=$(printf 'nameserver 127.0.0.1\nport %s\n' "$LOCAL_DNS_PORT")
  install -d -m 0755 "$RESOLVER_DIR"
  for d in "${RESOLVER_DOMAINS[@]}"; do
    if [[ $(cat "$RESOLVER_DIR/$d" 2>/dev/null) != "$want" ]]; then
      printf '%s\n' "$want" >"$RESOLVER_DIR/$d"
      changed=1
    fi
  done
  ((changed)) && flush_dns_cache
}

run() {
  local iface prev="?" now last_refresh=0
  install -d -m 0755 "$STATE_DIR"
  touch "$IPS_FILE"
  while :; do
    if [[ -e $DISABLED_FLAG ]]; then
      # `off` flushed the anchor behind our back; without this the cached rules
      # would match after `on` and never be reloaded.
      LAST_RULES=""
      sleep "$TICK"
      continue
    fi
    iface=$(happ_iface)
    if [[ $iface != "$prev" ]]; then
      log "Happ interface: ${iface:-none}"
      prev=$iface
    fi
    ensure_pf
    ensure_resolvers
    merge_seen
    apply_rules "$iface"
    now=$(date +%s)
    if [[ -n $iface ]] && ((now - last_refresh >= REFRESH)); then
      # A failed refresh is retried in 30 s, not after the full interval.
      if refresh_ips; then last_refresh=$now; else last_refresh=$((now - REFRESH + 30)); fi
      apply_rules "$iface"
    fi
    sleep "$TICK"
  done
}

off() {
  install -d -m 0755 "$STATE_DIR"
  touch "$DISABLED_FLAG"
  pfctl -q -a "$ANCHOR" -F all 2>&1
  local d
  for d in "${RESOLVER_DOMAINS[@]}"; do rm -f "${RESOLVER_DIR:?}/$d"; done
  flush_dns_cache
  echo "isolation off (flag $DISABLED_FLAG); 'claude-isolation on' re-enables"
}

on() {
  rm -f "$DISABLED_FLAG"
  echo "isolation on; the daemon applies it within ${TICK}s"
}

status() {
  echo "happ interface : $(happ_iface || true)"
  echo "disabled flag  : $([[ -e $DISABLED_FLAG ]] && echo yes || echo no)"
  echo "addresses      : $(wc -l <"$IPS_FILE" 2>/dev/null | tr -d ' ')"
  echo "--- anchor rules"
  pfctl -a "$ANCHOR" -sr 2>&1 | grep -v 'ALTQ'
  echo "--- resolver files"
  ls "$RESOLVER_DIR" 2>&1
}

case "${1:-run}" in
  run) run ;;
  on) on ;;
  off) off ;;
  status) status ;;
  *) echo "usage: claude-isolation [run|on|off|status]" >&2; exit 2 ;;
esac
