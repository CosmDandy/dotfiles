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
{ IFS= read -r -d '' out; IFS= read -r -d '' cmd; IFS= read -r -d '' sid; } < <(printf '%s' "$input" | jq -j '
  (.tool_response
   | if type == "string" then .
     elif type == "object" then ((.stdout // "") + "\n" + (.stderr // "") + "\n" + (.output // ""))
     else "" end), "\u0000", (.tool_input.command // ""), "\u0000", (.session_id // ""), "\u0000"' 2>/dev/null)
[[ -n "$out" ]] || exit 0
hint=""

case "$out" in
  *"too complex to verify"*)
    # NOTE: the worktree isolation of background jobs rejects heredocs, loops and `git -C`
    # because it cannot prove statically that they stay inside the worktree; there is no
    # setting that relaxes it. Transcripts show the same rejected command re-sent seconds
    # later, and the way out rediscovered every time — hence the per-session counter.
    n=1
    if [[ -n "$sid" ]]; then
      cnt="${TMPDIR:-/tmp}/claude-bashhint-worktree-${sid}"
      n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
      printf '%s' "$n" > "$cnt" 2>/dev/null
    fi
    if (( n == 1 )); then
      hint="Изоляция worktree не разбирает heredoc, циклы и \`git -C\` статически, и настройкой это не ослабить. Правку существующего файла делай через Edit; новый скрипт — Write в \$CLAUDE_JOB_DIR/tmp и запуск файлом. Повтор той же команды даст тот же отказ."
    else
      hint="Это уже ${n}-й отказ изоляции worktree за сессию: каждый heredoc и цикл здесь будет отклонён. Переходи на Edit/Write насовсем, скрипты — только файлом из \$CLAUDE_JOB_DIR/tmp."
    fi
    ;;
  *"Create a pull request for"*|*"/pull/new/"*)
    # NOTE: GitHub prints this on push only while the branch has no PR — so the push
    # output itself is the check, no gh call needed.
    case "$cmd" in
      *"git push"*)
        hint="Пуш прошёл, а PR для ветки нет — GitHub предлагает его создать. Последний шаг DELEGATED-запуска — \`gh pr create\`, не ссылка в отчёте."
        ;;
    esac
    ;;
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
