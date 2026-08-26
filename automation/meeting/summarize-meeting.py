#!/usr/bin/env python3
"""Саммари созвона из anarlog через Claude по подписке.

Зачем не штатной кнопкой: локальная модель в anarlog даёт около 40 баллов из 100
против эталона, Opus через `claude -p` — 86, и стоит ноль сверх подписки Max.
Подписка при этом используется по назначению: скрипт вызывает Claude Code так же,
как это делает человек, и кладёт готовый текст в базу. Никакого API-прокси.

anarlog показывает то, что лежит в session_documents с kind='template_output' —
ту же запись создаёт его собственная кнопка пересборки.

  ./summarize-meeting.py                 # все сессии без свежего саммари
  ./summarize-meeting.py <id-префикс>    # конкретная встреча
  ./summarize-meeting.py --dry-run       # показать, что будет обработано
"""

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import uuid
from pathlib import Path

DB = Path.home() / "Library/Application Support/anarlog/app.db"
PROMPT = Path(__file__).parent / "prompt.md"
TEMPLATE_ID = "tpl-work-call-ru"
DOC_TITLE = "Рабочий созвон"

# Метка в generation_metadata_json — по ней скрипт узнаёт свой документ. Нужна
# потому, что anarlog по выбору шаблона в выпадающем списке не переключает вкладку,
# а перегенерирует текущую локальной моделью — и создаёт свой template_output с тем
# же template_id. Без метки скрипт затирал бы чужую запись. Фронт этой колонки не
# читает, так что метка невидима в интерфейсе.
MARKER = "summarize-meeting"
MARKER_JSON = json.dumps({"source": MARKER})
MINE = "json_extract(generation_metadata_json, '$.source') = ?"

# Канал 0 — микрофон этой машины, там всегда её владелец: собеседники приходят
# системным звуком в канал 1. Правило постоянное, поэтому имя берём отсюда, а не
# из назначений спикеров — те могут быть не проставлены, и тогда в транскрипт
# попадёт «Участник 0.0», что заметно роняет качество саммари.
OWNER_NAME = os.environ.get("MEETING_OWNER_NAME", "Тимофей")


def db():
    if not DB.exists():
        sys.exit(f"нет базы anarlog: {DB}")
    return sqlite3.connect(f"file:{DB}?mode=ro", uri=True)


def speaker_names(con, hints, words):
    """Карта (канал, индекс спикера) → имя.

    Имена ставятся в карточке участников и попадают в speaker_hints как
    user_speaker_assignment, привязанный к конкретному слову. Через это слово
    и определяется, какому каналу и индексу спикера соответствует человек.
    """
    by_word = {w["id"]: w for w in words}
    prov = {
        h["word_id"]: json.loads(h["value"])
        for h in hints
        if h["type"] == "provider_speaker_index"
    }
    names = {}
    for h in hints:
        if h["type"] != "user_speaker_assignment":
            continue
        human_id = json.loads(h["value"]).get("human_id")
        if not human_id:
            continue
        row = con.execute("select name from humans where id=?", (human_id,)).fetchone()
        word = by_word.get(h["word_id"])
        if not row or not row[0] or not word:
            continue
        names[(word["channel"], prov.get(h["word_id"], {}).get("speaker_index"))] = row[
            0
        ]
    return names


def build_transcript(con, session_id):
    row = con.execute(
        "select words_json, speaker_hints_json from transcripts "
        "where session_id=? order by created_at desc limit 1",
        (session_id,),
    ).fetchone()
    if not row:
        return None
    words = json.loads(row[0])
    hints = json.loads(row[1])
    if not words:
        return None

    names = speaker_names(con, hints, words)
    speaker_of = {
        h["word_id"]: json.loads(h["value"])["speaker_index"]
        for h in hints
        if h["type"] == "provider_speaker_index"
    }

    # Слова хранятся поканально: сначала весь микрофон, потом системный звук.
    # Хронология восстанавливается только сортировкой.
    words.sort(key=lambda w: w["start_ms"])

    turns = []
    for w in words:
        # Канал 0 — микрофон, там всегда владелец машины. Эхо из колонок заставляет
        # диаризацию резать его на двоих, поэтому индекс спикера там игнорируем.
        key = (0, 0) if w["channel"] == 0 else (w["channel"], speaker_of.get(w["id"]))
        if turns and turns[-1]["key"] == key:
            turns[-1]["text"] += w["text"]
        else:
            turns.append({"key": key, "text": w["text"], "start": w["start_ms"]})

    lines = []
    for t in turns:
        # Канал 0 — всегда владелец машины, назначения для него не нужны. Для
        # остальных без имени пишем «Собеседник N», а не «Участник» — промпт учит
        # не приписывать роль тому, кто так подписан, иначе модель гадает
        # (см. случай, где два безымянных спикера оба стали «руководителями»).
        who = (
            OWNER_NAME
            if t["key"][0] == 0
            else (names.get(t["key"]) or f"Собеседник {t['key'][1] + 1}")
        )
        m, s = divmod(t["start"] // 1000, 60)
        lines.append(f"**[{m:02d}:{s:02d}] {who}:** {t['text'].strip()}")
    return "\n\n".join(lines)


def pending(con, only=None):
    """Сессии с транскриптом, у которых саммари нет или оно старше транскрипта."""
    rows = con.execute(
        f"""
        select s.id, s.title, t.updated_at,
               (select d.updated_at from session_documents d
                 where d.session_id = s.id and {MINE} and d.deleted_at is null
                 order by d.updated_at desc limit 1)
        from sessions s
        join transcripts t on t.session_id = s.id
        where s.deleted_at is null
        group by s.id
        order by s.created_at desc
    """,
        (MARKER,),
    ).fetchall()
    out = []
    for sid, title, t_upd, d_upd in rows:
        if only and not sid.startswith(only):
            continue
        if d_upd is None or d_upd < t_upd or only:
            out.append((sid, title or sid[:8]))
    return out


def summarize(transcript, model):
    prompt = PROMPT.read_text().replace("{TRANSCRIPT}", transcript)
    r = subprocess.run(
        ["claude", "-p", "--model", model],
        input=prompt,
        capture_output=True,
        text=True,
        check=True,
    )
    return r.stdout.strip()


def md_to_prosemirror(md):
    """anarlog хранит тело как ProseMirror и требует только h1: заголовки любого
    уровня схлопываем, иначе секция не распознаётся."""
    content, bullets = [], []

    def flush():
        if bullets:
            content.append(
                {
                    "type": "bulletList",
                    "content": [
                        {
                            "type": "listItem",
                            "content": [
                                {
                                    "type": "paragraph",
                                    "content": [{"type": "text", "text": b}],
                                }
                            ],
                        }
                        for b in bullets
                    ],
                }
            )
            bullets.clear()

    def plain(s):
        return re.sub(
            r"\*\*(.+?)\*\*", r"\1", re.sub(r"(?<!\*)\*(?!\*)(.+?)\*", r"\1", s)
        )

    for raw in md.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if m := re.match(r"^#{1,4}\s+(.*)", line):
            flush()
            content.append(
                {
                    "type": "heading",
                    "attrs": {"level": 1},
                    "content": [{"type": "text", "text": plain(m.group(1).strip())}],
                }
            )
        elif m := re.match(r"^\s*[-*]\s+(?:\[[ x]\]\s*)?(.*)", line):
            bullets.append(plain(m.group(1).strip()))
        else:
            flush()
            content.append(
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": plain(line)}],
                }
            )
    flush()
    return {"type": "doc", "content": content}


def write_summary(session_id, md):
    body = json.dumps(md_to_prosemirror(md), ensure_ascii=False)
    con = sqlite3.connect(DB)
    row = con.execute(
        f"select id from session_documents where session_id=? and {MINE} "
        "and deleted_at is null order by updated_at desc limit 1",
        (session_id, MARKER),
    ).fetchone()
    if row:
        con.execute(
            "update session_documents set body=?, title=?, template_id=?, sort_order=0, "
            "updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') where id=?",
            (body, DOC_TITLE, TEMPLATE_ID, row[0]),
        )
    else:
        ws = con.execute(
            "select workspace_id from sessions where id=?", (session_id,)
        ).fetchone()
        con.execute(
            "insert into session_documents (id, workspace_id, session_id, kind, template_id, "
            "title, body_format, body, sort_order, generation_metadata_json) "
            "values (?,?,?,?,?,?,?,?,0,?)",
            (
                str(uuid.uuid4()),
                ws[0] if ws else "",
                session_id,
                "template_output",
                TEMPLATE_ID,
                DOC_TITLE,
                "prosemirror_json",
                body,
                MARKER_JSON,
            ),
        )
    # Пустышки от anarlog: строку он заводит до обращения к модели и не убирает,
    # если та не ответила, — иначе у сессии копятся вкладки без текста. Список
    # вкладок строится без фильтра по содержимому, так что видно каждую.
    con.execute(
        "update session_documents set deleted_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') "
        "where session_id=? and kind in ('summary','template_output') "
        "and trim(body) in ('', '{}') and deleted_at is null",
        (session_id,),
    )
    con.commit()
    con.close()
    return bool(row)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument(
        "session", nargs="?", help="префикс id сессии; без него — все необработанные"
    )
    p.add_argument("--model", default="opus")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--save-to", help="каталог для копий саммари в markdown")
    a = p.parse_args()

    con = db()
    todo = pending(con, a.session)
    if not todo:
        print("нечего обрабатывать")
        sys.exit(0)

    if a.dry_run:
        for sid, title in todo:
            print(f"{sid[:8]}  {title}")
        sys.exit(0)

    for sid, title in todo:
        transcript = build_transcript(con, sid)
        if not transcript:
            print(f"× {title}: нет транскрипта")
            continue
        print(f"→ {title} ({len(transcript)} симв)")
        md = summarize(transcript, a.model)
        updated = write_summary(sid, md)
        if a.save_to:
            out = Path(a.save_to)
            out.mkdir(parents=True, exist_ok=True)
            slug = re.sub(r"[^\w\s-]", "", title).strip().replace(" ", "-")[:60]
            (out / f"{slug or sid[:8]}.md").write_text(md + "\n")
        print(f"  {'обновлено' if updated else 'создано'}: {len(md)} симв")
