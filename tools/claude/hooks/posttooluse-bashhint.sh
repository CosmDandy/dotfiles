#!/usr/bin/env bash
# PostToolUse(Bash): recognise a familiar trap from the error text and hand over the way out.
#
# The point is not blocking — the command has already run. The point is that the rule from
# CLAUDE.md ("macOS is BSD userland under zsh") is lost in the volume of that file and only
# gets remembered afterwards. Here it arrives exactly when it broke, with the replacement
# rather than the general principle.
#
# Every entry comes from mining actual transcripts, not from imagination.
set -uo pipefail

input="$(cat)"

# Bash's tool_response is sometimes a string and sometimes an object with stdout/stderr.
# NOTE: both fields come out of ONE jq — a fork costs ~10 ms and this hook runs on EVERY
# Bash call.
# NOTE: the separator is NUL, not a tab — both the command and the output can be
# multi-line, and @tsv would escape them. NUL survives only through process substitution;
# $(...) strips it.
{ IFS= read -r -d '' out; IFS= read -r -d '' cmd; } < <(printf '%s' "$input" | jq -j '
  (.tool_response
   | if type == "string" then .
     elif type == "object" then ((.stdout // "") + "\n" + (.stderr // "") + "\n" + (.output // ""))
     else "" end), "\u0000", (.tool_input.command // ""), "\u0000"' 2>/dev/null)
[[ -n "$out" ]] || exit 0
hint=""

case "$out" in
  *"control characters that would be hidden"*)
    hint="Управляющий символ попал в команду литералом. Отклоняется валидацией ДО исполнения, поэтому предотвратить это хуком нельзя — только не писать так. Собирай символ через printf в переменную: SEP=\$(printf '\\037') и дальше передавай \"\$SEP\"."
    ;;
  *"Illegal byte sequence"*)
    hint="BSD-утилита споткнулась о многобайтный UTF-8. Либо \`LC_ALL=C\` перед командой (если байты и нужны как байты), либо не гонять текст с не-ASCII через cut/sed/tr — python или awk справятся."
    ;;
  *"command not found: timeout"*|*"timeout: command not found"*)
    hint="GNU \`timeout\` на macOS нет. Есть \`gtimeout\` из coreutils, либо запусти через run_in_background и не ограничивай время вовсе."
    ;;
  *"no matches found:"*)
    hint="zsh считает глоб без совпадений ошибкой, а не пустым списком. Закавычь шаблон и отдай его самой команде (\`find … -name '*.log'\`), либо \`setopt null_glob\` в этом же вызове."
    ;;
  *"sed: -i may not be used"*|*"sed: 1: \""*|*"invalid command code"*)
    hint="BSD \`sed -i\` требует суффикс: \`sed -i '' 's/…/…/' file\`. Для правки файла в репозитории надёжнее Edit — он не зависит от диалекта sed."
    ;;
  *"unmatched '"*|*"unmatched \""*|*"unexpected EOF while looking for matching"*)
    hint="Незакрытая кавычка. Если внутри вложенный \`python -c\` или \`perl -e\` — вынеси код в heredoc или временный файл вместо того, чтобы вкладывать кавычки в кавычки."
    ;;
  *"Operation not permitted"*)
    case "$cmd" in
      *docker*|*ip\ netns*|*mount*)
        hint="Похоже на нехватку capability, а не на права файла: netns/mount нужен привилегированный контейнер. Не обходи — сообщи владельцу."
        ;;
    esac
    ;;
esac

[[ -n "$hint" ]] || exit 0

# NOTE: the hook is registered on two events (PostToolUse and PostToolUseFailure), and the
# name must match the one that arrived or the output risks being discarded.
event="$(printf '%s' "$input" | jq -r '.hook_event_name // "PostToolUse"' 2>/dev/null)"

jq -nc --arg ctx "Знакомая грабля: $hint" --arg ev "$event" \
  '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$ctx}}'
exit 0
