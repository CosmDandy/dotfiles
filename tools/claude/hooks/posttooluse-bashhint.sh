#!/usr/bin/env bash
# PostToolUse(Bash): узнать знакомую грабку по тексту ошибки и сразу дать выход.
#
# Смысл не в блокировке — команда уже отработала. Смысл в том, что правило из
# CLAUDE.md («macOS это BSD userland под zsh») теряется в общем объёме файла и
# вспоминается только постфактум. Здесь оно приходит ровно в тот момент, когда
# сломалось, и с готовой заменой, а не с общим принципом.
#
# Каждая запись взята из разбора собственных транскриптов, не выдумана.
set -uo pipefail

input="$(cat)"

# tool_response у Bash бывает и строкой, и объектом со stdout/stderr.
out="$(printf '%s' "$input" | jq -r '
  .tool_response
  | if type == "string" then .
    elif type == "object" then ((.stdout // "") + "\n" + (.stderr // "") + "\n" + (.output // ""))
    else "" end' 2>/dev/null)"
[[ -n "$out" ]] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
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

# Хук висит на двух событиях (PostToolUse и PostToolUseFailure) — имя должно совпадать
# с тем, что пришло, иначе вывод рискует быть отброшенным.
event="$(printf '%s' "$input" | jq -r '.hook_event_name // "PostToolUse"' 2>/dev/null)"

jq -nc --arg ctx "Знакомая грабля: $hint" --arg ev "$event" \
  '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$ctx}}'
exit 0
