# x3550 M3: UEFI изнутри (ревизия по SOL)

Инвентарь настроек UEFI Setup домашнего IBM x3550 M3, снятый удалённо
через SOL, и приём «как водить BIOS роботом». Про сам SOL и ipmitool —
[ipmi-sol.md](ipmi-sol.md).

## Приём: UEFI через tmux

SOL — сырой ANSI-поток, но tmux держит виртуальный экран, поэтому
консолью можно управлять программно (или чужими руками — Claude ездил
по меню именно так):

```bash
# SOL живёт в панели tmux; дальше — клавиши туда и чтение экрана:
tmux send-keys -t <sess>:<win>.<pane> Down   # стрелки: Up/Down/Left/Right
tmux send-keys -t ... Enter
tmux send-keys -t ... Escape                 # после Esc — пауза 2-3 сек!
tmux capture-pane -p -t ...                  # снять отрисованный экран
```

Правила выживания:

- после каждой клавиши — пауза (SOL буферизует, UEFI рисует медленно);
  после Esc — особенно: он неоднозначен (см. Esc-раздел в ipmi-sol.md);
- каждый шаг сверять capture-pane'ом: стрелки легко открывают
  выпадашку выбора значения вместо перехода — закрывать её Esc;
- **выходить из Setup всегда через `N` (Exit without Saving)**, если
  не менял ничего сознательно: UEFI может посчитать «изменением»
  фантомные Esc-последовательности и предложить сохранить;
- не подводить курсор с Enter к `Load Default Settings`, `Reset IMM
  to Defaults`, `Reset IMM`.

## Структура меню

Главное: System Information / System Settings / Date and Time / Start
Options / Boot Manager / System Event Logs / User Security / Save /
Restore / Load Defaults / Exit.

System Settings: Processors / Memory / Devices and I/O Ports (здесь
Console Redirection) / Power / Operating Modes / Legacy Support /
Integrated Management Module / System Security / Adapters and UEFI
Drivers / Network.

## Паспорт (июль 2026)

| | |
|---|---|
| Модель | 7944KHG, s/n KD55ALW |
| CPU | 2× Xeon X5675: 6C/12T, 3.07 GHz, 12 MB L3 — итого 12C/24T |
| RAM | 192 GB (18/18 DIMM, все Present+Enabled) |
| Скорость RAM | **800 MHz** — потолок при 3 DIMM на канал, настройкой не поднять |
| NUMA | Socket Interleave = NUMA (правильно для Linux/Proxmox) |
| Сеть | 4 onboard-порта (2 двухпортовых контроллера) |

## Что настроено (и как)

**Processors**: VT-x + VT-d Enable (виртуализация готова), Turbo
Enable, Performance States Enable, Power C-States Disable (латентность
важнее ватт), Execute Disable Enable, QPI Max Performance.

**Memory**: Max Performance, LV-DIMM Enhanced Performance (1.5V ради
скорости), Patrol Scrub + Demand Scrub Enable — фоновый скраб и есть
то, что ловило сбойный DIMM 6 до чистки контактов. Channel Mode
Independent (вся ёмкость, без зеркала).

**Power**: AEM Capping Enabled, Power Restore Policy Restore
(после пропажи питания вернётся в прежнее состояние), ASPM Disable.

**Operating Modes**: Custom — всё вручную в максимум. Quiet Boot
Enable, POST Attempts Limit 3.

**IMM**: Reboot on NMI Enable; POST Watchdog Timer — **выключен**.

**Network → Network Boot Configuration**: PXE на первом порту —
`UEFI and Legacy Support`, IPv4 (PXE-стенд обслужен в оба режима).

**Boot order** (по факту загрузки): CD/DVD → Floppy → дальше
диски/PXE.

## Глоссарий настроек

- **Quiet Boot** — не звук: прячет текст POST за логотипом. Для SOL
  выгоден Disable — в консоли текст полезнее псевдографики.
- **Watchdog Timer** — аппаратный обратный отсчёт: софт обязан его
  периодически сбрасывать; завис и не сбросил — железо принудительно
  перезагружает. Всегда контракт «таймер + конкретный гладильщик»:
  прежде чем включать, знать, кто обязан сбрасывать и существует ли он.
  - **POST Watchdog** (UEFI → IMM-меню): гладит сама прошивка —
    взводится на старте POST, снимается по его завершении. При
    нормальной загрузке незаметен, срабатывает только на реально
    зависшем POST. Включать безопасно, циклов ребута не даёт.
  - **OS/IPMI watchdog** (`ipmitool mc watchdog get`, в IMM —
    Server Timeouts): гладить обязан демон в ОС (`/dev/watchdog`).
    Включить без демона = ресет каждые N минут по кругу —
    классические грабли. Настраивать только вместе с демоном.
- **P-states** (Performance States) — сброс частоты/напряжения при
  простое. **Turbo** — разгон выше номинала при тепловом запасе.
  **C-states** — глубина сна простаивающих ядер: глубже сон → больше
  экономия → дольше просыпаться. C-states Disable = стабильная
  латентность ценой ватт.
- **NUMA** — у каждого CPU свой контроллер и свои 9 DIMM: «своя»
  память быстрая, «чужая» — через QPI, медленнее. Socket Interleave =
  NUMA — сказать ОС правду (планировщик держит процесс у его памяти);
  Interleave — чередовать адреса для NUMA-неосведомлённых ОС.
  Проверка в Linux: `numactl --hardware` — два узла по 96 GB.
- **Legacy vs UEFI boot** — legacy: прошивка прыгает в MBR; UEFI:
  запускает `.efi` с FAT-раздела. PXE-серверу отдавать разные файлы:
  `pxelinux.0` (legacy) / `*.efi` (UEFI). На M3 глобального
  переключателя нет: per-NIC — Network Boot Configuration → PXE Mode;
  глобально — Boot Manager → Change Boot Order, псевдо-пункт
  **«Legacy Only»**: всё после него в списке грузится legacy.

## Что можно улучшить

- [ ] **POST Watchdog Timer → включить** (IMM-меню): headless-сервер
  с зависшим POST перезагрузит себя сам, не понадобится ехать к нему.
- [ ] Quiet Boot → Disable: в SOL видно больше диагностики POST
  вместо логотипа. Косметика, но для serial-жизни удобнее.
- [ ] Память на 800 MHz — осознанный трейд-офф (192 GB > скорость);
  хочется быстрее — вынимать до 2 DIMM на канал (12 плашек, 1066+).
- Всё остальное (виртуализация, скраб, NUMA, PXE) уже настроено
  правильно — менять нечего.
