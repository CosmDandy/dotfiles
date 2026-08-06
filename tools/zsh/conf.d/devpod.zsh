# DevPod: алиасы управления воркспейсами + доставка age-ключа зоны в контейнер.
#
# Ключ принадлежит ЗОНЕ (удалённому docker-хосту), а не человеку: на том хосте
# root есть не только у меня, поэтому личный ключ мака туда не попадает никогда,
# а секреты зоны шифруются отдельной парой. Разбор — docs/secrets.md,
# разделы «В dev-контейнере» и «Отвергнутые варианты».
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

: ${DPKEY_ITEM:=host-age-key}   # запись в Bitwarden с ПРИВАТНЫМ ключом зоны
: ${DPKEY_FIELD:=}              # непусто → брать из custom-поля (rbw get -f)

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

# Доставка ключа зоны в контейнер. Без аргумента — интерактивный выбор.
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

  local key
  if [[ -n $DPKEY_FIELD ]]; then
    key=$(rbw get -f "$DPKEY_FIELD" "$DPKEY_ITEM") || return 1
  else
    key=$(rbw get "$DPKEY_ITEM") || return 1
  fi

  # Страховка: пустой вывод или подсунутый публичный ключ иначе молча уедут
  # в контейнер файлом-пустышкой, и отлаживать это потом дорого
  if [[ $key != *AGE-SECRET-KEY-* ]]; then
    print -u2 "dpkey: в записи «$DPKEY_ITEM» нет приватного age-ключа."
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
