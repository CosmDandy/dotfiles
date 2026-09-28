"""Behaviour tests for session-metrics.py on a synthetic transcript.

    python3 -m unittest tools/claude/metrics/test_session_metrics.py
"""

import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "session_metrics", os.path.join(HERE, "session-metrics.py")
)
sm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sm)


def user(text, ts="2026-09-27T00:00:00Z"):
    return {"type": "user", "timestamp": ts, "sessionId": "abcdef12-x",
            "message": {"role": "user", "content": text}}


def result(text, error=False, denial=None):
    rec = {"type": "user", "sessionId": "abcdef12-x",
           "message": {"role": "user", "content": [
               {"type": "tool_result", "tool_use_id": "t", "content": text,
                "is_error": error}]}}
    if denial:
        rec["toolDenialKind"] = denial
    return rec


def assistant(blocks, ctx=1000, out=10, model="m1", mid=None):
    return {"type": "assistant", "sessionId": "abcdef12-x",
            "message": {"role": "assistant", "model": model, "content": blocks,
                        "id": mid,
                        "usage": {"input_tokens": ctx, "cache_read_input_tokens": 0,
                                  "cache_creation_input_tokens": 0,
                                  "output_tokens": out}}}


def text(t):
    return {"type": "text", "text": t}


def tool(name, **inp):
    return {"type": "tool_use", "name": name, "input": inp}


def turn_ms(ms):
    return {"type": "system", "subtype": "turn_duration", "durationMs": ms}


RU = "Здесь длинный русский текст, чтобы язык определился однозначно и точно."
EN = "This is a long English sentence so the language check is unambiguous."

TRANSCRIPT = [
    user("сделай"),
    assistant([text("Какой хост брать?")]),  # question before any tool
    user("любой"),
    assistant([text(RU), tool("Read", file_path="a.py")]),  # full read
    result("ok"),
    # one batched API message, streamed as two records sharing message.id
    assistant([tool("Read", file_path="a.py", offset=1, limit=10)],
              out=900, mid="m-batch"),
    assistant([tool("Bash", command="ls")], out=900, mid="m-batch"),
    {"type": "user", "isMeta": True, "sessionId": "abcdef12-x",
     "message": {"role": "user", "content": "goal check-in"}},
    user("<task-notification>agent done</task-notification>"),
    result("ok"),
    result("ok"),
    assistant([tool("Bash", command="cat > x.txt <<'EOF'\nhi\nEOF")]),
    result("touching private keys", error=True, denial="permission-rule"),
    assistant([tool("Bash", command="ls")]),  # repeat of "ls"
    result("Permission to use Bash has been denied", error=True,
           denial="permission-rule"),
    assistant([tool("AskUserQuestion", questions=[])]),
    result("no", error=True, denial="user-rejected"),
    assistant([tool("Bash", command="git commit -m 'feat: add thing'")]),
    result("ok"),
    assistant([tool("Bash", command='git commit -m "fix: чиню"')]),
    result("ok"),
    assistant([tool("Bash", command="sed -i '' 's/a/b/' f.txt")]),
    result("Exit code 1", error=True),
    {"type": "system", "subtype": "compact_boundary"},
    turn_ms(60000),
    turn_ms(30000),
    assistant([text(EN + "\n```py\nx=1\n```\n")], ctx=250000, out=500),
    assistant([text("✔ done: всё готово\n! found: одна мелочь\n\nresult: сделано")],
              model="m2"),
    {"type": "assistant", "isSidechain": True, "sessionId": "abcdef12-x",
     "message": {"model": "m1", "content": [tool("Bash", command="rm -rf /")]}},
]


class MetricsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fd, cls.path = tempfile.mkstemp(suffix=".jsonl")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            for rec in TRANSCRIPT:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
            fh.write("this is not json\n")
        cls.m = sm.analyze(cls.path)

    @classmethod
    def tearDownClass(cls):
        os.unlink(cls.path)

    def test_counts(self):
        m = self.m
        self.assertEqual(m["sid"], "abcdef12")
        self.assertEqual(m["model"], "m1")
        self.assertEqual(m["human_turns"], 2)  # meta and <…> records skipped
        self.assertEqual(m["assistant_msgs"], 11)  # m-batch counted once
        self.assertEqual(m["tool_calls"], 9)  # the sidechain call is skipped
        self.assertEqual(m["questions_before_work"], 1)
        self.assertEqual(m["ask_user_question"], 1)

    def test_files_policy(self):
        m = self.m
        self.assertEqual(m["read_full"], 1)
        self.assertEqual(m["heredoc_writes"], 1)
        self.assertEqual(m["sed_i"], 1)
        self.assertEqual(m["repeat_commands"], 1)

    def test_denials(self):
        m = self.m
        self.assertEqual(m["denials"], 3)
        self.assertEqual(m["hook_denials"], 1)
        self.assertEqual(m["errors"], 4)

    def test_language(self):
        m = self.m
        self.assertEqual(m["commits"], 2)
        self.assertEqual(m["commits_en"], 1)
        self.assertEqual(m["chat_ru_share"], 0.67)  # RU, EN, final report
        self.assertEqual(m["code_fences"], 1)

    def test_interstitial_narration(self):
        # RU text precedes a Read in the same turn; EN text precedes the final
        # report with no tool call between — only the first is chatter
        self.assertEqual(self.m["interstitial_texts"], 1)

    def test_report(self):
        m = self.m
        self.assertEqual(m["report_lines"], 3)
        self.assertEqual(m["report_blocks"], 2)
        self.assertTrue(m["final_signal"])

    def test_batching_and_budget(self):
        m = self.m
        # 8 tool turns, one of them with two calls
        self.assertEqual(m["single_call_share"], round(7 / 8, 2))
        self.assertEqual(m["ctx_peak_k"], 250)
        self.assertEqual(m["out_k"], 1)  # 9*10 + 900 (once) + 500 = 1490
        self.assertEqual(m["turn_min"], 1.5)
        self.assertEqual(m["compactions"], 1)

    def test_summary_groups_by_model(self):
        rows = [dict(self.m), dict(self.m, model="m2", report_lines=30)]
        s = {r["model"]: r for r in sm.summary(rows)}
        self.assertEqual(s["m1"]["sessions"], 1)
        self.assertEqual(s["m2"]["report_lines"], 30)
        self.assertEqual(s["m1"]["final_signal"], 1.0)


if __name__ == "__main__":
    unittest.main()
