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

# ---- DENY: destructive infrastructure (manual only) ----
at 'terraform[[:space:]]+destroy\b'                  && deny "terraform destroy — run it manually"
at 'terraform[[:space:]]+state[[:space:]]+(rm|mv)\b' && deny "terraform state rm/mv — manual only"
at 'kubectl[[:space:]]+(delete|drain)\b'             && deny "kubectl delete/drain — manual only"
at 'helm[[:space:]]+(uninstall|rollback)\b'          && deny "helm uninstall/rollback — manual only"
at 'nomad[[:space:]]+(job[[:space:]]+(stop|purge)|node[[:space:]]+drain|alloc[[:space:]]+stop)\b' \
                                                     && deny "nomad stop/purge/drain — manual only"

# ---- DENY: destructive system / secret exfiltration (matters most under bypass) ----
at 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME|/\*|~/\*|\$HOME/\*)([[:space:]]|$)' \
                                                     && deny "recursive delete of / or home"
at 'sudo\b'                                          && deny "sudo — run it manually"
if at '(cat|less|more|head|tail|bat)[[:space:]]+[^|;&]*\.env(\.[[:alnum:]_-]+)?' \
   && ! has '\.env\.(example|sample|template|dist)'; then deny "reading a plaintext .env file"; fi
at '(printenv|env|set)\b[^|]*\|[^|]*(base64|curl|wget|nc|xxd)' && deny "environment-variable exfiltration"
at '(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh)\b' && deny "pipe-to-shell from network"
has '>[[:space:]]*/dev/tcp/'                          && deny "reverse shell"
has '(\.ssh/[^[:space:]]*(id_|key)|\.config/sops/age|\bage-keygen\b)' && deny "touching private keys"

# ---- ASK: mutating infrastructure (confirm in the moment) ----
at 'terraform[[:space:]]+apply\b'           && ask "terraform apply — confirm?"
at 'ansible-playbook\b'                      && ask "ansible-playbook — confirm?"
at 'kubectl[[:space:]]+apply\b'             && ask "kubectl apply — confirm?"
at 'helm[[:space:]]+(install|upgrade)\b'    && ask "helm install/upgrade — confirm?"
at 'nomad[[:space:]]+job[[:space:]]+run\b'  && ask "nomad job run — confirm?"
at 'chmod[^|]*\b777\b'                        && ask "chmod 777 — confirm?"

exit 0
