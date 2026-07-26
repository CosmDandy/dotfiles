#!/bin/bash

# Statusline для Claude Code. На stdin приходит JSON сессии, на stdout — строка.
# Слева идентичность и контекст, справа расход и лимиты подписки.

ESC=$'\033'
R="${ESC}[0m"
# Только слоты палитры 0-15: их значения задаёт тема терминала, поэтому строка
# остаётся в цветах Ghostty вместо жёстко прошитых оттенков. Форма 38;5;N при
# N<16 адресует ту же палитру, что и короткие коды 30-37/90-97.
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
RED="${ESC}[31m"
BLUE="${ESC}[34m"
# Вторичный текст — ANSI 11. Ни «bright black» (8), ни faint здесь не годятся:
# оба дают на тёмном фоне контраст ~2.1 при пороге читаемости 3, текст тонет,
# а на светлом наоборот перебивают основной. Причина в том, что Solarized
# задаёт вторичный тон разными кодами для тёмной и светлой темы (base01 против
# base1), а тема тут переключается автоматически. Коды 10-14 в обеих темах
# совпадают по значению, и из них только 11 (#657b83) держится выше порога с
# обеих сторон: 3.37 на тёмном (тише основного текста 4.75) и 4.13 на светлом.
GRAY="${ESC}[38;5;11m"
DIM="${ESC}[38;5;11m"

# Пороги контекста. Один рубеж — 85%, он же CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:
# раньше их было три (бар желтел на 70, краснел на 80, отдельная ⚠ на 85).
CTX_YELLOW=60
CTX_RED=85
BAR_LEN=10

# Кеш показываем только когда он реально просел: в норме держится 85-95%,
# и вечнозелёный индикатор не нёс информации.
CACHE_SHOW=80
CACHE_RED=50

# Лимиты подписки.
# 5h виден всегда: он расходуется рывками (пачка workflow-агентов сжигает
# десятки процентов за минуты), и без постоянной базовой линии разгон
# замечаешь уже постфактум.
FIVEH_SHOW=0
FIVEH_YELLOW=70
FIVEH_RED=85
# Тревога по СКОРОСТИ, а не только по накопленному проценту: при текущем темпе
# упрёмся в стену меньше чем через час — красный, меньше двух — жёлтый, даже
# если процент сам по себе ещё низкий.
BURN_RED_SEC=3600
BURN_YELLOW_SEC=7200
WEEK_SHOW=90         # абсолютный порог: близко к стене — показать в любой день недели
WEEK_SLACK=10
WEEK_SECONDS=604800
LIMIT_WINDOW=900     # окно усреднения для ETA, сек
IDLE_WINDOW=300      # тишина дольше этого = расход прекратился, прогноз убираем

# Глифы рисует ТЕРМИНАЛ, а не машина, на которой выполняется код: в devcontainer
# заходят из того же Ghostty с Nerd Font, поэтому детект контейнера здесь был бы
# ответом не на тот вопрос. Надёжно определить наличие шрифта нельзя, так что по
# умолчанию считаем, что он есть, и отключаемся только там, где графики заведомо
# нет (голая консоль, dumb-терминал) или когда сказали явно.
case "${CLAUDE_STATUSLINE_GLYPHS:-}" in
  nerd)  glyphs=nerd ;;
  ascii) glyphs=ascii ;;
  *)     case "${TERM:-}" in
           dumb|linux|vt[0-9]*|ansi|cons25|sun*) glyphs=ascii ;;
           *) glyphs=nerd ;;
         esac ;;
esac

if [ "$glyphs" = nerd ]; then
  # Октальные байты UTF-8, а не литералы: приватная зона Unicode переживает
  # копирование файла хуже, чем escape, и один раз уже потерялась при записи.
  G_THINK=$'\363\260\247\221'    # U+F09D1 md-brain
  G_FIVEH=$'\363\260\246\226'    # U+F0996 md-progress_clock
  G_WEEK=$'\363\260\250\263'     # U+F0A33 md-calendar_week
  G_SESSIONS=$'\363\260\204\241'   # U+F0121 md-tab
  CAP_L=''
  CAP_R=''
  # Иконки Nerd Font занимают ДВЕ колонки в вариантах шрифта без суффикса Mono
  # (у нас "JetBrainsMono Nerd Font"). Без этой поправки правый блок вылезал
  # за край и Claude Code обрезал хвост многоточием.
  GLYPH_COLS=2
else
  G_THINK='*'
  G_FIVEH='5h'
  G_WEEK='7d'
  G_SESSIONS='x'
  CAP_L=''
  CAP_R=''
  GLYPH_COLS=1
fi

# Обозначения усилия — ровно те, что показывает меню /effort самого Claude Code.
# Обычный Unicode, а не Nerd Font: одна колонка и рисуется без патченого шрифта,
# поэтому набор общий для обоих режимов и в поправку ширины не входит.
#   ○ Low   ◐ Medium   ● High (дефолт)   ◉ xHigh   ◈ Max
# Ultracode (✦) отдельным уровнем в payload не приходит — он репортится как
# xhigh, отличить его неоткуда.
G_EFFORT_LOW=$'\342\227\213'    # U+25CB ○
G_EFFORT_MED=$'\342\227\220'    # U+25D0 ◐
G_EFFORT_HIGH=$'\342\227\217'   # U+25CF ●
G_EFFORT_XHI=$'\342\227\211'    # U+25C9 ◉
G_EFFORT_MAX=$'\342\227\210'    # U+25C8 ◈

# Глиф, подпись и цвет уровня разом. Дефолтные и низкие уровни серые, чтобы не
# шуметь; выделяем только то, что выше обычного и жжёт заметно больше.
set_effort_parts() {
  case "$1" in
    low)    eff_glyph=$G_EFFORT_LOW;  eff_label=Low;    eff_color=$GRAY ;;
    medium) eff_glyph=$G_EFFORT_MED;  eff_label=Medium; eff_color=$GRAY ;;
    high)   eff_glyph=$G_EFFORT_HIGH; eff_label=High;   eff_color=$GRAY ;;
    xhigh)  eff_glyph=$G_EFFORT_XHI;  eff_label=xHigh;  eff_color=$YELLOW ;;
    max)    eff_glyph=$G_EFFORT_MAX;  eff_label=Max;    eff_color=$RED ;;
    *)      eff_glyph=''; eff_label=$1; eff_color=$GRAY ;;
  esac
}

# CLAUDE_STATUSLINE_DEBUG=1 — показать все сегменты, игнорируя пороги скрытия.
# Нужно, чтобы увидеть строку целиком, не дожидаясь просевшего кеша или
# заполненного лимита.
DEBUG_ALL="${CLAUDE_STATUSLINE_DEBUG:-}"

input=$(cat)

# Одним вызовом jq вместо полутора десятков: на каждое обновление строки
# форкался отдельный jq на поле, и прогон занимал ~130 мс при дебаунсе в 300.
# Порядок полей здесь и в read ниже должен совпадать.
# Разделитель 0x1F, а НЕ таб: IFS схлопывает подряд идущие whitespace-раз-
# делители, поэтому на @tsv пустое поле (нет агента, нет effort) съедало
# позицию и все следующие значения уезжали на одно влево.
IFS=$'\037' read -r used_pct model ctx_size cache_read input_tokens cache_creation \
  style_name effort thinking agent cost_usd \
  five_pct100 five_reset week_pct week_reset sid <<EOF
$(echo "$input" | jq -r '[
  (.context_window.used_percentage // 0 | floor),
  (.model.display_name // "Claude"),
  (.context_window.context_window_size // 0),
  (.context_window.current_usage.cache_read_input_tokens // 0),
  (.context_window.current_usage.input_tokens // 0),
  (.context_window.current_usage.cache_creation_input_tokens // 0),
  (.output_style.name // "default"),
  (.effort.level // ""),
  (if .thinking.enabled then "1" else "" end),
  (.agent.name // ""),
  ((.cost.total_cost_usd // 0) * 100 | floor),
  (if .rate_limits.five_hour.used_percentage == null then ""
   else (.rate_limits.five_hour.used_percentage * 100 | floor) end),
  (.rate_limits.five_hour.resets_at // ""),
  (if .rate_limits.seven_day.used_percentage == null then ""
   else (.rate_limits.seven_day.used_percentage | floor) end),
  (.rate_limits.seven_day.resets_at // ""),
  (.session_id // "")
] | map(tostring) | join("")')
EOF

cols=${COLUMNS:-100}
# Интерфейс Claude Code добавляет собственные отступы поверх COLUMNS, поэтому
# впритык к последней колонке прижимать нельзя — хвост срежется многоточием.
RIGHT_MARGIN=${CLAUDE_STATUSLINE_MARGIN:-5}

# --- бар контекста -----------------------------------------------------------

EIGHTHS=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉')

# Бар блоками в цветах темы: заполнено — █, пусто — ░, а последняя занятая
# клетка догоняется восьмушкой (▏▎▍▌▋▊▉), отсюда точность 1/8 клетки вместо
# целой при той же ширине. Края закругляются полукругами в цвете своей зоны.
render_bar() {
  local pct=$1 len=$2
  local eighths=$(( pct * len * 8 / 100 ))
  local full=$(( eighths / 8 ))
  local frac=$(( eighths % 8 ))
  local g_cells=$(( CTX_YELLOW * len / 100 ))
  local y_cells=$(( CTX_RED * len / 100 ))
  local i c out="" first="" last=""

  for ((i = 0; i < len; i++)); do
    if   [ "$i" -lt "$g_cells" ]; then c=$GREEN
    elif [ "$i" -lt "$y_cells" ]; then c=$YELLOW
    else                               c=$RED
    fi
    [ "$i" -eq 0 ] && first=$c
    last=$c
    if [ "$i" -lt "$full" ]; then
      out="${out}${c}█"
    elif [ "$i" -eq "$full" ] && [ "$frac" -gt 0 ]; then
      out="${out}${c}${EIGHTHS[$frac]}"
    else
      out="${out}${c}░"
    fi
  done

  if [ -n "$CAP_L" ]; then
    printf '%s%s%s%s%s%s' "$first" "$CAP_L" "$out" "$last" "$CAP_R" "$R"
  else
    printf '%s%s' "$out" "$R"
  fi
}

# --- лимиты ------------------------------------------------------------------

fmt_duration() {
  local s=$1
  if [ "$s" -ge 3600 ]; then
    printf '%dч %02dм' "$((s / 3600))" "$(((s % 3600) / 60))"
  else
    printf '%dм' "$((s / 60))"
  fi
}

# Момент времени как "4pm". BSD date (macOS) и GNU date (Linux) читают epoch
# разными флагами, локаль фиксируем — иначе %p может оказаться пустым.
# Регистр правим подстановкой, а не tr: ${x,,} требует bash 4, а здесь 3.2.
fmt_clock() {
  local ts=$1 s
  s=$(LC_ALL=C date -r "$ts" +'%-I%p' 2>/dev/null) \
    || s=$(LC_ALL=C date -d "@$ts" +'%-I%p' 2>/dev/null)
  s=${s/AM/am}
  printf '%s' "${s/PM/pm}"
}

# Сколько осталось при текущем темпе: до часа — минутами, дальше — моментом,
# когда упрёмся. Рядом со временем сброса два момента сравниваются глазом
# быстрее, чем длительность с моментом.
fmt_eta() {
  local eta=$1 now=$2
  if [ "$eta" -lt 3600 ]; then
    fmt_duration "$eta"
  else
    fmt_clock "$((now + eta))"
  fi
}

# Через сколько при текущем темпе упрёмся в 5h-лимит. Пусто, если темпа нет
# или окно сбросится раньше — тогда предупреждать не о чем. Проценты держим
# в сотых (целочисленная арифметика), файл сэмплов общий на все сессии:
# лимит аккаунтный, а не сессионный.
# Печатает «процент reset [eta]» — вызывается через $(...), то есть в подоболочке,
# поэтому отдать значения наружу можно только через stdout. Процент и reset могут
# отличаться от переданных: у отставшей сессии берём общие, из истории.
five_hour_eta() {
  local pct100=$1 reset=$2 now=$3
  local dir f wf prev_reset last first_ts first_pct last_ts last_pct idle_pct span rate eta
  dir="${TMPDIR:-/tmp}/claude-limit"
  mkdir -p "$dir" 2>/dev/null || { printf '%s %s' "$pct100" "$reset"; return 0; }
  f="$dir/five_hour"
  [ -n "$reset" ] || { printf '%s %s' "$pct100" "$reset"; return 0; }
  # Смену окна определяем по resets_at, а НЕ по падению процента. Сессии
  # обновляют payload вразнобой: простаивающая держит снимок часами, и разрыв
  # с активной легко доходит до десятков пунктов — любой порог на падении
  # срабатывает ложно и стирает историю. resets_at меняется ровно при сбросе
  # окна и только вперёд, поэтому меньший reset — заведомо протухший снимок.
  wf="$f.window"
  prev_reset=0
  [ -f "$wf" ] && read -r prev_reset < "$wf"
  prev_reset=${prev_reset:-0}
  if [ "$reset" -gt "$prev_reset" ] 2>/dev/null; then
    printf '%s\n' "$reset" >| "$wf"
    printf '%s %s\n' "$now" "$pct100" >| "$f"      # новое окно — базлайн заново
    printf '%s %s' "$pct100" "$reset"; return 0
  fi
  last=0
  [ -f "$f" ] && last=$(tail -1 "$f" | cut -d' ' -f2)
  last=${last:-0}
  # Протухший снимок в историю не пишем, но расчёт продолжаем: лимит аккаунтный,
  # и простаивающая сессия обязана показывать ту же картину, что активная.
  # Раньше здесь стоял ранний выход, и в отставших окнах прогноза не было.
  if [ "$reset" -lt "$prev_reset" ] 2>/dev/null; then
    reset=$prev_reset      # своё время сброса тоже из прошлого окна — берём общее
    pct100=$last
  elif [ "${pct100:-0}" -lt "$last" ] 2>/dev/null; then
    pct100=$last
  else
    # Только дописываем. Раньше файл на каждом тике перечитывался, фильтровался
    # и перекладывался через mv — при нескольких открытых сессиях они затирали
    # записи друг друга, история жила секунды и до span >= 60 не доживала.
    # Короткий append атомарен, поэтому окно теперь отбирается при ЧТЕНИИ.
    printf '%s %s\n' "$now" "$pct100" >> "$f"
  fi
  # Базлайн — последний сэмпл старше окна, иначе самый ранний внутри него.
  # Отдельно берём процент на границе последних IDLE_WINDOW секунд: по нему
  # видно, идёт расход прямо сейчас или окно тянет след давнего всплеска.
  read -r first_ts first_pct last_ts last_pct idle_pct <<EOF
$(awk -v now="$now" -v w="$LIMIT_WINDOW" -v iw="$IDLE_WINDOW" '
    $1 < now-w { b_ts=$1; b_pct=$2; next }
    {
      if (f_ts == "") { f_ts=$1; f_pct=$2 }
      if ($1 < now-iw) { i_pct=$2 }
      l_ts=$1; l_pct=$2
    }
    END {
      if (b_ts == "") { b_ts=f_ts; b_pct=f_pct }
      if (i_pct == "") { i_pct=b_pct }
      if (b_ts == "" || l_ts == "") exit
      print b_ts, b_pct, l_ts, l_pct, i_pct
    }' "$f")
EOF
  [ -n "$last_pct" ] || { printf '%s %s' "$pct100" "$reset"; return 0; }
  # держим файл в разумных пределах; редкая операция, гонка не страшна
  if [ "$(wc -l < "$f")" -gt 600 ] 2>/dev/null; then
    tail -100 "$f" >| "$f.tmp" && mv "$f.tmp" "$f"
  fi
  # Процент приходит с шагом в целый пункт, поэтому на коротком плече дельта в
  # один шаг меняет темп кратно — прогноз прыгал и мигал. Считаем только когда
  # накопились и время, и заметное изменение: MIN_SPAN секунд и MIN_DELTA сотых.
  span=$((last_ts - first_ts))
  rate=0
  # Простой: за последние IDLE_WINDOW секунд процент не сдвинулся. Окно в 15
  # минут само по себе этого не замечает — оно продолжает делить давний всплеск
  # на своё полное плечо и показывать бодрый темп, когда всё уже остановилось.
  if [ "$((last_pct - idle_pct))" -gt 0 ] 2>/dev/null \
     && [ "$span" -ge 180 ] && [ "$((last_pct - first_pct))" -ge 100 ]; then
    rate=$(( (last_pct - first_pct) * 60 / span ))   # сотых %/мин
  fi
  if [ "$rate" -gt 0 ]; then
    eta=$(( (10000 - pct100) * 60 / rate ))
    # Сброс раньше, чем упрёмся — предупреждать не о чем. Сравниваем с запасом
    # в 15%: без мёртвой зоны на границе eta ≈ время до сброса прогноз мигал,
    # появляясь и пропадая от каждого пересчёта.
    [ "$((eta * 100))" -lt "$(( (reset - now) * 85 ))" ] || eta=""
  else
    eta=""
  fi
  printf '%s %s %s' "$pct100" "$reset" "$eta"
}

# Лимиты подписки Claude Code кладёт прямо в payload — своей сети и кеша не
# надо, и в devcontainer работает тем же кодом. Поле есть только у Claude.ai
# Pro/Max и только после первого API-ответа; окна независимы.
# Показываем скупо:
#   5h — от FIVEH_SHOW%
#   7d — когда расход опережает равномерный по неделе на WEEK_SLACK п.п.
#        (само подстраивается: 30% в понедельник — тревога, 60% в воскресенье — нет)
compute_limits() {
  local now=$1 want_eta=$2
  local five_pct eta color elapsed_pct show five_seg="" week_seg="" segs=""

  if [ -n "$five_pct100" ]; then
    # функция возвращает актуальные (общие для всех сессий) процент и время
    # сброса плюс прогноз; eta пустой, когда темпа нет или сброс наступит раньше
    read -r five_pct100 five_reset eta <<EOF2
$(five_hour_eta "$five_pct100" "$five_reset" "$now")
EOF2
    five_pct=$((five_pct100 / 100))
    if [ "$five_pct" -ge "$FIVEH_SHOW" ] || [ -n "$DEBUG_ALL" ]; then
      color="$GREEN"
      [ "$five_pct" -ge "$FIVEH_YELLOW" ] && color="$YELLOW"
      [ "$five_pct" -ge "$FIVEH_RED" ] && color="$RED"
      # Цвет — худшее из «сколько уже потрачено» и «как быстро тратим»:
      # десяток параллельных агентов уводит окно в ноль с 20%, и ждать
      # порога в 70% там уже поздно.
      if [ -n "$eta" ]; then
        if [ "$eta" -lt "$BURN_RED_SEC" ]; then
          color="$RED"
        elif [ "$eta" -lt "$BURN_YELLOW_SEC" ] && [ "$color" = "$GREEN" ]; then
          color="$YELLOW"
        fi
      fi
      # Порядок: процент, затем прогноз упора, и справа — когда окно сбросится.
      # Прогноз стоит между ними, чтобы сравнивать «упрусь в X» с «сброс в Y».
      five_seg="${color}${G_FIVEH} ${five_pct}%"
      [ -n "$eta" ] && [ "$want_eta" -eq 1 ] && five_seg="${five_seg} ⇢ $(fmt_eta "$eta" "$now")"
      [ -n "$five_reset" ] && five_seg="${five_seg} ($(fmt_clock "$five_reset"))"
      five_seg="${five_seg}${R}"
    fi
  fi

  if [ -n "$week_pct" ]; then
    show=0
    color="$YELLOW"
    [ "$week_pct" -ge "$WEEK_SHOW" ] && show=1 && color="$RED"
    if [ "$show" -eq 0 ] && [ -n "$week_reset" ]; then
      # доля недели, которая уже прошла: окно = [resets_at - 7d, resets_at]
      elapsed_pct=$(( (WEEK_SECONDS - (week_reset - now)) * 100 / WEEK_SECONDS ))
      [ "$elapsed_pct" -lt 0 ] && elapsed_pct=0
      [ "$week_pct" -gt "$((elapsed_pct + WEEK_SLACK))" ] && show=1
    fi
    [ -n "$DEBUG_ALL" ] && show=1
    [ "$show" -eq 1 ] && week_seg="${color}${G_WEEK} ${week_pct}%${R}"
  fi

  segs="$five_seg"
  if [ -n "$week_seg" ]; then
    if [ -n "$segs" ]; then segs="${segs} ${DIM}·${R} ${week_seg}"; else segs="$week_seg"; fi
  fi
  printf '%s' "$segs"
}

# --- выравнивание ------------------------------------------------------------

# Видимая ширина. ANSI-последовательности места не занимают, ${#s} считает
# кодпоинты. Но иконки Nerd Font занимают по GLYPH_COLS колонок каждая, а
# кодпоинт у них один — недоучёт копился и выталкивал правый блок за край.
vis_width() {
  local s t n=0 g
  s=$(printf '%s' "$1" | sed "s/${ESC}\\[[0-9;]*m//g")
  n=${#s}
  if [ "$GLYPH_COLS" -gt 1 ]; then
    for g in "$G_THINK" "$G_FIVEH" "$G_WEEK" "$G_SESSIONS"; do
      [ -n "$g" ] || continue
      t=${s//"$g"/}
      n=$(( n + (${#s} - ${#t}) * (GLYPH_COLS - 1) ))
    done
  fi
  printf '%s' "$n"
}

# Правый блок прижимается к краю терминала; если строки не хватает — склеиваем
# обратно в одну ленту, это лучше, чем перенос на вторую строку.
join_edges() {
  local left=$1 right=$2 gap
  if [ -z "$right" ]; then printf '%s' "$left"; return; fi
  gap=$(( cols - RIGHT_MARGIN - $(vis_width "$left") - $(vis_width "$right") ))
  if [ "$gap" -lt 2 ]; then
    printf '%s %s·%s %s' "$left" "$DIM" "$R" "$right"
  else
    printf '%s%*s%s' "$left" "$gap" '' "$right"
  fi
}

# --- сборка сегментов --------------------------------------------------------

now=$(date +%s)

# Блок модели: [мозг] Модель [1M] [· effort] [▸ кастомный агент].
# display_name у моделей с расширенным контекстом выглядит как
# "Opus 5 (1M context)" — скобочный хвост режем, а факт 1M берём из
# context_window_size: не зависит от того, как Anthropic назовёт модель.
model_str="${model%% (*}"
[ "${ctx_size:-0}" -ge 1000000 ] 2>/dev/null && model_str="${model_str} 1M"
model_seg="${BLUE}${model_str}${R}"
[ -n "$thinking" ] && model_seg="${BLUE}${G_THINK} ${model_str}${R}"
if [ -n "$effort" ]; then
  set_effort_parts "$effort"
  if [ -n "$eff_glyph" ]; then
    model_seg="${model_seg}${GRAY} · ${eff_color}${eff_glyph} ${eff_label}${R}"
  else
    model_seg="${model_seg}${GRAY} · ${eff_label}${R}"
  fi
fi
# базовый агент называется "claude" — это не информация, показываем только свои
case "$agent" in
  ""|claude|Claude) ;;
  *) model_seg="${model_seg}${GRAY} ▸ ${agent}${R}" ;;
esac

# Контекст
ctx_color=$GREEN
[ "$used_pct" -ge "$CTX_YELLOW" ] 2>/dev/null && ctx_color=$YELLOW
[ "$used_pct" -ge "$CTX_RED" ] 2>/dev/null && ctx_color=$RED
bar=$(render_bar "$used_pct" "$BAR_LEN")
ctx_seg="${bar} ${ctx_color}${used_pct}%${R}"

# Кеш: только когда просел и только когда есть из чего считать
# (current_usage пуст в начале сессии и сразу после /compact — тогда молчим).
total_input=$((cache_read + input_tokens + cache_creation))
cache_seg=""
if [ "$total_input" -gt 0 ]; then
  cache_hit=$((cache_read * 100 / total_input))
  if [ "$cache_hit" -lt "$CACHE_SHOW" ] || [ -n "$DEBUG_ALL" ]; then
    cache_color=$YELLOW
    [ "$cache_hit" -lt "$CACHE_RED" ] && cache_color=$RED
    [ "$cache_hit" -ge "$CACHE_SHOW" ] && cache_color=$GREEN
    cache_seg="${cache_color}◎ ${cache_hit}%${R}"
  fi
fi

fmt_money() { printf '$%d.%02d' "$(($1 / 100))" "$(($1 % 100))"; }

# Деньги и сессии одним блоком: «сколько нас, сколько я, сколько все».
# Лимиты 5h/7d аккаунтные сами по себе, а стоимость в payload сессионная — при
# нескольких окнах видна только своя доля. Каждая сессия кладёт свою цифру в
# отдельный файл; живыми считаем обновлявшиеся за последние SESSION_TTL секунд.
# Долю от общего отделяем слэшем, а не скобками: скобки в правом блоке уже
# заняты временем сброса окна.
SESSION_TTL=90
alive=0
total=0
if [ -n "$sid" ]; then
  sdir="${TMPDIR:-/tmp}/claude-sessions"
  if mkdir -p "$sdir" 2>/dev/null; then
    printf '%s\n' "${cost_usd:-0}" >| "$sdir/$sid"
    for sf in "$sdir"/*; do
      [ -f "$sf" ] || continue
      mtime=$(stat -f %m "$sf" 2>/dev/null || stat -c %Y "$sf" 2>/dev/null || echo 0)
      if [ "$((now - mtime))" -gt "$SESSION_TTL" ]; then
        rm -f "$sf"          # сессия закрыта или давно молчит
        continue
      fi
      alive=$((alive + 1))
      read -r c < "$sf" 2>/dev/null || c=0
      total=$((total + ${c:-0}))
    done
  fi
fi

cost_seg=""
if [ "$alive" -gt 1 ]; then
  cost_seg="${GRAY}${G_SESSIONS} ${alive} $(fmt_money "${cost_usd:-0}")/$(fmt_money "$total")${R}"
elif [ "${cost_usd:-0}" -gt 0 ] 2>/dev/null; then
  cost_seg="${GRAY}$(fmt_money "$cost_usd")${R}"   # одна сессия — общее равно своему
fi

style_seg=""
[ "$style_name" != "default" ] && style_seg="${GRAY}⊙ ${style_name}${R}"

# --- рендер ------------------------------------------------------------------

sep="${DIM}·${R}"

add() {  # $1=аккумулятор $2=сегмент -> склейка через разделитель
  if [ -z "$2" ]; then printf '%s' "$1"
  elif [ -z "$1" ]; then printf '%s' "$2"
  else printf '%s %s %s' "$1" "$sep" "$2"
  fi
}

if [ "$cols" -lt 60 ]; then
  # узко: только кто и где по контексту
  limits=$(compute_limits "$now" 0)   # вызываем ради накопления сэмплов ETA
  out=$(add "$model_seg" "$ctx_seg")
elif [ "$cols" -lt 90 ]; then
  # средне: без ETA и без кеша
  limits=$(compute_limits "$now" 0)
  left=$(add "$model_seg" "$ctx_seg")
  right=$(add "$cost_seg" "$limits")
  out=$(join_edges "$left" "$right")
else
  # полностью
  limits=$(compute_limits "$now" 1)
  left=$(add "$model_seg" "$ctx_seg")
  [ -n "$style_seg" ] && left=$(add "$left" "$style_seg")
  right=$(add "$cache_seg" "$cost_seg")
  right=$(add "$right" "$limits")
  out=$(join_edges "$left" "$right")
fi
printf '%s' "$out"
