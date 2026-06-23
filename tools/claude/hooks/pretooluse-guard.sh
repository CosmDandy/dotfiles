#!/usr/bin/env bash
# PreToolUse guard for Bash commands.
# Runs in ALL modes — including --dangerously-skip-permissions (alias `cly`) —
# so it is the real backstop there, where settings.json allow/ask/deny is bypassed.
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
has()  { grep -Eq "$1" <<<"$cmd"; }

# ---- DENY: destructive infrastructure (manual only) ----
has '\bterraform[[:space:]]+destroy\b'                  && deny "terraform destroy — run it manually"
has '\bterraform[[:space:]]+state[[:space:]]+(rm|mv)\b' && deny "terraform state rm/mv — manual only"
has '\bkubectl[[:space:]]+(delete|drain)\b'             && deny "kubectl delete/drain — manual only"
has '\bhelm[[:space:]]+(uninstall|rollback)\b'          && deny "helm uninstall/rollback — manual only"
has '\bnomad[[:space:]]+(job[[:space:]]+(stop|purge)|node[[:space:]]+drain|alloc[[:space:]]+stop)\b' \
                                                        && deny "nomad stop/purge/drain — manual only"

# ---- DENY: destructive system / secret exfiltration (matters most under cly) ----
has '\brm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME|/\*|~/\*|\$HOME/\*)([[:space:]]|$)' \
                                                        && deny "recursive delete of / or home"
has '\bsudo\b'                                          && deny "sudo — run it manually"
if has '(^|[^[:alnum:]_])(cat|less|more|head|tail|bat)[[:space:]]+[^|;&]*\.env(\.[[:alnum:]_-]+)?' \
   && ! has '\.env\.(example|sample|template|dist)'; then deny "reading a plaintext .env file"; fi
has '(printenv|env|set)\b[^|]*\|[^|]*(base64|curl|wget|nc|xxd)' && deny "environment-variable exfiltration"
has '(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh)\b' && deny "pipe-to-shell from network"
has '>[[:space:]]*/dev/tcp/'                            && deny "reverse shell"
has '(\.ssh/[^[:space:]]*(id_|key)|\.config/sops/age|\bage-keygen\b)' && deny "touching private keys"

# ---- ASK: mutating infrastructure (confirm in the moment) ----
has '\bterraform[[:space:]]+apply\b'           && ask "terraform apply — confirm?"
has '\bansible-playbook\b'                      && ask "ansible-playbook — confirm?"
has '\bkubectl[[:space:]]+apply\b'             && ask "kubectl apply — confirm?"
has '\bhelm[[:space:]]+(install|upgrade)\b'    && ask "helm install/upgrade — confirm?"
has '\bnomad[[:space:]]+job[[:space:]]+run\b'  && ask "nomad job run — confirm?"
has '\bchmod\b[^|]*\b777\b'                     && ask "chmod 777 — confirm?"

exit 0
