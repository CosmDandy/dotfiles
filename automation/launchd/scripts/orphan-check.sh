#!/usr/bin/env bash
set -uo pipefail

# Report-only orphan detector: finds things that point at software which no
# longer exists (LaunchAgents, system extensions, network services, TCC grants,
# native messaging hosts, privileged helpers, unmanaged apps) and prints them.
# NEVER deletes anything — the sibling of cleanup-mac.sh with the opposite job.
# Runs without sudo, tolerates every check failing on its own, safe to re-run.
#
# Usage: ./orphan-check.sh [--quiet]
#   --quiet  print only sections with findings, so the launchd log stays empty on a clean
#            machine

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$HOME/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# NOTE: this script runs both as a bash launchd agent and by hand under zsh. In
# zsh a glob with no match is an error rather than an empty list, while bash
# passes the pattern through literally and the `[[ -e ]]` checks filter it.
# null_glob evens that out, and it is guarded because `setopt` does not exist in
# bash at all.
[[ -n "${ZSH_VERSION:-}" ]] && setopt null_glob 2>/dev/null

LOG_PREFIX="[orphan-check]"
QUIET=""
TOTAL=0

for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    # NOTE: a bad argument must not exit non-zero — launchd reads that as
    # "failed".
    *) echo "$LOG_PREFIX неизвестный аргумент игнорирован: $arg" >&2 ;;
  esac
done

log() { echo "$LOG_PREFIX $*"; }

# Each section accumulates into a temp file and is printed only once its count
# is known — otherwise --quiet could not decide whether to show the header.
print_section() {
  local title="$1" file="$2" count
  count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
  [[ -n "$count" ]] || count=0
  TOTAL=$((TOTAL + count))
  if [[ "$count" -eq 0 ]]; then
    [[ -n "$QUIET" ]] && return 0
    log "$title"
    log "  · находок нет"
    return 0
  fi
  log "$title"
  while IFS= read -r line; do
    log "  · $line"
  done < "$file"
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# --- 1. LaunchAgents/LaunchDaemons pointing at a missing binary ---------------

c1="$WORKDIR/c1"
: > "$c1"
for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  [[ -d "$dir" ]] || continue
  for plist in "$dir"/*.plist; do
    [[ -e "$plist" ]] || continue
    prog=$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null)
    [[ -n "$prog" ]] || prog=$(plutil -extract Program raw "$plist" 2>/dev/null)
    [[ -n "$prog" ]] || continue
    [[ -e "$prog" ]] && continue
    echo "$plist -> $prog" >> "$c1"
  done
done
print_section "LaunchAgents/LaunchDaemons с несуществующим бинарём" "$c1"

# --- 2. System extensions with no owner --------------------------------------

# NOTE: mdfind by bundle id is NOT the deciding test here — the staged copy of
# any installed extension lives in /Library/SystemExtensions and matches itself,
# so an orphan and a legitimate extension give the same self-only result. The
# real signal is the system's own state: enabled/active empty, [state] like
# "terminated waiting to uninstall on reboot". Active ones are not checked at
# all.
c2="$WORKDIR/c2"
: > "$c2"
# NOTE: one field per `read` instead of five — zsh and bash collapse empty
# leading tab-separated fields differently, which shifted the columns under zsh.
# awk splits.
while IFS= read -r rec; do
  [[ -n "$rec" ]] || continue
  id="${rec%%$'\t'*}"; rest="${rec#*$'\t'}"
  name="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
  team="${rest%%$'\t'*}"; state="${rest#*$'\t'}"
  echo "$name ($id, team $team) — $state" >> "$c2"
done < <(systemextensionsctl list 2>/dev/null | awk -F'\t' 'NF==6 && $3 != "teamID" && !($1=="*" && $2=="*") {
  id=$4; sub(/ \(.*/, "", id)
  printf "%s\t%s\t%s\t%s\n", id, $5, $3, $6
}')
print_section "Системные расширения без владельца (неактивные/terminated)" "$c2"

# --- 3. Network services with no owner ---------------------------------------

# Physical interfaces never appear in `scutil --nc list` — they have no bundle
# id and are skipped silently. Only VPN-like services are checked.
c3="$WORKDIR/c3"
: > "$c3"
nc_list=$(scutil --nc list 2>/dev/null)
while IFS= read -r svc; do
  [[ -n "$svc" ]] || continue
  line=$(grep -F "\"$svc\"" <<< "$nc_list" | head -1)
  [[ -n "$line" ]] || continue
  id=$(sed -E 's/.*\(([^()]+)\)[[:space:]]+"[^"]+".*/\1/' <<< "$line")
  [[ -n "$id" ]] || continue
  found=$(mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null)
  [[ -z "$found" ]] && echo "$svc ($id) — приложение не найдено" >> "$c3"
done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | sed 's/^\*//')
print_section "Сетевые сервисы без владельца" "$c3"

# --- 4. TCC entries pointing at missing paths --------------------------------

# The common case is a stale nix-store hash left behind by nix-collect-garbage.
# NOTE: opened mode=ro — never write to TCC.db.
c4="$WORKDIR/c4"
: > "$c4"
tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
tcc_out=$(sqlite3 "file:$tcc_db?mode=ro" "SELECT DISTINCT client FROM access WHERE client LIKE '/%';" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "TCC.db недоступна (нужен Full Disk Access для процесса, который это запускает: System Settings → Privacy & Security → Full Disk Access) — $tcc_out" >> "$c4"
else
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ -e "$path" ]] && continue
    echo "$path — путь не существует" >> "$c4"
  done <<< "$tcc_out"
fi
print_section "TCC: клиенты по несуществующим путям" "$c4"

# --- 5. Native messaging hosts pointing at a missing binary ------------------

c5="$WORKDIR/c5"
: > "$c5"
for host_dir in "$HOME/Library/Application Support"/*/NativeMessagingHosts; do
  [[ -d "$host_dir" ]] || continue
  for json in "$host_dir"/*.json; do
    [[ -e "$json" ]] || continue
    bin_path=$(jq -r '.path // empty' "$json" 2>/dev/null)
    [[ -n "$bin_path" ]] || continue
    [[ -e "$bin_path" ]] && continue
    echo "$json -> $bin_path" >> "$c5"
  done
done
print_section "Native messaging hosts с несуществующим бинарём" "$c5"

# --- 6. PrivilegedHelperTools nothing claims ---------------------------------

# The Info.plist contents are collected once rather than per helper — a find
# over /Applications and Application Support is not free.
c6="$WORKDIR/c6"
: > "$c6"
if [[ -d /Library/PrivilegedHelperTools ]]; then
  claims="$WORKDIR/claims"
  : > "$claims"
  while IFS= read -r plist; do
    [[ -e "$plist" ]] || continue
    content=$(plutil -p "$plist" 2>/dev/null) || continue
    [[ "$content" == *SMPrivilegedExecutables* ]] && echo "$content" >> "$claims"
  done < <(find /Applications "$HOME/Library/Application Support" "/Library/Application Support" \
    -iname Info.plist -path "*/Contents/Info.plist" 2>/dev/null)

  for helper in /Library/PrivilegedHelperTools/*; do
    [[ -e "$helper" ]] || continue
    name=$(basename "$helper")
    grep -q "\"$name\"" "$claims" 2>/dev/null && continue
    # NOTE: second source of ownership — pkg installers (Microsoft Office and
    # the like) place a helper outside SMPrivilegedExecutables but do leave a
    # receipt, and a live receipt is as much an owner as an Info.plist entry.
    pkgid=$(pkgutil --file-info "$helper" 2>/dev/null | awk '/^pkgid:/ {print $2; exit}')
    if [[ -n "$pkgid" ]] && pkgutil --pkg-info "$pkgid" &>/dev/null; then
      continue
    fi
    echo "$name — не заявлен ни в SMPrivilegedExecutables, ни в pkg-receipt" >> "$c6"
  done
fi
print_section "PrivilegedHelperTools без заявившего приложения" "$c6"

# --- 7. Applications in /Applications that nothing manages -------------------

# "Managed" means a brew cask owns it (the list plus the cask metadata — .app
# stanzas, uninstall.delete, pkgutil receivers, because for pkg installers brew
# does not declare the .app directly), the Mac App Store (_MASReceipt), or the
# nix store. Everything else never updates itself.
c7="$WORKDIR/c7"
: > "$c7"
if command -v brew >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  owned="$WORKDIR/owned"
  : > "$owned"
  for cask in $(brew list --cask 2>/dev/null); do
    json=$(brew info --cask --json=v2 "$cask" 2>/dev/null)
    brew list --cask "$cask" 2>/dev/null | grep -oE '[^/]+\.app$' >> "$owned"
    jq -r '[.. | strings] | .[]' <<< "$json" 2>/dev/null | grep -oE '[^/]+\.app$' >> "$owned"
    jq -r '[.. | .pkgutil? // empty] | flatten | .[]' <<< "$json" 2>/dev/null \
      | while IFS= read -r id; do
          [[ -n "$id" ]] || continue
          pkgutil --files "$id" 2>/dev/null \
            | grep -E '^Applications/[^/]+\.app/Contents/Info\.plist$' \
            | sed -E 's#^Applications/##; s#/Contents/Info\.plist$##'
        done >> "$owned"
  done

  for app in /Applications/*.app; do
    [[ -e "$app" ]] || continue
    base=$(basename "$app")
    if [[ -L "$app" ]]; then
      tgt=$(readlink "$app")
      case "$tgt" in
        /nix/store/*|*/nix/store/*|/System/*|../System/*) continue ;;
      esac
    fi
    [[ -f "$app/Contents/_MASReceipt/receipt" ]] && continue
    grep -Fxq "$base" "$owned" 2>/dev/null && continue
    echo "$base" >> "$c7"
  done
else
  echo "brew или jq не найдены в PATH — проверка пропущена" >> "$c7"
fi
print_section "Приложения в /Applications без владельца (brew/MAS/nix)" "$c7"

if [[ -z "$QUIET" || "$TOTAL" -gt 0 ]]; then
  log "Итого находок: $TOTAL"
fi
exit 0
