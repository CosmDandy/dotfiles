#!/usr/bin/env bash
# PreToolUse guard for Bash commands.
# Runs in ALL modes — including the --dangerously-skip-permissions alias — so it
# is the real backstop there, where settings.json allow/ask/deny is bypassed.
#   deny = destructive infra / system / secret-exfiltration (do it by hand)
#   ask  = mutating infra you should confirm in the moment
# NOTE: no `set -e` — grep returning 1 on "no match" must not kill the script.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[[ -n "$cmd" ]] || exit 0

# Cheap prefilter: the hook runs on EVERY command, and one pass over the string
# is three times cheaper than segmenting plus twenty greps. It is a strict
# superset of everything the rules below can fire on.
# NOTE: adding a rule with a new command name means adding the name here too.
# NOTE: the second group has no closing \b on purpose — exfiltration and
# pipe-to-shell rules match these as substrings, and `\bnc\b` let `env | ncat h
# p` through the filter, turning a hard deny into silence.
GATED='\b(terraform|kubectl|helm|nomad|docker|git|rm|sudo|chmod|ansible-playbook|python3?|node|uv|zsh|bash|sh|dash|ksh|age-keygen)\b|\b(curl|wget|nc|base64|xxd)|/dev/tcp|\.ssh\b|\.config/sops/age|\.env'
grep -Eq "$GATED" <<<"$cmd" || exit 0

emit() {
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}
deny() { emit deny "$1"; }
ask()  { emit ask  "$1"; }

# has: match anywhere (for content patterns that are dangerous regardless).
has() { grep -Eq "$1" <<<"$cmd"; }
# at: match only at COMMAND POSITION — start of line or right after a shell
# separator. Stops phrases quoted inside `git commit -m "..."` from counting.
CP='(^|[;&|]|&&|\|\|)[[:space:]]*'
at() { grep -Eq "${CP}$1" <<<"$cmd"; }

# NOTE: splitting must understand quoting or it breaks BOTH ways. Splitting on
# every ; and | tore `curl -H 'Cookie: a=1; b=2' -o ~/.zshrc URL` in half so no
# segment held both the head and -o, and it fired on quoted prose like `git
# commit -m "cleanup; rm -r old files"`. So: walk the string, track quote state,
# split only on UNQUOTED separators. `&` splits too, and `(` `)` so a command
# inside $(...) becomes its own segment head.
# NOTE: written via a quoted heredoc — awk needs both quote characters as
# literals.
SPLIT_AWK=$(cat <<'AWK'
function walk(s,   n, i, c, out, q, rest, tag) {
  n = length(s); out = ""; q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == "\\" && q == "\"") { i++; out = out c substr(s, i, 1); continue }
      # NOTE: substitution inside DOUBLE quotes still runs, so "$(sudo ls)" is a
      # command position too. Without this branch `echo "$(sudo rm -rf /)"`
      # passed.
      if (q == "\"" && (c == "`" || (c == "$" && substr(s, i+1, 1) == "("))) {
        print out; out = ""
        if (c == "$") i++
        continue
      }
      if (c == q) q = ""
      out = out c
      continue
    }
    if (c == "\\") { i++; out = out c substr(s, i, 1); continue }
    if (c == "'" || c == "\"") { q = c; out = out c; continue }
    # NOTE: a heredoc opener counts only at an UNQUOTED position. Matching the
    # tag against the raw line meant `git commit -m "docs: describe <<EOF
    # usage"` switched the rest of the command off — one `<<Word` in prose
    # disabled the guard entirely.
    if (c == "<" && substr(s, i+1, 1) == "<" && substr(s, i+2, 1) != "<" && hd == "") {
      rest = substr(s, i)
      if (match(rest, /^<<-?[[:space:]]*["']?[A-Za-z_][A-Za-z0-9_]*["']?/)) {
        tag = substr(rest, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/["']/, "", tag)
        hd = tag
      }
    }
    if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "`") {
      print out; out = ""; continue
    }
    out = out c
  }
  print out
}
{
  # NOTE: a heredoc body is data, not commands — but only for splitting. For
  # `has` it is the opposite (the body IS the script to read), so the skip lives
  # only here.
  buf[++nb] = $0
  if (hd != "") {
    line = $0
    sub(/^[[:space:]]+/, "", line)          # <<- allows an indented terminator
    sub(/[[:space:]]+$/, "", line)
    if (line == hd) hd = ""
    next
  }
  hdopen = nb
  walk($0)
}
END {
  # NOTE: an unclosed tag means `<<` never opened a heredoc (`$((1 << n))`,
  # `<<TAG` in prose). The tail cannot be swallowed silently — real commands may
  # live there.
  if (hd != "") for (i = hdopen + 1; i <= nb; i++) { hd = ""; walk(buf[i]) }
}
AWK
)

# `zsh -c "terraform destroy"` is one command headed by zsh, and without this
# step no rule looks inside the quotes.
# NOTE: flags before -c must be allowed — `bash -lc "…"` is the most common form
# of all. The body used to be cut as ${line#*-c}, i.e. at the first "-c"
# substring, which does not exist in -lc/-ec/-ic/-xc, so nothing looked inside —
# while bash/sh/zsh sit in allow precisely because this parsing was believed to
# work.
# NOTE: the body is bounded by quotes or one word, not `.*` — that way grep -Eo
# returns EVERY `<shell> -c` in the line, not just the first.
SHELLC_FLAGS='([[:space:]]+(-o[[:space:]]+[^[:space:]]+|--[a-z][a-z-]*|-[a-zA-Z]+))*[[:space:]]+-[a-zA-Z]*c[[:space:]]+'
SHELLC_RE=$(cat <<RE
(^|[[:space:]])([^[:space:]]*/)?(zsh|bash|sh|dash|ksh)${SHELLC_FLAGS}("[^"]*"|'[^']*'|[^[:space:]]+)
RE
)
SHELLC_STRIP=$(cat <<RE
s/^[[:space:]]*([^[:space:]]*\/)?(zsh|bash|sh|dash|ksh)${SHELLC_FLAGS}//
RE
)
shellc_bodies() {
  local line body first last
  # Cheap reject before the expensive grep -Eo, which scans the whole line
  # regardless.
  grep -qE '(^|[[:space:]/])(zsh|bash|sh|dash|ksh)[[:space:]]+-' <<<"$cmd" || return 0
  while IFS= read -r line; do
    body=$(sed -E "$SHELLC_STRIP" <<<"$line")
    first=${body:0:1}; last=${body: -1}
    if [[ ( $first == '"' && $last == '"' ) || ( $first == "'" && $last == "'" ) ]]; then
      body=${body:1:${#body}-2}
    fi
    printf '%s\n' "$body"
  done < <(printf '%s\n' "$cmd" | grep -Eo -- "$SHELLC_RE")
}

# Parsed once per run: every rule calls segs(), and on a large command each
# recount is an awk plus two greps.
SEGS=''
segs() {
  if [[ -z $SEGS ]]; then
    SEGS=$( { printf '%s\n' "$cmd" | awk "$SPLIT_AWK"; shellc_bodies | awk "$SPLIT_AWK"; } )
  fi
  printf '%s\n' "$SEGS"
}

# NOTE: every git rule must tolerate global flags before the subcommand, or
# `Bash(git -C:*)` in allow becomes a bypass for the push gate, the gitleaks
# scan and the `reset --hard` deny alike. The list comes from `git --help`, not
# from memory — a missed flag bypasses all git rules at once.
GITPFX=$(cat <<'RE'
git([[:space:]]+(-C[[:space:]]*[^[:space:]]+|-c[[:space:]]*[^[:space:]]*("[^"]*"|'[^']*')?[^[:space:]]*|--(git-dir|work-tree|namespace|exec-path)([[:space:]]+|=)[^[:space:]]+|-[pP]|--(paginate|no-pager|bare|literal-pathspecs|no-optional-locks|no-replace-objects|no-lazy-fetch)))*[[:space:]]+
RE
)
# NOTE: pipelines, not a loop with a grep per segment — a heredoc carrying a
# script body cuts into thousands of segments, and a 289 KB command took over
# three minutes and tens of thousands of processes. Here the process count is
# constant.
# NOTE: no `-q` in the last stage — it closes the pipe on the first match, the
# upstream grep gets SIGPIPE, and under pipefail a successful search would
# return non-zero.
# NOTE: `--` is required — a rule's pattern may start with a dash (`-c
# …hooksPath`), and without it grep reads it as flags and dies with usage, i.e.
# the rule silently stops firing instead of breaking loudly.
seg_with() { segs | grep -E -- "^[[:space:]]*$1" | grep -E -- "$2" >/dev/null; }
# any segment headed by $1 — the same question `at` answers, but decided by the
# quote-aware splitter. CP does not treat `$(` as a command position, so `at`
# misses `echo $(docker volume rm x)`; conversely `git commit -m "chore(sudo):
# …"` would false-deny if `(` were added to CP.
seg_head() { segs | grep -E -- "^[[:space:]]*$1" >/dev/null; }
# segment headed by $1 that does NOT match $2. Empty input means no such
# command.
seg_without() { segs | grep -E -- "^[[:space:]]*$1" | grep -vE -- "$2" >/dev/null; }

# ---- DENY: destructive infrastructure (manual only) ----
seg_head 'terraform[[:space:]]+destroy\b'                  && deny "terraform destroy — run it manually"
seg_head 'terraform[[:space:]]+state[[:space:]]+(rm|mv)\b' && deny "terraform state rm/mv — manual only"
seg_head 'kubectl[[:space:]]+(delete|drain)\b'             && deny "kubectl delete/drain — manual only"
seg_head 'helm[[:space:]]+(uninstall|rollback)\b'          && deny "helm uninstall/rollback — manual only"
seg_head 'nomad[[:space:]]+(job[[:space:]]+(stop|purge)|node[[:space:]]+drain|alloc[[:space:]]+stop)\b' \
                                                           && deny "nomad stop/purge/drain — manual only"
# Same class as `docker system prune`: named volumes are somebody's data.
seg_head 'docker[[:space:]]+volume[[:space:]]+prune\b'     && deny "docker volume prune wipes unused volumes — manual only"

# ---- DENY: git operations that throw work away ----
# NOTE: settings.json denies these by prefix, but a prefix never matches
# `git -C /repo reset --hard` — only the GITPFX rule closes that.
seg_head "${GITPFX}reset[[:space:]]+--hard\b"              && deny "git reset --hard discards uncommitted work — manual only"
seg_head "${GITPFX}clean\b"                                && deny "git clean deletes untracked files — manual only"
# NOTE: the short forms are the common ones, and `git branch`/`git checkout` are
# in allow — without these alternations work was deleted with no question at
# all.
seg_head "${GITPFX}branch[[:space:]]+(-[a-zA-Z]*D|-[a-zA-Z]*(fd|df)|--delete[[:space:]]+--force|--force[[:space:]]+--delete)\b" \
                                                           && deny "git branch force-delete — manual only"
seg_head "${GITPFX}(checkout([[:space:]]+--)?|restore)[[:space:]]+\.([[:space:]]|$)" \
                                                           && deny "discarding all local changes — manual only"

# ---- DENY: destructive system / secret exfiltration (matters most under
# bypass) ----
seg_head 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME|/\*|~/\*|\$HOME/\*)([[:space:]]|$)' \
                                                           && deny "recursive delete of / or home"
seg_head 'sudo\b'                                          && deny "sudo — run it manually"
if seg_head '(cat|less|more|head|tail|bat)[[:space:]]+[^|;&]*\.env(\.[[:alnum:]_-]+)?' \
   && ! has '\.env\.(example|sample|template|dist)'; then deny "reading a plaintext .env file"; fi
at '(printenv|env|set)\b[^|]*\|[^|]*(base64|curl|wget|nc|xxd)' && deny "environment-variable exfiltration"
at '(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh)\b' && deny "pipe-to-shell from network"
# NOTE: narrowed after an audit (6 false, 0 true) — one-way probes like `echo
# >/dev/tcp/h/22` matched the old bare pattern. A real reverse shell needs an
# interactive shell or a duplex bind back to stdin.
if has '/dev/tcp/' && { has '\b(bash|sh|zsh|dash|ksh)[[:space:]]+-[a-zA-Z]*i[a-zA-Z]*\b' \
   || has '(0>&1|0<&1|<>[[:space:]]*/dev/tcp/)'; }; then deny "reverse shell"; fi
# NOTE: the whole ~/.ssh is blocked by the literal ".ssh" — matching id_* or
# names containing "key" let the real key names through. Public artefacts
# (authorized_keys, known_hosts, config, *.pub) are stripped first and the REST
# is re-checked, so a mixed command like `cat authorized_keys work_ed25519` is
# still denied.
# NOTE: `has` matches anywhere, heredoc and echo bodies included. Narrowing to
# argument position is impossible without a full shell parse.
cmd_pub_stripped=$(sed -E "s#\.ssh/(authorized_keys|known_hosts|config|sockets)[^[:space:]']*##g; s#\.ssh/[^[:space:]']*\.pub##g" <<<"$cmd")
grep -Eq '(\.ssh\b|\.config/sops/age|\bage-keygen\b)' <<<"$cmd_pub_stripped" \
                                                           && deny "touching private keys"

# ---- DENY: committing a secret (staged diff scanned by gitleaks) ---- Exit 1
# == leak found; any other code (git failure, gitleaks error) is treated as
# "nothing to block" so we never false-deny.
# NOTE: the scan must run against the repo being committed to, not the hook's
# cwd — otherwise a secret elsewhere is missed and a clean commit is blocked by
# a leak here.
if seg_head "${GITPFX}commit\b" && command -v gitleaks >/dev/null 2>&1; then
  gitc=$(segs | grep -E "^[[:space:]]*${GITPFX}commit\b" \
         | grep -Eo -- '-C[[:space:]]*[^[:space:]]+' | sed -E 's/^-C[[:space:]]*//' | head -1)
  gitargs=()
  [[ -n $gitc ]] && gitargs=(-C "$gitc")
  git ${gitargs[@]+"${gitargs[@]}"} diff --cached --no-color 2>/dev/null \
    | gitleaks stdin --no-banner --redact >/dev/null 2>&1
  [[ ${PIPESTATUS[1]} -eq 1 ]] \
    && deny "gitleaks flagged a secret in the staged diff — review it, then commit by hand or add a .gitleaksignore entry if it is a false positive"
fi

# ---- Interpreters: judge the code, not the command name ----
# python/python3/node sit in allow on purpose: a prefix rule only ever sees
# `python3 -c`, while everything that decides safe-vs-not lives inside the
# quotes.
# NOTE: this block MUST stay below the gitleaks deny — ask() exits, so an ask
# placed above a deny silences it and `python3 -c "..." && git commit` would
# skip the scan.
# NOTE: the trailing [[:space:]] in INTERP is load-bearing. With `\b` there, the
# `(` anchor turned every conventional commit subject into an invocation: `git
# commit -m "fix(node): swap child_process for execa"` matched on `(node`, then
# hit the shell-out pattern and hard-denied the commit style CLAUDE.md mandates.
# NOTE: `uv run --with requests python -c …` is THE idiomatic uv one-liner and
# uv is allow-listed, so arbitrary tokens before the interpreter have to be
# tolerated.
INTERP='(^|[;&|(`]|&&|\|\||\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((env|nice|nohup)[[:space:]]+|uv[[:space:]]+run[[:space:]]+([^[:space:]]+[[:space:]]+)*)*([^[:space:]]*/)?(python3?|node)[[:space:]]'
if has "$INTERP"; then
  # NOTE: `__import__("os").system` and `from shutil import rmtree` reach the
  # same calls without ever writing the literal name.
  has 'os\.(system|popen|exec[lv]|spawn)|\bsubprocess\b|\bpty\.spawn\b|child_process|\b(exec|spawn|execFile)Sync\b|__import__\([^)]*(os|subprocess|pty)' \
                                                     && deny "interpreter shelling out — that escapes every pattern in this guard; write the shell command directly"
  has '\brmtree\(|os\.removedirs|\b(rm|rmdir)Sync\([^)]*recursive|\bfs\.rm(dir)?\([^)]*recursive' \
                                                     && deny "recursive tree delete from an interpreter"
  has '\b(urllib|requests|httpx|http\.client|socket|ftplib|smtplib|paramiko)\b|\bfetch\(|\baxios\b' \
                                                     && ask "interpreter opening the network — confirm?"
  # File write/delete asks were removed after an audit: 9/9 fires were routine
  # in-CWD edits the Edit tool performs silently. Shell-out and tree delete stay
  # hard denies.
fi

# ---- ASK: mutating infrastructure (confirm in the moment) ----
seg_head 'terraform[[:space:]]+apply\b'           && ask "terraform apply — confirm?"
seg_head 'kubectl[[:space:]]+apply\b'             && ask "kubectl apply — confirm?"
seg_head 'helm[[:space:]]+(install|upgrade)\b'    && ask "helm install/upgrade — confirm?"
seg_head 'nomad[[:space:]]+job[[:space:]]+run\b'  && ask "nomad job run — confirm?"
seg_with 'chmod\b' '\b777\b'                      && ask "chmod 777 — confirm?"

# NOTE: `Bash(git push:*)` catches only the bare prefix, so with `git -C` in
# allow a push from another directory would go out silently.
seg_head "${GITPFX}push\b"                        && ask "git push publishes — confirm?"

# ---- ASK by argument, not by command name ---- These three were blanket `ask`
# entries in settings.json and the top prompt generators there, almost always on
# a dry-run or read-only form a prefix rule cannot tell apart.

# NOTE: --check IS the dry run CLAUDE.md mandates. Per segment, because
# `ansible-playbook x --check && ansible-playbook x` is the idiom and only the
# second half needs confirming.
seg_without 'ansible-playbook\b' '(^|[[:space:]])(--check|-C)([[:space:]]|$)' \
                                              && ask "ansible-playbook without --check — confirm?"

# NOTE: `-d@file` and `--data-binary@file` take no space or `=`, and they are
# the canonical exfiltration form, so `@` closes the alternation too.
seg_with 'curl\b' '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]+(POST|PUT|DELETE|PATCH)|--json\b|(^|[[:space:]])(-d|--data(-raw|-binary|-urlencode)?|-F|--form|-T|--upload-file)([[:space:]]|=|@))' \
                                              && ask "curl with a mutating method or body — confirm?"

# NOTE: git config writes are routine (user.name in fresh clones);
# core.hooksPath is the one key that runs arbitrary code, so it is gated alone.
seg_with "${GITPFX}config\b" 'hooksPath' \
                                              && ask "git config core.hooksPath runs arbitrary code — confirm?"

# NOTE: `git -c core.hooksPath=X <anything>` is the same substitution, and
# GITPFX swallows `-c k=v` as a harmless global flag, so it needs its own rule.
seg_with 'git\b' '(^|[[:space:]])-c[[:space:]]*[^[:space:]]*hooksPath' \
                                              && ask "git -c core.hooksPath runs arbitrary code on the next git operation — confirm?"

# NOTE: `docker compose:*` is in allow, and `down -v` destroys named volumes —
# not the reversible local operation the rest of the compose lifecycle is.
seg_with 'docker([[:space:]]+|-)compose[[:space:]]+down\b' '(^|[[:space:]])(-v|--volumes)([[:space:]]|$)' \
                                              && ask "docker compose down -v destroys named volumes — confirm?"

seg_head 'docker[[:space:]]+volume[[:space:]]+rm\b' \
                                              && ask "docker volume rm destroys the volume's data — confirm?"

# Recursive rm. The blanket `Bash(rm:*)` ask was dropped — deleting a scratch
# file is routine, `-r` is where it stops being. The deny above only fires on
# exactly / ~ or $HOME, so `rm -Rf ~/Documents` had nothing on it.
# NOTE: scratch roots are exempt PER TARGET, not per command, and a target
# hidden in a variable cannot be resolved here, so it stays gated.
rm_has_unsafe_target() {
  segs \
    | grep -E '^[[:space:]]*rm\b' \
    | grep -E -- '(^|[[:space:]])-[a-zA-Z]*[rR]' \
    | grep -Eo -- '(^|[[:space:]])[^-[:space:]][^[:space:]]*' \
    | sed -E "s/^[[:space:]]+//; s/^[\"']//" \
    | grep -vxE 'rm' \
    | grep -vE '^/(private/)?tmp/|CLAUDE_JOB_DIR|/scratchpad(/|$)|(^|/)_site(/|$)|(^|/)node_modules(/|$)|(^|/)\.turbo(/|$)' >/dev/null
}
seg_with 'rm\b' '(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)' \
  && rm_has_unsafe_target                     && ask "recursive rm outside scratch — confirm the target?"

# curl writing to disk: `curl -o ~/.zshrc URL` is a remote-controlled overwrite
# of a startup file. `-o /dev/null` is the status-probe idiom and stays silent.
# NOTE: the exemption is decided PER TARGET. Asking "does this command mention
# /dev/null anywhere" let one probe cover a real write, and curl accepts
# repeated `-o FILE URL` pairs, so that is reachable within a single command.
# NOTE: `-[a-zA-Z]*o` catches the bundled short form, and the value may be
# attached with no separator at all (`curl -o/Users/x/.zshrc URL` really does
# write that file).
curl_writes_a_file() {
  segs \
    | grep -E '^[[:space:]]*curl\b' \
    | grep -Eo -- '(^|[[:space:]])(-[a-zA-Z]*o|--output)([[:space:]]|=)*[^[:space:]]*' \
    | sed -E 's/^[[:space:]]*(-[a-zA-Z]*o|--output)[[:space:]=]*//; s/^["'"'"']//' \
    | grep -vE '^(/dev/null)?$|^/(private/)?tmp/|CLAUDE_JOB_DIR|/scratchpad(/|$)' >/dev/null
}
seg_with 'curl\b' '(^|[[:space:]])(-[a-zA-Z]*O|--remote-name)([[:space:]]|$)' \
                                              && ask "curl -O writes a file named by the server — confirm?"
curl_writes_a_file                            && ask "curl writing the response to a file — confirm the path?"

# ---- ASK: broad git-add sweeps everything, incl. the private submodule ----
seg_with "${GITPFX}add\b" '(^|[[:space:]])(-A|--all|\.)([[:space:]]|$)' \
                                              && ask "git add -A/./--all stages everything — prefer explicit paths?"

exit 0
