import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

script = Path(__file__).resolve().parents[1] / "claude/skills/memory-consolidate/scripts/cross_check.py"


def write_jsonl(path, records):
    path.write_text("".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records), encoding="utf-8")


class CrossCheckTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.work = Path(self.directory.name)
        (self.work / "text/memory").mkdir(parents=True)

    def tearDown(self):
        self.directory.cleanup()

    def run_check(self, command):
        result = subprocess.run([sys.executable, str(script), command, str(self.work)],
                                capture_output=True, text=True)
        return result.returncode, result.stdout

    def write_memory(self, body):
        (self.work / "text/memory/a.md").write_text(body, encoding="utf-8")

    def claim(self, number, quote, source="memory", file="memory/a.md"):
        return {"file": file, "id": f"{file}#{number}", "source": source, "subject": "s", "condition": "",
                "assertion": "a", "quote": quote}


class ExtractionTest(CrossCheckTest):
    def test_passes_when_every_sentence_is_quoted(self):
        self.write_memory("---\nname: a\n---\n\n# 見出し\n\n- 一つ目の文です。二つ目の\n  文です。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "一つ目の文です"), self.claim(2, "二つ目の文です")])
        self.assertEqual(self.run_check("extraction"), (0, ""))

    def test_reports_a_sentence_no_quote_covers(self):
        self.write_memory("- 一つ目の文です。取り出し忘れた文です。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "一つ目の文です")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("memory/a.md:1", out)
        self.assertIn("取り出し忘れた文です", out)

    def test_accepts_a_sentence_recorded_as_not_a_claim(self):
        self.write_memory("- 一つ目の文です。経緯だけの文です。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "一つ目の文です")])
        write_jsonl(self.work / "skipped.jsonl", [{"file": "memory/a.md", "text": "経緯だけの文です", "reason": "経緯"}])
        self.assertEqual(self.run_check("extraction"), (0, ""))

    def test_reports_a_quote_missing_from_the_text(self):
        self.write_memory("- 一つ目の文です。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "一つ目の文です"), self.claim(2, "本文に無い引用")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("memory/a.md#2", out)

    def test_reports_a_sentence_whose_words_appear_only_inside_another_quote(self):
        self.write_memory("- 保存する。失敗時は別の場所に保存する。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "保存する")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("uncovered memory/a.md:1 失敗時は別の場所に保存する", out)

    def test_reports_a_quote_that_matches_two_sentences_equally(self):
        self.write_memory("- 保存する。\n- 保存する。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "保存する")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("ambiguous-quote memory/a.md#1", out)

    def test_accepts_a_sentence_contained_in_another_when_the_line_is_given(self):
        self.write_memory("- 本文から取ります。値は本文から取ります。\n- 値は本文から取ります\n")
        write_jsonl(self.work / "claims.jsonl", [
            {**self.claim(1, "本文から取ります"), "line": 1},
            {**self.claim(2, "値は本文から取ります"), "line": 1},
            {**self.claim(3, "値は本文から取ります"), "line": 2},
        ])
        self.assertEqual(self.run_check("extraction"), (0, ""))

    def test_accepts_a_line_hint_for_a_sentence_on_a_continuation_line(self):
        self.write_memory("- 前置きの文です。\n  値は本文から取ります。\n- 値は本文から取ります\n")
        write_jsonl(self.work / "claims.jsonl", [
            self.claim(1, "前置きの文です"),
            {**self.claim(2, "値は本文から取ります"), "line": 2},
            {**self.claim(3, "値は本文から取ります"), "line": 3},
        ])
        self.assertEqual(self.run_check("extraction"), (0, ""))

    def test_reports_a_skipped_sentence_without_a_reason(self):
        self.write_memory("- 一つ目の文です。経緯だけの文です。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "一つ目の文です")])
        write_jsonl(self.work / "skipped.jsonl", [{"file": "memory/a.md", "text": "経緯だけの文です", "reason": ""}])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("経緯だけの文です", out)

    def test_reports_two_claims_with_the_same_id(self):
        self.write_memory("- 赤を使う。青を使う。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "赤を使う"), self.claim(1, "青を使う")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("duplicate-id memory/a.md#1", out)

    def test_reports_an_english_sentence_no_quote_covers(self):
        self.write_memory("- Use the cache. Never retry on failure.\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "Use the cache")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("Never retry on failure", out)

    def test_reports_an_english_sentence_on_the_next_line(self):
        self.write_memory("Use the cache.\nNever retry on failure.\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "Use the cache")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("Never retry on failure", out)

    def test_reports_a_quote_that_runs_into_the_next_sentence(self):
        self.write_memory("- 保存する。失敗時は通知する。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "保存する。失敗時")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("失敗時は通知する", out)

    def test_accepts_a_quote_that_includes_the_full_stop(self):
        self.write_memory("- 一つ目の文です。二つ目の文です。\n")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "一つ目の文です。"), self.claim(2, "二つ目の文です")])
        self.assertEqual(self.run_check("extraction"), (0, ""))

    def test_reports_a_listed_file_with_no_claims(self):
        self.write_memory("- 一つ目の文です。\n")
        (self.work / "text/memory/b.md").write_text("- 別の文です。\n", encoding="utf-8")
        write_jsonl(self.work / "claims.jsonl", [self.claim(1, "一つ目の文です")])
        code, out = self.run_check("extraction")
        self.assertEqual(code, 1)
        self.assertIn("memory/b.md:1", out)


class JudgmentsTest(CrossCheckTest):
    def setUp(self):
        super().setUp()
        write_jsonl(self.work / "claims.jsonl", [
            self.claim(1, "q1"),
            self.claim(2, "q2"),
            self.claim(1, "q3", source="instruction", file="dotfiles/AGENTS.md"),
        ])
        write_jsonl(self.work / "topics.jsonl", [
            {"id": "memory/a.md#1", "topics": ["保存", "起動"]},
            {"id": "memory/a.md#2", "topics": ["保存"]},
            {"id": "dotfiles/AGENTS.md#1", "topics": ["保存"]},
        ])
        self.complete = [
            {"id": "memory/a.md#1", "topic": "保存",
             "pairs": [{"with": "dotfiles/AGENTS.md#1", "verdict": "contradiction", "note": "n"}], "outside": []},
            {"id": "memory/a.md#1", "topic": "起動", "pairs": [], "outside": []},
            {"id": "memory/a.md#2", "topic": "保存", "pairs": [], "outside": []},
        ]

    def test_passes_when_every_pair_of_claim_and_topic_has_one_line(self):
        write_jsonl(self.work / "judgments.jsonl", self.complete)
        self.assertEqual(self.run_check("judgments"), (0, ""))

    def test_reports_a_claim_without_a_topic(self):
        write_jsonl(self.work / "topics.jsonl", [
            {"id": "memory/a.md#1", "topics": ["保存", "起動"]},
            {"id": "memory/a.md#2", "topics": ["保存"]},
        ])
        write_jsonl(self.work / "judgments.jsonl", self.complete)
        code, out = self.run_check("judgments")
        self.assertEqual(code, 1)
        self.assertIn("dotfiles/AGENTS.md#1", out)

    def test_reports_a_missing_line_for_one_of_two_topics(self):
        write_jsonl(self.work / "judgments.jsonl", [self.complete[0], self.complete[2]])
        code, out = self.run_check("judgments")
        self.assertEqual(code, 1)
        self.assertIn("memory/a.md#1", out)
        self.assertIn("起動", out)

    def test_reports_two_lines_for_the_same_claim_and_topic(self):
        write_jsonl(self.work / "judgments.jsonl", self.complete + [self.complete[2]])
        code, out = self.run_check("judgments")
        self.assertEqual(code, 1)
        self.assertIn("memory/a.md#2", out)

    def test_reports_a_line_for_an_instruction_claim(self):
        write_jsonl(self.work / "judgments.jsonl", self.complete + [
            {"id": "dotfiles/AGENTS.md#1", "topic": "保存", "pairs": [], "outside": []}])
        code, out = self.run_check("judgments")
        self.assertEqual(code, 1)
        self.assertIn("dotfiles/AGENTS.md#1", out)

    def test_reports_a_partner_that_is_not_in_the_list(self):
        lines = [dict(line) for line in self.complete]
        lines[2] = {"id": "memory/a.md#2", "topic": "保存",
                    "pairs": [{"with": "memory/a.md#9", "verdict": "duplicate", "note": "n"}], "outside": []}
        write_jsonl(self.work / "judgments.jsonl", lines)
        code, out = self.run_check("judgments")
        self.assertEqual(code, 1)
        self.assertIn("memory/a.md#9", out)

    def test_reports_an_outside_topic_not_yet_assigned(self):
        lines = [dict(line) for line in self.complete]
        lines[2] = {"id": "memory/a.md#2", "topic": "保存", "pairs": [], "outside": ["起動"]}
        write_jsonl(self.work / "judgments.jsonl", lines)
        code, out = self.run_check("judgments")
        self.assertEqual(code, 1)
        self.assertIn("memory/a.md#2", out)
        self.assertIn("起動", out)

    def test_reports_a_verdict_outside_the_two_values(self):
        lines = [dict(line) for line in self.complete]
        lines[2] = {"id": "memory/a.md#2", "topic": "保存",
                    "pairs": [{"with": "memory/a.md#1", "verdict": "different-condition", "note": "n"}], "outside": []}
        write_jsonl(self.work / "judgments.jsonl", lines)
        code, out = self.run_check("judgments")
        self.assertEqual(code, 1)
        self.assertIn("different-condition", out)


if __name__ == "__main__":
    unittest.main()
