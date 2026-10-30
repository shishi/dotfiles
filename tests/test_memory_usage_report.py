import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

source = Path(__file__).resolve().parents[1] / "agent-shared/bin/memory-usage-report.py"
spec = importlib.util.spec_from_file_location("memory_usage_report", source)
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)


def lookup_context(candidates):
    return ("[記憶検索] 確定済み記憶の語句検索: 3件一致、本文取得0件。\n<personal-memory-index>\n# Memory Index\n"
            "</personal-memory-index>\n語句検索の候補（この hook では本文を注入しない、関連性は未判定）: "
            + ", ".join(candidates) + "\n本文の自動注入は行わない。")


class MemoryUsageReportTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.repo = root / "memory"
        (self.repo / "projects").mkdir(parents=True)
        for path, body in {"MEMORY.md": "# Memory Index\n", "CORE.md": "core\n", "a.md": "alpha\n",
                           "b.md": "bravo\n", "projects/p.md": "project\n", "rare.md": "x" * 40}.items():
            (self.repo / path).write_bytes(body.encode("utf-8"))
        for command in (["init", "-q", "-b", "main"], ["add", "-A"],
                        ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "fixture"]):
            subprocess.run(["git", "-C", str(self.repo), *command], check=True)
        self.commit = subprocess.check_output(["git", "-C", str(self.repo), "rev-parse", "main"], text=True).strip()
        self.claude = root / "claude"
        self.codex = root / "codex"
        self.claude.mkdir()
        self.codex.mkdir()

    def tearDown(self):
        self.directory.cleanup()

    def write_jsonl(self, path, records):
        path.write_text("\n".join(json.dumps(record, ensure_ascii=False) for record in records) + "\n", encoding="utf-8")

    def test_claude_prompt_retrievals_are_attributed_to_the_preceding_lookup(self):
        self.write_jsonl(self.claude / "session.jsonl", [
            {"type": "attachment", "timestamp": "2026-10-30T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md", "b.md"])]}},
            {"type": "assistant", "timestamp": "2026-10-30T00:00:01Z", "message": {"content": [
                {"type": "tool_use", "id": "t1", "name": "Bash",
                 "input": {"command": f"git -C ~/.claude/memory show {self.commit}:a.md"}},
                {"type": "tool_use", "id": "t2", "name": "Bash",
                 "input": {"command": f"git -C ~/.claude/memory show {self.commit}:missing.md"}}]}},
            {"type": "user", "timestamp": "2026-10-30T00:00:02Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "alpha"},
                {"type": "tool_result", "tool_use_id": "t2", "content": "fatal"}]}},
            {"type": "attachment", "timestamp": "2026-10-30T00:01:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["b.md"])]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [], "2026-10-01")

        self.assertEqual(report["prompts"], 2)
        self.assertEqual(report["prompts_with_retrieval"], 1)
        self.assertEqual(report["files"]["a.md"]["retrieved"], 1)
        self.assertEqual(report["files"]["a.md"]["candidate"], 1)
        self.assertEqual(report["files"]["b.md"]["candidate"], 2)
        self.assertNotIn("missing.md", report["files"])

    def test_codex_lookups_and_delivered_bodies_count_as_retrievals(self):
        self.write_jsonl(self.codex / "rollout.jsonl", [
            {"type": "response_item", "timestamp": "2026-10-30T00:00:00Z",
             "payload": {"type": "message", "role": "developer",
                         "content": [{"type": "input_text", "text": lookup_context(["a.md"])}]}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:01Z",
             "payload": {"type": "function_call", "name": "shell", "call_id": "c1",
                         "arguments": json.dumps({"command": "bash ~/.agent-shared/hooks/inject-memory.sh ~/.codex/memory lookup 'projects/p.md'"})}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:02Z",
             "payload": {"type": "function_call_output", "call_id": "c1", "output": json.dumps(
                 {"output": '<retrieved-memory path="projects/p.md">\nproject\n</retrieved-memory>',
                  "metadata": {"exit_code": 0}})}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:03Z",
             "payload": {"type": "function_call", "name": "shell", "call_id": "c2",
                         "arguments": json.dumps({"command": "bash ~/.agent-shared/hooks/inject-memory.sh ~/.codex/memory lookup sandbox"})}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:04Z",
             "payload": {"type": "function_call_output", "call_id": "c2", "output": json.dumps(
                 {"output": '<retrieved-memory path="b.md">\n全文取得\nbravo\n</retrieved-memory>',
                  "metadata": {"exit_code": 0}})}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [], [str(self.codex)], "2026-10-01")

        self.assertEqual(report["prompts"], 1)
        self.assertEqual(report["prompts_with_retrieval"], 1)
        self.assertEqual(report["files"]["projects/p.md"]["retrieved"], 1)
        self.assertEqual(report["files"]["projects/p.md"]["outside"], 1)
        self.assertEqual(report["files"]["b.md"]["retrieved"], 1)
        self.assertEqual(report["files"]["a.md"]["retrieved"], 0)

    def test_every_memory_file_is_listed_with_its_size_even_when_never_used(self):
        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [str(self.codex)], "2026-10-01")

        self.assertEqual(report["prompts"], 0)
        self.assertEqual(report["files"]["rare.md"], {"chars": 40, "retrieved": 0, "candidate": 0, "outside": 0})
        self.assertNotIn("MEMORY.md", report["files"])
        self.assertEqual(report["index_chars"], len("# Memory Index\n"))

    def test_instructions_quoting_the_marker_are_not_hook_output(self):
        self.write_jsonl(self.codex / "rollout.jsonl", [
            {"type": "response_item", "timestamp": "2026-10-30T00:00:00Z",
             "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text":
                         "# AGENTS.md instructions\n- 毎入力の `[記憶検索]` と索引を確認する。\n語句検索の候補: a.md"}]}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:01Z",
             "payload": {"type": "message", "role": "developer",
                         "content": [{"type": "input_text", "text": lookup_context(["b.md"])}]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [], [str(self.codex)], "2026-10-01")

        self.assertEqual(report["prompts"], 1)
        self.assertEqual(report["files"]["a.md"]["candidate"], 0)

    def test_only_successful_reads_of_the_memory_repository_count_as_retrievals(self):
        self.write_jsonl(self.claude / "session.jsonl", [
            {"type": "attachment", "timestamp": "2026-10-30T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md"])]}},
            {"type": "assistant", "timestamp": "2026-10-30T00:00:01Z", "message": {"content": [
                {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "git show HEAD:a.md"}},
                {"type": "tool_use", "id": "t2", "name": "Edit",
                 "input": {"file_path": "C:\\Users\\u\\.claude\\memory\\b.md", "old_string": "x", "new_string": "y"}},
                {"type": "tool_use", "id": "t3", "name": "Bash",
                 "input": {"command": f"git -C ~/.claude/memory show {self.commit}:rare.md"}},
                {"type": "tool_use", "id": "t4", "name": "Read",
                 "input": {"file_path": "C:\\Users\\u\\.claude\\memory\\projects\\p.md"}}]}},
            {"type": "user", "timestamp": "2026-10-30T00:00:02Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "alpha"},
                {"type": "tool_result", "tool_use_id": "t2", "content": "ok"},
                {"type": "tool_result", "tool_use_id": "t3", "is_error": True, "content": "fatal"},
                {"type": "tool_result", "tool_use_id": "t4", "content": "project"}]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [], "2026-10-01")

        self.assertEqual({path: row["retrieved"] for path, row in report["files"].items() if row["retrieved"]},
                         {"projects/p.md": 1})

    def test_quoted_lookup_paths_and_delivered_bodies_are_recognised(self):
        self.write_jsonl(self.claude / "session.jsonl", [
            {"type": "attachment", "timestamp": "2026-10-30T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md"])]}},
            {"type": "assistant", "timestamp": "2026-10-30T00:00:01Z", "message": {"content": [
                {"type": "tool_use", "id": "t1", "name": "Bash",
                 "input": {"command": "bash ~/.agent-shared/hooks/inject-memory.sh ~/.claude/memory lookup 'sandbox'"}}]}},
            {"type": "user", "timestamp": "2026-10-30T00:00:02Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1",
                 "content": '<retrieved-memory path="b.md">\n全文取得\nbravo\n</retrieved-memory>'}]}},
        ])
        self.write_jsonl(self.codex / "rollout.jsonl", [
            {"type": "response_item", "timestamp": "2026-10-30T00:00:00Z",
             "payload": {"type": "message", "role": "developer",
                         "content": [{"type": "input_text", "text": lookup_context(["a.md"])}]}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:01Z",
             "payload": {"type": "function_call", "name": "shell", "call_id": "c1",
                         "arguments": json.dumps({"command": 'bash ~/.agent-shared/hooks/inject-memory.sh ~/.codex/memory lookup "a.md"'})}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:02Z",
             "payload": {"type": "function_call_output", "call_id": "c1", "output": json.dumps(
                 {"output": '<retrieved-memory path="a.md">\nalpha\n</retrieved-memory>', "metadata": {"exit_code": 0}})}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [str(self.codex)], "2026-10-01")

        self.assertEqual(report["files"]["b.md"]["retrieved"], 1)
        self.assertEqual(report["files"]["a.md"]["retrieved"], 1)

    def codex_hook(self, timestamp="2026-10-30T00:00:00Z"):
        return [{"type": "event_msg", "timestamp": timestamp, "payload": {"type": "task_started"}},
                {"type": "response_item", "timestamp": timestamp,
                 "payload": {"type": "message", "role": "developer",
                             "content": [{"type": "input_text", "text": lookup_context(["a.md"])}]}}]

    def exec_call(self, call_id, command):
        return {"type": "response_item", "timestamp": "2026-10-30T00:00:01Z",
                "payload": {"type": "custom_tool_call", "name": "exec", "call_id": call_id,
                            "input": "text(await tools.exec_command({cmd:" + json.dumps(command) + "}));"}}

    def exec_output(self, call_id, exit_code, text=""):
        body = json.dumps({"chunk_id": "x", "exit_code": exit_code, "output": text})
        return {"type": "response_item", "timestamp": "2026-10-30T00:00:02Z",
                "payload": {"type": "custom_tool_call_output", "call_id": call_id,
                            "output": [{"type": "input_text", "text": "Script completed\n"},
                                       {"type": "input_text", "text": body}]}}

    def test_codex_counts_successful_reads_and_ignores_patches_and_failures(self):
        self.write_jsonl(self.codex / "rollout.jsonl", self.codex_hook() + [
            self.exec_call("c1", f'git -C ~/.codex/memory show "{self.commit}:a.md"'),
            self.exec_output("c1", 0, "alpha"),
            self.exec_call("c2", f"git -C ~/.codex/memory show {self.commit}:rare.md"),
            self.exec_output("c2", 128, "fatal"),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:03Z",
             "payload": {"type": "custom_tool_call", "name": "apply_patch", "call_id": "c3",
                         "input": "*** Begin Patch\n*** Update File: C:/Users/u/.codex/memory/b.md\n*** End Patch"}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:04Z",
             "payload": {"type": "custom_tool_call_output", "call_id": "c3", "output": "Done"}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [], [str(self.codex)], "2026-10-01")

        self.assertEqual({path: row["retrieved"] for path, row in report["files"].items() if row["retrieved"]},
                         {"a.md": 1})

    def test_codex_reads_without_a_clean_exit_status_are_not_retrievals(self):
        truncated = ("Warning: truncated output (original token count: 15447)\n\n"
                     + json.dumps({"chunk_id": "x", "exit_code": 1, "output": "alpha"}))
        self.write_jsonl(self.codex / "rollout.jsonl", self.codex_hook() + [
            self.exec_call("c1", f"git -C ~/.codex/memory show {self.commit}:a.md"),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:02Z",
             "payload": {"type": "custom_tool_call_output", "call_id": "c1",
                         "output": [{"type": "input_text", "text": truncated}]}},
            self.exec_call("c2", f"git -C ~/.codex/memory show {self.commit}:b.md"),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:03Z",
             "payload": {"type": "custom_tool_call_output", "call_id": "c2",
                         "output": [{"type": "input_text", "text": "Script running with cell ID 1"}]}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:04Z",
             "payload": {"type": "custom_tool_call", "name": "exec", "call_id": "c3",
                         "input": 'text(await tools.exec_command({cmd:"git -C ~/.codex/memory show HEAD:rare.md\\x20"}));'}},
            self.exec_output("c3", 0, "x"),
        ])

        report = usage.build_report(str(self.repo), self.commit, [], [str(self.codex)], "2026-10-01")

        self.assertEqual(report["retrieved_total"], 0)
        self.assertEqual(report["unknown_results"], 1)

    def test_only_memory_repository_commands_and_lookup_deliveries_count(self):
        self.write_jsonl(self.claude / "session.jsonl", [
            {"type": "attachment", "timestamp": "2026-10-30T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md"])]}},
            {"type": "assistant", "timestamp": "2026-10-30T00:00:01Z", "message": {"content": [
                {"type": "tool_use", "id": "t1", "name": "Bash",
                 "input": {"command": "echo agent-memory; git -C ./other show HEAD:a.md"}},
                {"type": "tool_use", "id": "t2", "name": "Bash",
                 "input": {"command": 'echo "git -C ~/.claude/memory show HEAD:b.md"'}},
                {"type": "tool_use", "id": "t3", "name": "Bash",
                 "input": {"command": "bash ~/.agent-shared/hooks/inject-memory.sh ~/.claude/memory lookup 'rare.md'"}},
                {"type": "tool_use", "id": "t4", "name": "Read", "input": {"file_path": "C:/work/fixture.txt"}}]}},
            {"type": "user", "timestamp": "2026-10-30T00:00:02Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "alpha"},
                {"type": "tool_result", "tool_use_id": "t2", "content": "git -C ~/.claude/memory show HEAD:b.md"},
                {"type": "tool_result", "tool_use_id": "t3", "content": "[記憶検索] 本文取得0件。既読の同一版: rare.md"},
                {"type": "tool_result", "tool_use_id": "t4",
                 "content": '<retrieved-memory path="projects/p.md">\nproject\n</retrieved-memory>'}]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [], "2026-10-01")

        self.assertEqual(report["retrieved_total"], 0)

    def test_quoted_hook_output_in_an_answer_is_not_a_prompt(self):
        self.write_jsonl(self.codex / "rollout.jsonl", [
            {"type": "response_item", "timestamp": "2026-10-30T00:00:00Z",
             "payload": {"type": "message", "role": "assistant",
                         "content": [{"type": "output_text", "text": "注入はこうなる:\n" + lookup_context(["a.md"])}]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [], [str(self.codex)], "2026-10-01")

        self.assertEqual(report["prompts"], 0)

    def test_reads_after_an_input_without_hook_output_are_not_credited_to_the_previous_input(self):
        self.write_jsonl(self.claude / "session.jsonl", [
            {"type": "user", "turnOrigin": "human", "timestamp": "2026-10-30T00:00:00Z", "message": {"content": "first request"}},
            {"type": "attachment", "timestamp": "2026-10-30T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md"])]}},
            {"type": "user", "turnOrigin": "human", "timestamp": "2026-10-30T00:01:00Z", "message": {"content": "second request"}},
            {"type": "assistant", "timestamp": "2026-10-30T00:01:01Z", "message": {"content": [
                {"type": "tool_use", "id": "t1", "name": "Bash",
                 "input": {"command": f"git -C ~/.claude/memory show {self.commit}:a.md"}}]}},
            {"type": "user", "timestamp": "2026-10-30T00:01:02Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "alpha"}]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [], "2026-10-01")

        self.assertEqual(report["prompts"], 1)
        self.assertEqual(report["prompts_with_retrieval"], 0)

    def test_notifications_inside_a_turn_do_not_end_the_input(self):
        self.write_jsonl(self.claude / "session.jsonl", [
            {"type": "user", "turnOrigin": "human", "timestamp": "2026-10-30T00:00:00Z", "message": {"content": "request"}},
            {"type": "attachment", "timestamp": "2026-10-30T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md"])]}},
            {"type": "user", "timestamp": "2026-10-30T00:00:01Z",
             "message": {"content": "<task-notification>agent finished</task-notification>"}},
            {"type": "assistant", "timestamp": "2026-10-30T00:00:02Z", "message": {"content": [
                {"type": "tool_use", "id": "t1", "name": "Bash",
                 "input": {"command": f"git -C ~/.claude/memory show {self.commit}:a.md"}}]}},
            {"type": "user", "timestamp": "2026-10-30T00:00:03Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "alpha"},
                {"type": "text", "text": "Tool loaded."}]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [], "2026-10-01")

        self.assertEqual(report["files"]["a.md"]["retrieved"], 1)

    def test_shell_quoting_and_tool_output_text_do_not_change_reads(self):
        stdout_mentions_failure = json.dumps({"chunk_id": "x", "exit_code": 0, "output": 'example: {"exit_code":1}'})
        self.write_jsonl(self.codex / "rollout.jsonl", self.codex_hook() + [
            self.exec_call("c1", 'echo "example; git -C ~/.codex/memory show HEAD:a.md"'),
            self.exec_output("c1", 0, "example"),
            self.exec_call("c2", f"git -C ~/.codex/memory show {self.commit}:b.md"),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:03Z",
             "payload": {"type": "custom_tool_call_output", "call_id": "c2",
                         "output": [{"type": "input_text", "text": stdout_mentions_failure}]}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:04Z",
             "payload": {"type": "custom_tool_call", "name": "exec", "call_id": "c3",
                         "input": f"text(await tools.exec_command({{cmd: 'git -C ~/.codex/memory show {self.commit}:rare.md'}}));"}},
            self.exec_output("c3", 0, "x"),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:05Z",
             "payload": {"type": "custom_tool_call", "name": "exec", "call_id": "c4",
                         "input": "text(await tools.exec_command({cmd: `git -C ~/.codex/memory show HEAD:${path}`}));"}},
            self.exec_output("c4", 0, "x"),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:06Z",
             "payload": {"type": "custom_tool_call", "name": "exec", "call_id": "c5",
                         "input": "text(await tools.exec_command({cmd: `rg ${pattern} src`}));"}},
            self.exec_output("c5", 0, "x"),
        ])

        report = usage.build_report(str(self.repo), self.commit, [], [str(self.codex)], "2026-10-01")

        self.assertEqual({path: row["retrieved"] for path, row in report["files"].items() if row["retrieved"]},
                         {"b.md": 1, "rare.md": 1})
        self.assertEqual(report["unparsed_commands"], 1)

    def test_shell_reads_count_only_when_they_run(self):
        commands = {
            "t1": 'echo ";" git -C ~/.claude/memory show HEAD:rare.md',
            "t2": "true || git -C ~/.claude/memory show HEAD:rare.md",
            "t3": f"# 記憶を読む\ngit -C ~/.claude/memory show {self.commit}:a.md",
            "t4": f"git -C ~/.claude/memory \\\n  show {self.commit}:b.md",
            "t5": "true ||\n  git -C ~/.claude/memory show HEAD:rare.md",
            "t6": f"false && git -C ~/.claude/memory show {self.commit}:rare.md; true",
            "t7": 'printf "%s\\n" example\\;git -C ~/.claude/memory show HEAD:rare.md',
            "t8": "for p in rare; do git -C ~/.claude/memory show HEAD:$p.md; done",
            "t9": f"GIT_PAGER=cat git -C ~/.claude/memory show {self.commit}:rare.md",
            "t10": f"git -c core.quotepath=off -C ~/.claude/memory show {self.commit}:projects/p.md | head -5",
            "t11": "true || # fallback\n  git -C ~/.claude/memory show HEAD:rare.md",
            "t12": "if false; then\n  git -C ~/.claude/memory show HEAD:rare.md\nfi",
        }
        self.write_jsonl(self.claude / "session.jsonl", [
            {"type": "assistant", "timestamp": "2026-10-29T23:59:59Z", "message": {"content": [
                {"type": "tool_use", "id": "t0", "name": "Bash",
                 "input": {"command": "true || git -C ~/.claude/memory show HEAD:rare.md"}}]}},
            {"type": "attachment", "timestamp": "2026-10-30T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md"])]}},
            {"type": "assistant", "timestamp": "2026-10-30T00:00:01Z", "message": {"content": [
                {"type": "tool_use", "id": call, "name": "Bash", "input": {"command": command}}
                for call, command in commands.items()]}},
            {"type": "user", "timestamp": "2026-10-30T00:00:02Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": call, "content": "ok"} for call in commands]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [], "2026-10-01")

        self.assertEqual({path: row["retrieved"] for path, row in report["files"].items() if row["retrieved"]},
                         {"a.md": 1, "b.md": 1, "projects/p.md": 1})
        # Every memory show that is not a plain git command stays visible as unparsed, even t1.
        self.assertEqual(report["unparsed_commands"], 9)

    def test_codex_reads_follow_the_literal_command_and_the_wrapper_exit_code(self):
        lookup_stdout = ("Attempting to perform the InitializeDefaultDrives operation on the 'FileSystem' provider failed.\n"
                         + json.dumps({"hookSpecificOutput": {"additionalContext":
                                                              '<retrieved-memory path="b.md">\nbravo\n</retrieved-memory>'}}))
        self.write_jsonl(self.codex / "rollout.jsonl", self.codex_hook() + [
            {"type": "response_item", "timestamp": "2026-10-30T00:00:01Z",
             "payload": {"type": "custom_tool_call", "name": "exec", "call_id": "c1",
                         "input": 'text(await tools.exec_command({cmd: "git -C ~/.codex/memory show HEAD:rare.md" + ".bak"}));'}},
            self.exec_output("c1", 0, "x"),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:02Z",
             "payload": {"type": "custom_tool_call", "name": "exec", "call_id": "c2",
                         "input": f"text(await tools.exec_command({{cmd: 'cd ~\\ngit -C ~/.codex/memory show {self.commit}:a.md'}}));"
                                  'text(await tools.exec_command({cmd: "git status" + " --short"}));'}},
            self.exec_output("c2", 0, "alpha"),
            self.exec_call("c3", "bash ~/.agent-shared/hooks/inject-memory.sh ~/.codex/memory lookup b.md"),
            self.exec_output("c3", 0, lookup_stdout),
            {"type": "response_item", "timestamp": "2026-10-30T00:00:03Z",
             "payload": {"type": "function_call", "name": "shell", "call_id": "c4",
                         "arguments": json.dumps({"command": f"git -C ~/.codex/memory show {self.commit}:projects/p.md"})}},
            {"type": "response_item", "timestamp": "2026-10-30T00:00:04Z",
             "payload": {"type": "function_call_output", "call_id": "c4",
                         "output": 'Process exited with code 0\nOutput:\n{"chunk_id":"example","exit_code":1}'}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [], [str(self.codex)], "2026-10-01")

        self.assertEqual({path: row["retrieved"] for path, row in report["files"].items() if row["retrieved"]},
                         {"a.md": 1, "b.md": 1, "projects/p.md": 1})
        self.assertEqual(report["unparsed_commands"], 1)

    def test_records_before_the_period_are_ignored(self):
        self.write_jsonl(self.claude / "old.jsonl", [
            {"type": "attachment", "timestamp": "2026-09-01T00:00:00Z",
             "attachment": {"type": "hook_additional_context", "hookEvent": "UserPromptSubmit",
                            "content": [lookup_context(["a.md"])]}},
        ])

        report = usage.build_report(str(self.repo), self.commit, [str(self.claude)], [], "2026-10-01")

        self.assertEqual(report["prompts"], 0)


if __name__ == "__main__":
    unittest.main()
