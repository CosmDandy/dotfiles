#!/usr/bin/env bash
# SessionEnd: свернуть файлы этой сессии в общий PROGRESS.md и удалить их.
#
# Почему хуком, а не правилом. В CLAUDE.md уже написано «сверни фрагмент и удали»,
# и это не выполнялось: к моменту написания в корне лежали пять PROGRESS-фрагментов
# от пяти разных сессий и два TODO, а /knowledge не запускался ни разу за девять
# содержательных сессий. Ритуал в конце сессии не делает ни человек, ни модель —
# у обоих в этот момент уже нет ни контекста, ни повода. Хук делает.
#
# Область намеренно узкая: сворачивается ТОЛЬКО фрагмент своей сессии. Определить
# «чужая сессия точно закончилась» надёжно нельзя, а свернуть чужой живой фрагмент —
# значит увести работу из-под работающей сессии. Чужие по-прежнему показывает
# SessionStart, и разбирает их владелец.
#
# NOTE: без `set -e` — это уборка, и частичный отказ не должен ронять остальное.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
sid8="${sid:0:8}"
[[ -n "$sid8" && -n "$cwd" ]] || exit 0

cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0

# В worktree фрагмент лежит в ОСНОВНОМ чекауте: так велит CLAUDE.md, потому что
# в `.claude/worktrees/<name>/` следующая сессия его не найдёт. А --show-toplevel
# указывает на сам worktree — то есть хук искал бы там, где ничего нет, и молча
# выходил, оставив файлы навсегда. Различаем worktree по расхождению git-dir и
# common-dir; в сабмодуле они совпадают, и поведение не меняется.
gitdir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [[ -n "$common" && "$gitdir" != "$common" ]]; then
  main_root="$(dirname "$common")"
  [[ -d "$main_root" ]] && root="$main_root"
fi

frag="$root/PROGRESS.${sid8}.md"
todo="$root/TODO.${sid8}.md"
main="$root/PROGRESS.md"
[[ -f "$frag" || -f "$todo" ]] || exit 0

# Блокировка каталогом, а не flock: flock в BSD-userland нет вовсе, а `mkdir`
# атомарен везде. Не смогли взять — значит другая сессия сворачивает прямо сейчас;
# наши файлы никуда не денутся до следующего раза.
lock="$root/.progress-fold.lock"
# Замок снимает trap на EXIT, а SIGKILL (таймаут хука, падение, выключение машины)
# его не выполняет. Оставшийся каталог выключил бы свёртку в этом репозитории
# НАВСЕГДА и молча, а CLAUDE.md при этом говорит модели не сворачивать руками.
# Свёртка занимает доли секунды, так что пять минут — заведомо мёртвый хозяин.
if [[ -d "$lock" ]]; then
  # GNU-форма первой: BSD на `-c` отвечает пустым stdout и кодом 1, а GNU на `-f`
  # печатает блок про файловую систему и мусор попадает в переменную.
  mtime="$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null)"
  [[ -n "$mtime" ]] && (( $(date +%s) - mtime > 300 )) && rmdir "$lock" 2>/dev/null
fi
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

stamp="$(date '+%Y-%m-%d %H:%M')"
[[ -f "$main" ]] || printf '# PROGRESS\n\n## Done\n\n## In progress\n\n## Next\n\n## Notes\n' > "$main"

# --- незакрытые задачи уезжают в ## Next: именно они и есть то, что подхватывает
# --- следующая сессия. Закрытые не переносим — они уже история, она в git.
if [[ -f "$todo" ]]; then
  open_items="$(grep -E '^[[:space:]]*- \[ \]' "$todo" 2>/dev/null)"
  if [[ -n "$open_items" ]]; then
    items_file="$(mktemp)"
    printf '%s\n' "$open_items" | sed "s|^[[:space:]]*- \[ \]|- (сессия ${sid8})|" > "$items_file"
    tmp="$(mktemp)"
    awk -v f="$items_file" '
      { print }
      # Заголовок ищется по префиксу — ровно так же, как его читает
      # sessionstart-state.sh. С точным `^## Next$` заголовок вида «## Next steps»
      # не совпадал, свёртка дописывала ВТОРУЮ секцию в конец файла, а SessionStart
      # продолжал показывать первую: задача уезжала на диск и терялась.
      /^## Next/ && !ins { while ((getline l < f) > 0) print l; close(f); ins = 1 }
      END { if (!ins) { print ""; print "## Next"; while ((getline l < f) > 0) print l } }
    ' "$main" > "$tmp" && mv "$tmp" "$main"
    rm -f "$items_file" "$tmp"
  fi
  rm -f "$todo"
fi

# --- сам фрагмент уезжает в конец, под датированный заголовок. Первую строку-титул
# --- фрагмента отбрасываем, иначе в PROGRESS.md появится второй `# PROGRESS`.
if [[ -f "$frag" ]]; then
  body="$(sed '1{/^#[[:space:]]/d;}' "$frag")"
  if [[ -n "${body//[[:space:]]/}" ]]; then
    {
      printf '\n## Сессия %s — %s\n\n' "$sid8" "$stamp"
      printf '%s\n' "$body"
    } >> "$main"
  fi
  rm -f "$frag"
fi

exit 0
