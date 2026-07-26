# DevPod: алиасы управления воркспейсами + доставка age-ключа зоны в контейнер.
#
# Ключ принадлежит ЗОНЕ (удалённому docker-хосту), а не человеку: на том хосте
# root есть не только у меня, поэтому личный ключ мака туда не попадает никогда,
# а секреты зоны шифруются отдельной парой. Подробный разбор схемы — в
# локальных заметках владельца (docs/ в репозиторий не входит).
#
# Имя записи держим нейтральным: этот файл публичный, а реальное имя (оно же
# имя рабочего хоста) переопределяется в private/zsh/ — тот сорсится позже.
#
# alias'ы dpl/dpf должны быть определены ДО private/zsh/work-stack.sh:kvt-up() —
# там они используются внутри тела функции, а alias-подстановка происходит при
# парсинге функции, не при её вызове. conf.d грузится раньше private/, поэтому
# порядок соблюдён (см. комментарий у цикла подключения conf.d в .zshrc).
alias ds='devpod ssh'
alias dpd='devpod delete'
alias dps='devpod stop'
alias dpl='devpod up --dotfiles-script-env PROFILE=core --workspace-env-file ~/.dotfiles/.env'
alias dpf='devpod up --dotfiles-script-env PROFILE=devops --workspace-env-file ~/.dotfiles/.env'

: ${DPKEY_ITEM:=host-age-key}   # стартовый запрос в списке ключей, не жёсткий выбор
: ${DPKEY_FIELD:=}              # непусто → брать из custom-поля (rbw get -f)
: ${DPKEY_FILTER:=age}          # чем отсеиваем записи rbw; пусто → показать все

# Строки «id <TAB> дата последнего использования», недавние сверху.
# Сортируем по полному таймстемпу, а показываем только дату: иначе воркспейсы,
# тронутые в один день, встали бы в произвольном порядке.
_dp_rows() {
  devpod list --output json 2>/dev/null \
    | jq -r '.[] | [(.lastUsed // "-"), .id, ((.lastUsed // "----------")[:10])] | @tsv' \
    | sort -r \
    | cut -f2,3
}

# Выбор воркспейса. С fzf — нечёткий поиск, без него нумерованное меню:
# функция переживает машину без fzf и сама переключается, когда он появится.
_dp_pick() {
  emulate -L zsh
  local -a rows
  rows=(${(f)"$(_dp_rows)"})
  (( ${#rows} )) || { print -u2 "воркспейсов не найдено"; return 1; }

  if (( $+commands[fzf] )); then
    # --with-nth показывает обе колонки, --nth ограничивает поиск первой:
    # искать по дате бессмысленно, а совпадения по ней сбивают выдачу
    print -rl -- $rows \
      | fzf --prompt='workspace> ' --height=40% --reverse \
            --delimiter=$'\t' --with-nth=1,2 --nth=1 \
            --header='последние сверху' \
      | cut -f1
  else
    local choice
    select choice in ${rows%%$'\t'*}; do
      [[ -n $choice ]] && { print -r -- "$choice"; return 0; }
    done
    return 1
  fi
}

# Выбор записи с ключом среди всех записей Bitwarden. Фильтр по имени нужен
# потому, что записей больше сотни, а ключей единицы; DPKEY_ITEM идёт стартовым
# запросом fzf — привычный ключ сразу наверху, но список полный и Ctrl-U
# показывает остальные. Содержимое записей здесь не читается: список строится по
# именам, а `rbw get` вызывается уже для одной выбранной.
_dp_pick_key() {
  emulate -L zsh
  local -a items
  items=(${(f)"$(rbw list 2>/dev/null | grep -i -- "$DPKEY_FILTER")"})
  (( ${#items} )) || {
    print -u2 "dpkey: под фильтр «$DPKEY_FILTER» не попала ни одна запись Bitwarden"
    print -u2 "       DPKEY_FILTER='' покажет все"
    return 1
  }

  if (( $+commands[fzf] )); then
    print -rl -- $items \
      | fzf --prompt='age-key> ' --height=40% --reverse \
            --query="$DPKEY_ITEM" \
            --header='приватный ключ; Ctrl-U — очистить запрос и увидеть все'
  else
    local choice
    select choice in $items; do
      [[ -n $choice ]] && { print -r -- "$choice"; return 0; }
    done
    return 1
  fi
}

# Доставка ключа зоны в контейнер. Без аргументов — интерактивный выбор обоих:
# сначала воркспейс, потом ключ (порядок тот же, что у позиционных аргументов).
# Ключ живёт в контейнере до пересоздания, поэтому вызывается на первый запуск
# и после --recreate, а не на каждую сессию — оттого и отдельная команда,
# а не хвост dpl/dpf.
dpkey() {
  emulate -L zsh
  setopt local_options pipefail

  # Присваивание отдельно от local: `local id=$(...)` вернул бы 0 всегда
  # и проглотил отказ _dp_pick
  local id
  if (( $# )); then
    id=$1
  else
    id=$(_dp_pick) || return 1
  fi
  [[ -z $id ]] && { print -u2 "dpkey: воркспейс не выбран"; return 1; }

  local item
  if (( $# > 1 )); then
    item=$2
  else
    item=$(_dp_pick_key) || return 1
  fi
  [[ -z $item ]] && { print -u2 "dpkey: ключ не выбран"; return 1; }

  local key
  if [[ -n $DPKEY_FIELD ]]; then
    key=$(rbw get -f "$DPKEY_FIELD" "$item") || return 1
  else
    key=$(rbw get "$item") || return 1
  fi

  # Страховка: пустой вывод или подсунутый публичный ключ иначе молча уедут
  # в контейнер файлом-пустышкой, и отлаживать это потом дорого
  if [[ $key != *AGE-SECRET-KEY-* ]]; then
    print -u2 "dpkey: в записи «$item» нет приватного age-ключа."
    print -u2 "       Нужен приватный (AGE-SECRET-KEY-...), а не публичный age1..."
    return 1
  fi

  local errfile
  errfile=$(mktemp) || return 1
  print -r -- "$key" \
    | devpod ssh "$id" --command \
        'install -D -m600 /dev/stdin "$HOME/.config/sops/age/keys.txt"' 2>"$errfile" >/dev/null
  local rc=$?
  unset key

  if (( rc != 0 )); then
    print -u2 "dpkey: ключ не доставлен в $id"
    # devpod печатает «Error tunneling to container» и на успешных прогонах —
    # это его шум, показываем только когда есть настоящая ошибка
    grep -v 'Error tunneling to container' "$errfile" >&2
  else
    print "dpkey: ключ зоны доставлен в $id"
  fi
  rm -f "$errfile"
  return $rc
}
