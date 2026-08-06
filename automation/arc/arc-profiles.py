#!/usr/bin/env python3
"""Привязка Spaces браузера Arc к Chrome-профилям + снимки состояния.

Arc теряет связь Space → профиль после переустановки .app (её затирает
синхронизация, приезжающая из облака: там у Space записан профиль по
умолчанию). Сами данные профиля при этом целы, но рабочий Space открывается
на личном — без расширений, паролей и сессий. Штатной кнопки «сменить профиль
у Space» в интерфейсе нет, поэтому правим состояние напрямую.

Привязка машино-специфична: в ней хранится machineID, поэтому облако её не
подхватывает и на других устройствах она не ломается.

Одного исправленного значения мало. У каждой записи в кэше синхронизации есть
lastChangeDate; при старте Arc сверяется с облаком и, не увидев у правки более
свежей даты, разворачивает облачную версию поверх. Поэтому вместе со значением
проставляется текущая дата — тогда Arc публикует нашу версию, а не забирает
чужую.

Отдельно теряются Favorites — иконки в самом верху сайдбара. Они лежат в
контейнерах topApps, по одному на профиль, и обнуляются независимо от привязок,
поэтому эталон для них хранится отдельно и восстанавливается точечно, не
откатывая остальное состояние.

Восстанавливаются они переносом, а не вставкой. Сами контейнеры в облаке не
хранятся, а вот их содержимое — обычные элементы, которые синхронизируются:
всё, чего сервер не знает, при первом же обмене считается удалённым, и Arc
сносит это через десяток секунд после старта. Поэтому эталон нужен только как
список адресов — по ним ищется уже существующая вкладка и ей меняется родитель,
ровно как при перетаскивании мышкой. Такие иконки синхронизация не трогает.

Чего в сайдбаре нет, того и не перенести: Arc дедуплицирует по адресу и второй
вкладки с тем же URL не создаёт. Про такие apply говорит отдельной строкой —
их закрепляют руками, после чего pins-save обновляет эталон.

    arcs status            что сейчас: Spaces, профили, наполнение
    arcs snapshot          снять копию состояния
    arcs pins-save         запомнить текущие Favorites как эталон
    arcs apply             починить привязки и пустые Favorites
    arcs list              показать снимки
    arcs restore [снимок]  вернуть состояние целиком (по умолчанию последний)

Arc должен быть ЗАКРЫТ для apply и restore — иначе он перезапишет файл
из памяти, и правка пропадёт.
"""

import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

# Какой Space к какому профилю. None — профиль по умолчанию («Your Arc»).
# Имя профиля — это каталог внутри User Data, а не то, что видно в интерфейсе:
# подсмотреть можно в `arcs status`.
BINDINGS = {
    "Work": "Profile 3",
    "Research": None,
}

ARC = os.path.expanduser("~/Library/Application Support/Arc")
SIDEBAR = os.path.join(ARC, "StorableSidebar.json")
LOCAL_STATE = os.path.join(ARC, "User Data", "Local State")
SNAPSHOTS = os.path.expanduser("~/Backups/arc")
# Эталон Favorites: пополняется вручную (pins-save), а не снимком — снимки
# копят состояние как есть, включая уже потерянное.
PINS = os.path.join(SNAPSHOTS, "pins.json")


def die(msg):
    print(f"arc: {msg}", file=sys.stderr)
    sys.exit(1)


def arc_running():
    return (
        subprocess.run(
            ["pgrep", "-x", "Arc"], capture_output=True, check=False
        ).returncode
        == 0
    )


def load():
    if not os.path.exists(SIDEBAR):
        die(f"не найден {SIDEBAR}")
    with open(SIDEBAR, encoding="utf-8") as f:
        return json.load(f)


def save(data):
    mode = os.stat(SIDEBAR).st_mode & 0o777
    # Arc пишет JSON с отступами и пробелом вокруг двоеточия; повторяем стиль,
    # чтобы диффы между снимками оставались читаемыми.
    with open(SIDEBAR, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, separators=(",", " : "), ensure_ascii=False)
    os.chmod(SIDEBAR, mode)


def machine_id(data):
    """Берём machineID из состояния, а не зашиваем: он свой на каждой машине."""
    found = []

    def walk(o):
        if isinstance(o, dict):
            if "machineID" in o and isinstance(o["machineID"], str):
                found.append(o["machineID"])
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(data)
    if not found:
        die(
            "в состоянии нет ни одного machineID — нечего копировать.\n"
            "     Закрепи что-нибудь в любом профиле и повтори."
        )
    return max(set(found), key=found.count)


def spaces_of(data):
    for container in data.get("sidebar", {}).get("containers", []):
        for s in container.get("spaces", []):
            if isinstance(s, dict) and s.get("title"):
                yield s


def synced_spaces_of(data):
    """Записи Spaces в кэше синхронизации — целиком, вместе с датой изменения."""
    models = (
        data.get("firebaseSyncState", {}).get("syncData", {}).get("spaceModels", [])
    )
    for m in models:
        if (
            isinstance(m, dict)
            and isinstance(m.get("value"), dict)
            and m["value"].get("title")
        ):
            yield m


def apple_now():
    """Даты в состоянии Arc отсчитываются от 2001-01-01, а не от эпохи Unix."""
    return time.time() - 978307200


def profile_name(space):
    prof = space.get("profile") or {}
    if "custom" in prof:
        return prof["custom"].get("_0", {}).get("directoryBasename", "?")
    return None


def sidebar_items(data):
    return data["sidebar"]["containers"][1].setdefault("items", [])


def top_containers(data):
    """Контейнеры Favorites (иконки сверху) — по одному на профиль."""
    for it in sidebar_items(data):
        if not isinstance(it, dict):
            continue
        ct = (
            (it.get("data", {}) or {}).get("itemContainer", {}).get("containerType", {})
        )
        if "topApps" in ct:
            who = (
                ct["topApps"]["_0"]
                .get("custom", {})
                .get("_0", {})
                .get("directoryBasename", "Default")
            )
            yield it, who


def load_pins():
    if not os.path.exists(PINS):
        return {}
    with open(PINS, encoding="utf-8") as f:
        return json.load(f)


def item_title(item):
    """У закреплённых имя обычно не в title, а в сохранённой вкладке."""
    tab = (item.get("data", {}) or {}).get("tab") or {}
    return item.get("title") or tab.get("savedTitle") or tab.get("savedURL", "?")


def item_url(item):
    return ((item.get("data", {}) or {}).get("tab") or {}).get("savedURL") or ""


def pinned_urls(ref):
    """Адреса из эталона, в том же порядке, в каком они стояли в сайдбаре."""
    saved = {i["id"]: i for i in ref["items"]}
    return [item_url(saved[k]) for k in ref["childrenIds"] if k in saved]


def synced_items(data):
    return data["firebaseSyncState"]["syncData"]["items"]


def sync_touch(data, item, stamp, mid):
    """Объявить элемент изменённым здесь и сейчас, иначе облако вернёт своё."""
    synced = synced_items(data)
    record = {"value": item, "lastChangeDate": stamp, "lastChangedDevice": mid}
    for n, x in enumerate(synced):
        if isinstance(x, dict) and x.get("value", {}).get("id") == item["id"]:
            synced[n] = record
            return
    synced.extend([item["id"], record])


def own_containers(data, who):
    """Контейнеры тех Spaces, что открываются в этом профиле."""
    result = set()
    for space in spaces_of(data):
        if (profile_name(space) or "Default") != who:
            continue
        result.update(
            x
            for x in (space.get("containerIDs") or [])
            if isinstance(x, str) and x not in ("pinned", "unpinned")
        )
    return result


def find_tab(items, url, allowed):
    """Самая свежая вкладка с таким адресом из Spaces этого профиля.

    Берём именно существующую: выдуманный элемент сервер не знает и при первом
    же обмене сносит как удалённый, а настоящий переживает синхронизацию, даже
    если ещё не попал в локальный кэш.

    Ищем только среди своих. Один и тот же адрес нередко стоит в Favorites обоих
    профилей, а вкладка на него одна — без этого ограничения её забирает тот
    контейнер, что обработался первым, и второй остаётся ни с чем.
    """
    best = None
    for it in items:
        if not isinstance(it, dict) or "id" not in it:
            continue
        if it.get("parentID") not in allowed:
            continue
        if item_url(it).rstrip("/") != url.rstrip("/"):
            continue
        if best is None or it.get("createdAt", 0) > best.get("createdAt", 0):
            best = it
    return best


def cmd_status():
    data = load()
    items = {
        i["id"]: i
        for i in data["sidebar"]["containers"][1].get("items", [])
        if isinstance(i, dict) and "id" in i
    }

    def deep(cid, seen=None):
        seen = seen or set()
        if cid in seen or cid not in items:
            return 0
        seen.add(cid)
        kids = items[cid].get("childrenIds") or []
        return len(kids) + sum(deep(k, seen) for k in kids)

    mtime = datetime.fromtimestamp(
        os.stat(SIDEBAR).st_mtime, tz=timezone.utc
    ).astimezone()
    print(f"состояние: {SIDEBAR}")
    print(f"изменено:  {mtime:%d.%m.%Y %H:%M}")
    print(
        f"Arc сейчас {'ЗАПУЩЕН — apply/restore недоступны' if arc_running() else 'закрыт'}\n"
    )

    print(f"{'SPACE':14} {'ПРОФИЛЬ':14} {'ОЖИДАЕТСЯ':14} {'ВКЛАДОК':>8}")
    print("-" * 54)
    for s in spaces_of(data):
        actual = profile_name(s) or "Default"
        want = BINDINGS.get(s["title"], "—")
        want = want or "Default" if s["title"] in BINDINGS else "—"
        total = sum(
            deep(c) for c in (s.get("newContainerIDs") or []) if isinstance(c, str)
        )
        flag = "" if want in ("—", actual) else "  ← расходится"
        print(f"{s['title']:14} {actual:14} {want:14} {total:>8}{flag}")

    # Закреплённые сверху лежат в отдельных контейнерах, по одному на профиль.
    tops = [
        (i["id"], i)
        for i in items.values()
        if "topApps"
        in (i.get("data", {}) or {}).get("itemContainer", {}).get("containerType", {})
    ]
    if tops:
        print("\nзакреплённые сверху:")
        for cid, it in tops:
            ct = it["data"]["itemContainer"]["containerType"]["topApps"]["_0"]
            who = ct.get("custom", {}).get("_0", {}).get("directoryBasename", "Default")
            print(f"  {who:14} {deep(cid):>3}")

    with open(LOCAL_STATE, encoding="utf-8") as f:
        profiles = json.load(f).get("profile", {}).get("info_cache", {})
    print("\nпрофили Chrome:")
    for key, val in profiles.items():
        print(f"  {key:14} {val.get('name', '')}")


def cmd_snapshot(quiet=False):
    stamp = datetime.now(tz=timezone.utc).astimezone().strftime("%Y-%m-%d-%H%M%S")
    dst = os.path.join(SNAPSHOTS, stamp)
    os.makedirs(dst, exist_ok=True)
    for src in (SIDEBAR, LOCAL_STATE):
        if os.path.exists(src):
            shutil.copy2(src, dst)
    if not quiet:
        size = sum(os.path.getsize(os.path.join(dst, f)) for f in os.listdir(dst))
        print(f"снимок: {dst}  ({size // 1024} КБ)")
    return dst


def cmd_pins_save():
    """Запомнить текущие Favorites как эталон для восстановления."""
    data = load()
    ref = {}
    for cont, who in top_containers(data):
        kids = cont.get("childrenIds") or []
        by_id = {
            i["id"]: i for i in sidebar_items(data) if isinstance(i, dict) and "id" in i
        }
        ref[who] = {
            "childrenIds": list(kids),
            "items": [by_id[k] for k in kids if k in by_id],
        }
    if not any(v["childrenIds"] for v in ref.values()):
        die("Favorites пусты — сохранять нечего. Закрепи их в Arc и повтори.")
    os.makedirs(SNAPSHOTS, exist_ok=True)
    with open(PINS, "w", encoding="utf-8") as f:
        json.dump(ref, f, indent=2, ensure_ascii=False)
    for who, v in ref.items():
        print(f"  {who:14} {len(v['childrenIds'])} шт.")
        for it in v["items"]:
            print(f"      • {item_title(it)}")
    print(f"эталон: {PINS}")


def cmd_apply():
    if arc_running():
        die("Arc запущен — закрой его, иначе правка будет перезаписана из памяти")
    data = load()
    mid = machine_id(data)
    cmd_snapshot(quiet=True)

    def binding_for(title):
        profile = BINDINGS[title]
        if profile is None:
            return {"default": True}
        return {"custom": {"_0": {"machineID": mid, "directoryBasename": profile}}}

    # Дата в будущем: Arc успевает стартовать и сверить версии, и наша правка
    # всё ещё выглядит для него более свежей, чем то, что лежит в облаке.
    stamp = apple_now() + 60

    changed = []
    # Правим и рабочее состояние, и кэш синхронизации — иначе Arc может
    # развернуть в sidebar облачную версию и затереть привязку обратно.
    for space in spaces_of(data):
        title = space.get("title")
        if title in BINDINGS:
            want = binding_for(title)
            if space.get("profile") != want:
                space["profile"] = want
                changed.append(title)

    for record in synced_spaces_of(data):
        title = record["value"].get("title")
        if title in BINDINGS:
            want = binding_for(title)
            if record["value"].get("profile") != want:
                record["value"]["profile"] = want
                record["lastChangeDate"] = stamp
                record["lastChangedDevice"] = mid
                changed.append(title)

    # Favorites восстанавливаем только в опустевший контейнер: если они на
    # месте, значит пользователь мог их поменять — эталон тут не хозяин.
    pins = load_pins()
    restored = []
    missing = []
    if pins:
        items = sidebar_items(data)
        by_id = {i["id"]: i for i in items if isinstance(i, dict) and "id" in i}
        for cont, who in top_containers(data):
            ref = pins.get(who)
            if not ref or cont.get("childrenIds"):
                continue
            kept = []
            allowed = own_containers(data, who)
            for url in pinned_urls(ref):
                tab = find_tab(items, url, allowed)
                if tab is None:
                    missing.append((who, url))
                    continue
                # Перенос, а не копия: у копии новый id, которого нет на сервере,
                # и синхронизация снесёт её через десяток секунд после старта.
                old = by_id.get(tab.get("parentID"))
                if old and tab["id"] in (old.get("childrenIds") or []):
                    old["childrenIds"].remove(tab["id"])
                    sync_touch(data, old, stamp, mid)
                tab["parentID"] = cont["id"]
                kept.append(tab["id"])
                sync_touch(data, tab, stamp, mid)
            if kept:
                cont["childrenIds"] = kept
                sync_touch(data, cont, stamp, mid)
                restored.append((who, len(kept)))

    if not changed and not restored and not missing:
        print("всё на месте, чинить нечего")
        return
    save(data)
    with open(SIDEBAR, encoding="utf-8") as f:
        json.load(f)  # проверка, что файл читается
    for title in sorted(set(changed)):
        print(f"  профиль: {title} → {BINDINGS[title] or 'Default'}")
    for who, n in restored:
        print(f"  Favorites: {who} ← {n} шт. перенесено")
    for who, url in missing:
        print(f"  Favorites: {who} — нет вкладки {url}, закрепи руками")
    print("готово, запускай Arc")


def cmd_list():
    if not os.path.isdir(SNAPSHOTS):
        print("снимков нет")
        return
    for name in sorted(os.listdir(SNAPSHOTS), reverse=True):
        path = os.path.join(SNAPSHOTS, name)
        if os.path.isdir(path):
            size = sum(os.path.getsize(os.path.join(path, f)) for f in os.listdir(path))
            print(f"  {name}  {size // 1024} КБ")


def cmd_restore(which=None):
    if arc_running():
        die("Arc запущен — закрой его перед восстановлением")
    if not os.path.isdir(SNAPSHOTS):
        die("снимков нет")
    snaps = sorted(
        d for d in os.listdir(SNAPSHOTS) if os.path.isdir(os.path.join(SNAPSHOTS, d))
    )
    if not snaps:
        die("снимков нет")
    name = which or snaps[-1]
    src = os.path.join(SNAPSHOTS, name, "StorableSidebar.json")
    if not os.path.exists(src):
        die(f"в снимке {name} нет StorableSidebar.json")
    cmd_snapshot(quiet=True)  # текущее состояние тоже сохраняем
    shutil.copy2(src, SIDEBAR)
    print(f"восстановлено из {name}, запускай Arc")


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    if cmd == "status":
        cmd_status()
    elif cmd == "snapshot":
        cmd_snapshot()
    elif cmd == "pins-save":
        cmd_pins_save()
    elif cmd == "apply":
        cmd_apply()
    elif cmd == "list":
        cmd_list()
    elif cmd == "restore":
        cmd_restore(args[1] if len(args) > 1 else None)
    else:
        die(
            f"неизвестная команда {cmd!r}. Доступно: status, snapshot, apply, list, restore"
        )


if __name__ == "__main__":
    main()
