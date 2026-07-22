# Настройки, которые не ложатся в конфиги

Всё, что придётся повторить руками при переустановке системы, и почему это
нельзя объявить декларативно. Источник истины для чек-листов —
`platform/macos/install-extra.sh`, здесь то же самое, но с объяснением причин
и в читаемом виде.

## Почему это вообще существует

Три разные причины, и лечатся они по-разному.

**Права TCC.** Accessibility, запись экрана, микрофон, мониторинг ввода. macOS
принципиально не даёт выдать их скриптом — только руками в System Settings,
либо профилем MDM на управляемой машине. Это не недоработка, это защита от
именно такого сценария.

**Логины.** Учётки, OAuth, двухфакторка. Автоматизировать можно было бы через
Bitwarden (`rbw` в системе есть), но веб-логины всё равно интерактивные.

**Настройки внутри приложения.** Часть приложений хранит их в своём формате, а
не в `defaults`. У Things, например, домен `com.culturedcode.ThingsMac` состоит
целиком из позиций окон — ни одной настройки. Raycast держит своё в
зашифрованной sqlite.

---

## Права, которые надо выдать

Порядок один: System Settings → Privacy & Security → нужный раздел → добавить
приложение. После установки системы это самая длинная часть.

| Право | Кому нужно | Что сломается без него |
|---|---|---|
| Accessibility | AeroSpace, Karabiner, CleanShot X, SuperWhisper, `bt-layout-switch` | оконный менеджер не двигает окна, переключение раскладки не работает |
| Screen Recording | CleanShot X, Screen Studio, Teams | скриншоты и запись пустые |
| Microphone | SuperWhisper, Teams, Spokenly | диктовка молчит |
| Input Monitoring | Karabiner, Leader Key | не ловятся горячие клавиши |
| Bluetooth | `bt-layout-switch` | не видит клавиатуру, раскладка не переключается |
| Full Disk Access | Onyx, CleanShot X | |
| «Разрешить включать раскладку» | `bt-layout-switch` | выдаётся отдельным диалогом, см. ниже |

Karabiner дополнительно требует одобрить системное расширение в
Login Items & Extensions — это отдельный шаг, драйвер уровня ядра.

### Отдельно про раскладку

`platform/macos/install-bt-layout.sh` запрашивает три разрешения и печатает
инструкцию по каждому. Диалог «allow enabling keyboard layout» вызывается явно:

    automation/launchd/scripts/bt-layout-switch.app/Contents/MacOS/bt-layout-switch --request-layout-permission

MAC-адрес клавиатуры прописывается в `automation/launchd/config/bt-layout.conf`
и на новой клавиатуре меняется — узнать можно тем же бинарём с
`--list-devices`.

---

## Логины

Ни один не автоматизируется. Пароли — в Bitwarden, доставать через `rbw get`.

Raycast · Obsidian · Timing · Arc · Cursor · ChatGPT · Claude · WhatsApp ·
Microsoft Teams · Things Cloud · Telegram (**два** аккаунта, личный и рабочий)

---

## Настройки по приложениям

### OrbStack
Автоматизировано — `tools/orbstack/apply.sh` вызывается хуком активации
`applyOrbstack`. Руками ничего не нужно.

### Leader Key
- Shortcut → F10
- Theme → Breadcrumbs
- Launch at login → on
- Activation → Reset group selection
- Show Leader Key in menubar → off
- Force English keyboard layout → on

Сам конфиг раскладки меню — в репозитории (`tools/leader-key/config.json`),
подключается симлинком. Руками только настройки самого приложения.

### CleanShot X
- Start at login → on
- Menu bar: show icon → off
- Desktop icons: hide while capturing → on
- Copy file to clipboard: screenshot → on
- Auto-close → on
- Retina: scale videos to 1x → on
- Do Not Disturb while recording → on
- Dim screen while recording → off
- Max resolution 1080p, video FPS 25
- Freeze screen when taking a screenshot → on
- Automatically check for updates → off

Перехватывает горячие клавиши скриншотов и полностью заменяет системный
скриншотер — поэтому системный `screencapture` в конфиге не настраивается.

### SuperWhisper
- Create mode → Voice to text → Voice Model → Ultra V3 Turbo
- Toggle Recording → Command + F1
- Automatically check for updates → off
- Launch on login → on
- Mini Recording window → on, always show → off
- Show in Dock → off
- Dynamic normalization → on

Модель Ultra V3 Turbo нужно скачать внутри приложения — это гигабайты, не
скрипт.

### Things 3
- Счётчик в Dock → Сегодня + Входящие
- Группировать задачи в «Сегодня» по проектам → on
- Быстрый ввод: `Cmd+F2`, быстрый ввод с заполнением: `Cmd+F3`
- Показывать события календаря в «Сегодня» и «Планах» → on
- Things Cloud → Sync

### Raycast
- Import Data — восстановить из встроенного экспорта Raycast

Свои настройки Raycast хранит в зашифрованной sqlite, и вычитать их снаружи
нельзя — но у него есть собственный экспорт/импорт, им и пользуемся. Стоит
проверить, что файл экспорта лежит в каталоге, попадающем в
`automation/backup/manifest.conf` (`~/Documents`, `~/Projects`, `~/Work`);
иначе он не бэкапится ничем.

**Отдельный пункт, который легко забыть:** каталоги со script-командами нужно
зарегистрировать вручную — Extensions → Script Commands → добавить
`~/.dotfiles/tools/leader-key` и `~/.dotfiles/tools/aerospace`. Без этого
перестанут работать пункты меню Leader Key, которые дёргают
`raycast://script-commands/...`: рабочий профиль, профиль разработки,
переключение AeroSpace, скринсейвер, переключение встроенного дисплея.

### Karabiner-Elements
- Disable the built-in keyboard while this device is connected → on

### Flux
- Pick location (Москва)

### AeroSpace
- Experimental UI Settings → on

Оконные правила целиком в `tools/aerospace/.aerospace.toml`, руками только эта
галка.

### Logi Options+
- Спарить MX Master по Bluetooth
- Восстановить настройки из резервной копии

Привязано к железу, автоматизировать нечем.

### BetterDisplay
Настройки восстанавливаются импортом из `tools/betterdisplay/BetterDisplay.plist`
— это делает `install-extra.sh`. Но привязка к дисплеям идёт по UUID железа,
поэтому на свежей системе может понадобиться один раз перелинковать монитор:
Settings → transfer settings of a disconnected display to a connected one.

Если импорт не подхватился, целевое состояние такое: Mi Monitor — HiDPI on,
Full EDID match, 59.95 Hz, 2560×1440; встроенный — 1280×800; группы Work/Home
с Layout Protection и синхронизацией яркости.

### iStatistica Pro
- Скачать iStatistica Sensors Plugin внутри приложения (+ Accessibility)

---

## Приложения, которые ставятся не из brew и не из nix

Скачиваются вручную по ссылкам, которые открывает `install-extra.sh`, и
перетаскиваются в `/Applications`:

Final Cut Pro · Capture One · iStatistica Pro · Network Radar · Kaleidoscope ·
Screen Studio · Transmit · CleanShot X · SuperWhisper · Things 3 · Logi Options+

---

## Что уже пробовали автоматизировать и почему отказались

Была попытка перенести настройки приложений в репозиторий через
`defaults export` / `defaults import` — по образцу того, как это сделано для
BetterDisplay. Ручных пунктов становилось 43 вместо 72. Откатили, причины:

1. **Домены содержат не только настройки.** У CleanShot X в `mediaHistory`
   лежат заголовки окон последних скриншотов. Снимок окна рабочего проекта
   отправил бы в публичный репозиторий имя клиента или тикета.
2. **`defaults export` пишет бинарный plist.** Git показывает
   «Binary files differ» — проверить содержимое диффом невозможно, gitleaks
   сканирует вслепую.
3. **Экспорт не отличает настройки от состояния.** У Things домен оказался
   целиком позициями окон, а настройки лежат внутри приложения.

Первые две проблемы решаются конвертацией в XML и вычисткой ключей по шаблону,
третья — нет: подход требует ручного разбора каждого приложения.

Если возвращаться к этому, то точечно: у Leader Key домен содержит ровно те
шесть пунктов чек-листа (`KeyboardShortcuts_navigate`, `theme`,
`showInMenubar`, `forceEnglishKeyboardLayout`, `reactivateBehavior`), у Flux —
`location`, `lateColorTemp`, `wakeTime`. Эти два автоматизируются чисто.
