# Overnight — отложенная автономная работа Claude Code

> **Статус: черновик, НЕ протестировано.** Механизм-заготовка, чтобы запускать
> большие задачи «пока я сплю». Перед боевым запуском прочитай рейлы и проверь под себя.

## Зачем

Иногда упираешься в лимит токенов или хочешь, чтобы агент отработал ночью и к утру
были готовые коммиты. Здесь — заготовка такого флоу: очередь задач + headless-runner,
который дёргается по расписанию в окно **после сброса лимитов**.

## Как «само себя запустить» — честно

Два способа, и оба **не магия вокруг квоты**:

1. **Внутри живой сессии.** У ассистента есть таймеры (`ScheduleWakeup`, durable
   `CronCreate` — переживает рестарт, пишется в `.claude/scheduled_tasks.json`). Но
   срабатывают только пока процесс жив и REPL простаивает. Закрыл сессию — не выстрелит.
   Хрупко: годится, если оставляешь открытый терминал.
2. **На уровне ОС (надёжно, этот каталог про него).** `systemd-timer`/`cron` запускает
   `claude -p` headless: новый процесс в назначенное время, без живой сессии.

**Главная засада — лимит, а не триггер.** Любой headless-прогон ест ту же квоту
аккаунта. Упёрся в лимит — таймер выстрелит, но работа встанет до сброса. Поэтому
расписание выравнивай строго под окно сброса; `overnight.sh` ещё и делает бэкофф-ретраи.

## Состав

| файл | что |
|------|-----|
| `overnight.sh` | runner: берёт `queue/*.task.md`, гонит `claude -p` на выделенной ветке, лог + перенос в `done/` |
| `overnight.timer` / `overnight.service` | systemd-user юниты (расписание) |
| `queue/EXAMPLE.task.md` | формат файла-задачи (просто промпт + DoD) |
| `overnight-skill.draft.md` | черновик скилла `/overnight` для интерактива и headless |

## Использование

```sh
# разовый прогон одной задачи
tools/claude/overnight/overnight.sh --once tools/claude/overnight/queue/my.task.md

# обработать всю очередь
tools/claude/overnight/overnight.sh
```

Поставить на расписание (systemd --user):

```sh
mkdir -p ~/.config/systemd/user
ln -sf ~/dotfiles/tools/claude/overnight/overnight.service ~/.config/systemd/user/
ln -sf ~/dotfiles/tools/claude/overnight/overnight.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now overnight.timer
systemctl --user list-timers overnight.timer
```

Либо cron:

```cron
30 4 * * * /home/vscode/dotfiles/tools/claude/overnight/overnight.sh >> ~/.local/state/overnight/cron.log 2>&1
```

## Рейлы (зашиты в runner и в системный промпт)

- никогда не работать прямо в `master`/`main` — создаётся ветка `overnight/<ts>`;
- белый список инструментов (`OVERNIGHT_TOOLS`) — остальное заблокировано даже при `--dangerously-skip-permissions`;
- `flock` против параллельных запусков; бэкофф при rate-limit;
- атомарные коммиты + push каждого; без деструктива и без мёржа в master.

> `--dangerously-skip-permissions` нужен, чтобы не висеть на подтверждениях ночью.
> Это снимает запросы, поэтому страховка — выделенная ветка + dev-окружение, которое
> не жалко. Не запускай это на проде/в важном репо без доп. изоляции (контейнер/worktree).

## Альтернативы

- **GitHub Actions + Claude Code Action на `schedule:`** — прогон в CI, без твоей
  машины, результат — PR. Часто самый надёжный «ночной» вариант.
- **Autonomous-loop** — промпт, который в конце сам планирует следующее пробуждение
  (`ScheduleWakeup`), держит цикл живым в простое.
- **Очередь задач** (этот каталог) — кладёшь спеки в `queue/`, runner берёт по одной.

## TODO перед боевым использованием

- [ ] протестировать `overnight.sh --once` на безопасной задаче;
- [ ] проверить флаги `claude` под свою версию CLI (`claude --help`);
- [ ] решить про изоляцию (worktree/контейнер) при skip-permissions;
- [ ] перенести `overnight-skill.draft.md` в `custom`-submodule как `skills/overnight/SKILL.md`.
