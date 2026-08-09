#!/usr/bin/env bash
set -uo pipefail

# Report-only orphan detector: finds things that point at software which no
# longer exists (LaunchAgents, system extensions, network services, TCC
# grants, native messaging hosts, privileged helpers, unmanaged apps) and
# prints them. NEVER deletes anything — this is a sibling of cleanup-mac.sh
# with the opposite job: that one reclaims disk, this one surfaces dangling
# references for a human to judge. Runs without sudo, tolerates every check
# failing on its own, safe to re-run any time (purely read-only).
#
# Запуск: ./orphan-check.sh [--quiet]
#   --quiet  печатать только секции с находками — для launchd-запуска,
#            чтобы на чистой машине лог оставался пустым

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$HOME/.bun/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Скрипт написан на пересечении bash и zsh (запускается и как launchd-агент
# через #!/usr/bin/env bash, и вручную через `zsh orphan-check.sh`). В zsh
# незаматчившийся glob — это ошибка, а не пустой список (см. правило в
# CLAUDE.md); под bash `for x in glob` при отсутствии совпадений передаёт
# паттерн буквально, и последующая проверка `[[ -e ]]` уже фильтрует его.
# null_glob уравнивает поведение и включается только под zsh — `setopt`
# самой командой не существует в bash и упала бы.
[[ -n "${ZSH_VERSION:-}" ]] && setopt null_glob 2>/dev/null

LOG_PREFIX="[orphan-check]"
QUIET=""
TOTAL=0

for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    # Не падаем на плохом аргументе: скрипт зовётся из launchd, где
    # ненулевой выход читается как «упал», а не «неверные флаги».
    *) echo "$LOG_PREFIX неизвестный аргумент игнорирован: $arg" >&2 ;;
  esac
done

log() { echo "$LOG_PREFIX $*"; }

# Каждая секция копится во временный файл построчно, а печатается только
# после того как известно, есть ли в ней находки, — иначе --quiet не мог бы
# решить, показывать заголовок секции или нет.
print_section() {
  local title="$1" file="$2" count
  count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
  [[ -n "$count" ]] || count=0
  TOTAL=$((TOTAL + count))
  if [[ "$count" -eq 0 ]]; then
    [[ -n "$QUIET" ]] && return 0
    log "$title"
    log "  · находок нет"
    return 0
  fi
  log "$title"
  while IFS= read -r line; do
    log "  · $line"
  done < "$file"
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# --- 1. LaunchAgents/LaunchDaemons с несуществующим бинарём -----------------

c1="$WORKDIR/c1"
: > "$c1"
for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  [[ -d "$dir" ]] || continue
  for plist in "$dir"/*.plist; do
    [[ -e "$plist" ]] || continue # незаматчившийся glob — не ошибка, пропуск
    prog=$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null)
    [[ -n "$prog" ]] || prog=$(plutil -extract Program raw "$plist" 2>/dev/null)
    [[ -n "$prog" ]] || continue
    [[ -e "$prog" ]] && continue
    echo "$plist -> $prog" >> "$c1"
  done
done
print_section "LaunchAgents/LaunchDaemons с несуществующим бинарём" "$c1"

# --- 2. Системные расширения без владельца -----------------------------------

# mdfind по bundle id тут НЕ решающий тест: staged-копия любого установленного
# расширения (живого или нет) лежит в /Library/SystemExtensions и сама себя
# матчит по kMDItemCFBundleIdentifier — что для сироты io.nekohasekai.sfavt.system,
# что для легитимного org.pqrs.Karabiner-DriverKit-VirtualHIDDevice mdfind даёт
# ровно один и тот же self-only результат, отличить нельзя (проверено на этой
# машине). Настоящий сигнал сироты — сама система: enabled/active пустые,
# [state] вроде "terminated waiting to uninstall on reboot" — активные
# (enabled=* active=*) не проверяем вовсе.
c2="$WORKDIR/c2"
: > "$c2"
# Одно поле на строку read вместо пяти: у zsh и bash `read` с IFS=tab
# по-разному схлопывают пустые ведущие поля (у SFM enabled/active пустые —
# два ведущих таба), из-за чего многопольный read под zsh сдвигает колонки;
# awk режет поля сам.
while IFS= read -r rec; do
  [[ -n "$rec" ]] || continue
  id="${rec%%$'\t'*}"; rest="${rec#*$'\t'}"
  name="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
  team="${rest%%$'\t'*}"; state="${rest#*$'\t'}"
  echo "$name ($id, team $team) — $state" >> "$c2"
done < <(systemextensionsctl list 2>/dev/null | awk -F'\t' 'NF==6 && $3 != "teamID" && !($1=="*" && $2=="*") {
  id=$4; sub(/ \(.*/, "", id)
  printf "%s\t%s\t%s\t%s\n", id, $5, $3, $6
}')
print_section "Системные расширения без владельца (неактивные/terminated)" "$c2"

# --- 3. Сетевые сервисы без владельца -----------------------------------------

# Физические интерфейсы (Wi-Fi, USB LAN, Thunderbolt Bridge) не встречаются в
# `scutil --nc list` вовсе — у них нет bundle id и проверять нечего, они
# пропускаются молча. Проверяем только VPN-подобные сервисы, у которых bundle
# id есть.
c3="$WORKDIR/c3"
: > "$c3"
nc_list=$(scutil --nc list 2>/dev/null)
while IFS= read -r svc; do
  [[ -n "$svc" ]] || continue
  line=$(grep -F "\"$svc\"" <<< "$nc_list" | head -1)
  [[ -n "$line" ]] || continue
  id=$(sed -E 's/.*\(([^()]+)\)[[:space:]]+"[^"]+".*/\1/' <<< "$line")
  [[ -n "$id" ]] || continue
  found=$(mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null)
  [[ -z "$found" ]] && echo "$svc ($id) — приложение не найдено" >> "$c3"
done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | sed 's/^\*//')
print_section "Сетевые сервисы без владельца" "$c3"

# --- 4. TCC: клиенты по несуществующим путям ---------------------------------

# Частый случай — устаревший nix-store хэш: путь пережил `nix-collect-garbage`
# или пересборку и в TCC.db остался мусор. READ-ONLY открытие (mode=ro) —
# никогда не пишем в TCC.db.
c4="$WORKDIR/c4"
: > "$c4"
tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
tcc_out=$(sqlite3 "file:$tcc_db?mode=ro" "SELECT DISTINCT client FROM access WHERE client LIKE '/%';" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "TCC.db недоступна (нужен Full Disk Access для процесса, который это запускает: System Settings → Privacy & Security → Full Disk Access) — $tcc_out" >> "$c4"
else
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ -e "$path" ]] && continue
    echo "$path — путь не существует" >> "$c4"
  done <<< "$tcc_out"
fi
print_section "TCC: клиенты по несуществующим путям" "$c4"

# --- 5. Native messaging hosts с несуществующим бинарём ----------------------

c5="$WORKDIR/c5"
: > "$c5"
for host_dir in "$HOME/Library/Application Support"/*/NativeMessagingHosts; do
  [[ -d "$host_dir" ]] || continue
  for json in "$host_dir"/*.json; do
    [[ -e "$json" ]] || continue
    bin_path=$(jq -r '.path // empty' "$json" 2>/dev/null)
    [[ -n "$bin_path" ]] || continue
    [[ -e "$bin_path" ]] && continue
    echo "$json -> $bin_path" >> "$c5"
  done
done
print_section "Native messaging hosts с несуществующим бинарём" "$c5"

# --- 6. PrivilegedHelperTools без заявившего приложения ----------------------

# Собираем содержимое всех Info.plist с ключом SMPrivilegedExecutables один
# раз, а не по разу на каждый helper — find по /Applications и Application
# Support не бесплатен.
c6="$WORKDIR/c6"
: > "$c6"
if [[ -d /Library/PrivilegedHelperTools ]]; then
  claims="$WORKDIR/claims"
  : > "$claims"
  while IFS= read -r plist; do
    [[ -e "$plist" ]] || continue
    content=$(plutil -p "$plist" 2>/dev/null) || continue
    [[ "$content" == *SMPrivilegedExecutables* ]] && echo "$content" >> "$claims"
  done < <(find /Applications "$HOME/Library/Application Support" "/Library/Application Support" \
    -iname Info.plist -path "*/Contents/Info.plist" 2>/dev/null)

  for helper in /Library/PrivilegedHelperTools/*; do
    [[ -e "$helper" ]] || continue
    name=$(basename "$helper")
    grep -q "\"$name\"" "$claims" 2>/dev/null && continue
    # Второй источник: pkg-инсталляторы (Microsoft Office и подобные) кладут
    # helper мимо SMPrivilegedExecutables, но оставляют receipt. Живой receipt
    # — такой же владелец, как запись в Info.plist.
    pkgid=$(pkgutil --file-info "$helper" 2>/dev/null | awk '/^pkgid:/ {print $2; exit}')
    if [[ -n "$pkgid" ]] && pkgutil --pkg-info "$pkgid" &>/dev/null; then
      continue
    fi
    echo "$name — не заявлен ни в SMPrivilegedExecutables, ни в pkg-receipt" >> "$c6"
  done
fi
print_section "PrivilegedHelperTools без заявившего приложения" "$c6"

# --- 7. Приложения в /Applications, не управляемые ничем --------------------

# «Управляемое» = каску владеет brew (список плюс метаданные каска —
# .app-стенза, uninstall.delete, pkgutil-ресиверы: у pkg-инсталляторов вроде
# karabiner-elements/microsoft-teams/openvpn-connect/amneziavpn brew не
# декларирует .app напрямую), Mac App Store (_MASReceipt/receipt), либо nix
# store (симлинк на /nix/store или в системный /System). Всё остальное
# никогда не обновляется автоматически.
c7="$WORKDIR/c7"
: > "$c7"
if command -v brew >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  owned="$WORKDIR/owned"
  : > "$owned"
  for cask in $(brew list --cask 2>/dev/null); do
    json=$(brew info --cask --json=v2 "$cask" 2>/dev/null)
    brew list --cask "$cask" 2>/dev/null | grep -oE '[^/]+\.app$' >> "$owned"
    jq -r '[.. | strings] | .[]' <<< "$json" 2>/dev/null | grep -oE '[^/]+\.app$' >> "$owned"
    jq -r '[.. | .pkgutil? // empty] | flatten | .[]' <<< "$json" 2>/dev/null \
      | while IFS= read -r id; do
          [[ -n "$id" ]] || continue
          pkgutil --files "$id" 2>/dev/null \
            | grep -E '^Applications/[^/]+\.app/Contents/Info\.plist$' \
            | sed -E 's#^Applications/##; s#/Contents/Info\.plist$##'
        done >> "$owned"
  done

  for app in /Applications/*.app; do
    [[ -e "$app" ]] || continue
    base=$(basename "$app")
    if [[ -L "$app" ]]; then
      tgt=$(readlink "$app")
      case "$tgt" in
        /nix/store/*|*/nix/store/*|/System/*|../System/*) continue ;;
      esac
    fi
    [[ -f "$app/Contents/_MASReceipt/receipt" ]] && continue
    grep -Fxq "$base" "$owned" 2>/dev/null && continue
    echo "$base" >> "$c7"
  done
else
  echo "brew или jq не найдены в PATH — проверка пропущена" >> "$c7"
fi
print_section "Приложения в /Applications без владельца (brew/MAS/nix)" "$c7"

# --- Итог --------------------------------------------------------------------

if [[ -z "$QUIET" || "$TOTAL" -gt 0 ]]; then
  log "Итого находок: $TOTAL"
fi
exit 0
