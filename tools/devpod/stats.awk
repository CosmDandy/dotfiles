#!/usr/bin/awk -f

# Summary of dp's own event log: how often each call happens, what it costs, and
# how often it fails. Written for the question the log exists to answer — what
# timeout is right here — so it reports p50 and p95 rather than an average: the
# average of "40ms from cache" and "6s cold" describes neither.
#
# Input is the five-column TSV written by _dp_log: when, event, ms, status,
# key=value pairs. Usage: awk -f stats.awk events.tsv [events.tsv.1]
#
# NOTE: sorts by hand. macOS ships the one-true-awk, which has no asort(), and
# insertion sort over a few thousand rows is instant.

function isort(a, n,    i, j, key) {
  for (i = 2; i <= n; i++) {
    key = a[i]; j = i - 1
    while (j > 0 && a[j] > key) { a[j + 1] = a[j]; j-- }
    a[j + 1] = key
  }
}

function pct(a, n, p,    idx) {
  if (n == 0) return 0
  idx = int(p * n / 100)
  if (idx < 1) idx = 1
  if (idx > n) idx = n
  return a[idx]
}

# Milliseconds are unreadable past a second and misleading below one.
function dur(ms) {
  if (ms >= 10000) return sprintf("%.0fs", ms / 1000)
  if (ms >= 1000)  return sprintf("%.1fs", ms / 1000)
  return sprintf("%dms", ms)
}

BEGIN {
  FS = "\t"
  order_n = 0
}

# Skip anything that is not a data row: a truncated line from a killed shell,
# or a header somebody added by hand.
NF < 4 || $2 == "" { next }

{
  ev = $2
  ms = $3 + 0
  bad = ($4 + 0 != 0)

  if (!(ev in seen)) { seen[ev] = 1; order[++order_n] = ev }
  n[ev]++
  if (bad) fail[ev]++
  v[ev, n[ev]] = ms
  if (ms > max[ev]) max[ev] = ms

  # The breakdowns worth having: which path an entry took and whether the
  # multiplexed connection was already up, and which host a probe asked.
  if (ev == "connect" || ev == "session") {
    path = ""; master = ""
    split($5, kv, " ")
    for (i in kv) {
      if (kv[i] ~ /^path=/)   { path = substr(kv[i], 6) }
      if (kv[i] ~ /^master=/) { master = substr(kv[i], 8) }
    }
    k = sprintf("%-7s %-7s master=%s", ev, path, master)
    if (!(k in dseen)) { dseen[k] = 1; dorder[++dorder_n] = k }
    dn[k]++
    dv[k, dn[k]] = ms
    if (bad) dfail[k]++
  }
  if (ev == "probe") {
    host = ""
    split($5, kv, " ")
    for (i in kv) if (kv[i] ~ /^host=/) host = substr(kv[i], 6)
    if (!(host in hseen)) { hseen[host] = 1; horder[++horder_n] = host }
    hn[host]++
    hv[host, hn[host]] = ms
    if (bad) hfail[host]++
  }
}

END {
  if (order_n == 0) { print "no events logged yet"; exit 0 }

  printf "%-14s %6s %9s %9s %9s %7s\n", "event", "n", "p50", "p95", "max", "failed"
  for (o = 1; o <= order_n; o++) {
    ev = order[o]
    for (i = 1; i <= n[ev]; i++) tmp[i] = v[ev, i]
    isort(tmp, n[ev])
    printf "%-14s %6d %9s %9s %9s %7d\n", ev, n[ev], \
      dur(pct(tmp, n[ev], 50)), dur(pct(tmp, n[ev], 95)), dur(max[ev]), fail[ev] + 0
    for (i = 1; i <= n[ev]; i++) delete tmp[i]
  }

  if (dorder_n > 0) {
    printf "\nentering a container — connect is time to get in, session is time spent\n"
    printf "%-30s %6s %9s %9s %7s\n", "", "n", "p50", "p95", "failed"
    for (o = 1; o <= dorder_n; o++) {
      k = dorder[o]
      for (i = 1; i <= dn[k]; i++) tmp[i] = dv[k, i]
      isort(tmp, dn[k])
      printf "%-30s %6d %9s %9s %7d\n", k, dn[k], \
        dur(pct(tmp, dn[k], 50)), dur(pct(tmp, dn[k], 95)), dfail[k] + 0
      for (i = 1; i <= dn[k]; i++) delete tmp[i]
    }
  }

  if (horder_n > 0) {
    printf "\nasking a host for its containers\n"
    printf "%-22s %6s %9s %9s %9s %7s\n", "host", "n", "p50", "p95", "max", "silent"
    for (o = 1; o <= horder_n; o++) {
      h = horder[o]
      for (i = 1; i <= hn[h]; i++) tmp[i] = hv[h, i]
      isort(tmp, hn[h])
      printf "%-22s %6d %9s %9s %9s %7d\n", h, hn[h], \
        dur(pct(tmp, hn[h], 50)), dur(pct(tmp, hn[h], 95)), dur(pct(tmp, hn[h], 100)), hfail[h] + 0
      for (i = 1; i <= hn[h]; i++) delete tmp[i]
    }
  }
}
