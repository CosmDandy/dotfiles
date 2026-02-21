#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Fix Claude OAuth URL
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔐
# @raycast.description Берёт OAuth ссылку Claude Code из буфера, исправляет scope и копирует обратно

# Читаем из буфера
URL=$(pbpaste)

# Проверяем что это вообще claude oauth ссылка
if [[ "$URL" != *"claude.ai/oauth/authorize"* ]]; then
  osascript -e 'display notification "В буфере нет Claude OAuth ссылки" with title "Fix Claude OAuth" sound name "Basso"'
  exit 1
fi

# Проверяем нужно ли вообще фиксить
if [[ "$URL" != *"%3A"* ]] && [[ "$URL" != *"org%253A"* ]]; then
  osascript -e 'display notification "Ссылка уже корректная, исправлений не нужно" with title "Fix Claude OAuth"'
  exit 0
fi

# Исправляем двойное кодирование (%253A -> %3A -> :) в scope
# Сначала декодируем %25 -> %
FIXED_URL=$(echo "$URL" | sed 's/%253A/%3A/g')

# Теперь декодируем %3A -> : только в части scope
# Используем Python для надёжного парсинга URL
FIXED_URL=$(
  python3 - "$FIXED_URL" <<'PYEOF'
import sys
import urllib.parse

url = sys.argv[1]

# Парсим URL
parsed = urllib.parse.urlparse(url)
params = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)

# Исправляем scope: декодируем %3A -> : 
if 'scope' in params:
    fixed_scope = urllib.parse.unquote(params['scope'][0])
    params['scope'] = [fixed_scope]

# Собираем query обратно
new_query = urllib.parse.urlencode(params, doseq=True)
fixed = parsed._replace(query=new_query)
print(urllib.parse.urlunparse(fixed))
PYEOF
)

# Копируем в буфер
echo "$FIXED_URL" | pbcopy

osascript -e 'display notification "Ссылка исправлена и скопирована в буфер!" with title "Fix Claude OAuth" sound name "Glass"'
