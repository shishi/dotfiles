import contextlib
import importlib.util
import io
from pathlib import Path
import unittest
import sys
import os
import tempfile
import subprocess

sys.dont_write_bytecode = True
from unittest.mock import patch


source = Path(__file__).resolve().parents[1] / "codex/skills/notion-read/notion-read.py"
spec = importlib.util.spec_from_file_location("notion_read", source)
notion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notion)


class NotionReadTest(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "fixture curl uses a POSIX executable")
    def test_cli_preserves_completion_and_references_from_the_api_response(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            curl = root / "curl"
            curl.write_text(
                "#!/usr/bin/env python3\nimport json, sys\nsys.stdin.read()\n"
                "if any('/databases/' in arg for arg in sys.argv):\n"
                " print(json.dumps({'object':'error', 'code':'object_not_found'}))\n"
                "else:\n"
                " print(json.dumps({'results':[\n"
                "  {'id':'done','type':'to_do','to_do':{'checked':True,'rich_text':[{'plain_text':'Verified'}]}},\n"
                "  {'id':'link','type':'bookmark','bookmark':{'url':'https://example.invalid/reference'}}\n"
                " ],'has_more':False}))\n"
            )
            curl.chmod(0o755)
            result = subprocess.run(
                [sys.executable, str(source), "11111111-1111-1111-1111-111111111111"],
                env={**os.environ, "NOTION_TOKEN": "fixture", "PATH": str(root) + os.pathsep + os.environ["PATH"]},
                capture_output=True, text=True, check=True,
            )
            self.assertIn("- [x] Verified", result.stdout)
            self.assertIn("https://example.invalid/reference", result.stdout)

    def test_repository_token_is_found_through_an_agent_home_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "dotfiles"
            script = repo / "codex/skills/notion-read/notion-read.py"
            script.parent.mkdir(parents=True)
            script.touch()
            (repo / ".notion_env").write_text("fixture-notion-token")
            home = root / "user"
            home.mkdir()
            (home / ".codex").symlink_to(repo / "codex", target_is_directory=True)
            virtual_script = home / ".codex/skills/notion-read/notion-read.py"
            with patch.object(notion, "__file__", str(virtual_script)):
                with patch.object(notion.os.path, "expanduser", return_value=str(home / ".notion_env")):
                    with patch.dict(os.environ, {"NOTION_TOKEN": ""}):
                        self.assertEqual(notion.token(), "fixture-notion-token")

    def test_search_returns_results_after_the_first_page(self):
        pages = [
            {"results": [{"id": "first", "object": "page", "properties": {}}],
             "has_more": True, "next_cursor": "next-page"},
            {"results": [{"id": "last", "object": "page", "properties": {}}],
             "has_more": False},
        ]
        output = io.StringIO()
        with patch.object(notion, "request", side_effect=pages) as request:
            with contextlib.redirect_stdout(output):
                notion.search("architecture")
        self.assertIn("first\t[page]", output.getvalue())
        self.assertIn("last\t[page]", output.getvalue())
        self.assertEqual(request.call_args_list[1].args[1]["start_cursor"], "next-page")

    def test_depth_limit_reports_unread_children(self):
        page = {"results": [{"id": "parent", "type": "toggle", "has_children": True,
                             "toggle": {"rich_text": [{"plain_text": "Details"}]}}],
                "has_more": False}
        output = io.StringIO()
        errors = io.StringIO()
        with patch.object(notion, "request", return_value=page):
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                notion.walk("root", 0, {"n": 0, "max_depth": 0, "max_blocks": 10})
        self.assertIn("parent", errors.getvalue())
        self.assertIn("--max-depth", errors.getvalue())
        self.assertIn("未取得", errors.getvalue())

    def test_table_cell_text_is_retained(self):
        page = {"results": [{"id": "row", "type": "table_row", "has_children": False,
                             "table_row": {"cells": [[{"plain_text": "name"}],
                                                     [{"plain_text": "value"}]]}}],
                "has_more": False}
        output = io.StringIO()
        with patch.object(notion, "request", return_value=page):
            with contextlib.redirect_stdout(output):
                notion.walk("table", 0, {"n": 0, "max_depth": 3, "max_blocks": 10})
        self.assertIn("name", output.getvalue())
        self.assertIn("value", output.getvalue())

    def test_to_do_completion_state_is_retained(self):
        page = {"results": [
            {"id": "done", "type": "to_do", "has_children": False,
             "to_do": {"checked": True, "rich_text": [{"plain_text": "Verified"}]}},
            {"id": "pending", "type": "to_do", "has_children": False,
             "to_do": {"checked": False, "rich_text": [{"plain_text": "Deploy"}]}},
        ], "has_more": False}
        output = io.StringIO()
        with patch.object(notion, "request", return_value=page):
            with contextlib.redirect_stdout(output):
                notion.walk("root", 0, {"n": 0, "max_depth": 3, "max_blocks": 10})
        self.assertEqual(output.getvalue(), "- [x] Verified\n- [ ] Deploy\n")

    def test_page_reference_and_rich_text_link_destinations_are_retained(self):
        target = "11111111-1111-1111-1111-111111111111"
        page = {"results": [
            {"id": "reference", "type": "link_to_page", "has_children": False,
             "link_to_page": {"type": "page_id", "page_id": target}},
            {"id": "paragraph", "type": "paragraph", "has_children": False,
             "paragraph": {"rich_text": [{"plain_text": "Details",
                                            "href": "https://example.invalid/details"}]}},
        ], "has_more": False}
        output = io.StringIO()
        with patch.object(notion, "request", return_value=page):
            with contextlib.redirect_stdout(output):
                notion.walk("root", 0, {"n": 0, "max_depth": 3, "max_blocks": 10})
        self.assertIn(target, output.getvalue())
        self.assertIn("https://example.invalid/details", output.getvalue())

    def test_nontext_block_is_visible_without_claiming_its_content_was_read(self):
        page = {"results": [{"id": "attachment", "type": "pdf", "has_children": False,
                             "pdf": {"type": "external", "external": {
                                 "url": "https://example.invalid/file.pdf"}}}],
                "has_more": False}
        output = io.StringIO()
        with patch.object(notion, "request", return_value=page):
            with contextlib.redirect_stdout(output):
                notion.walk("root", 0, {"n": 0, "max_depth": 3, "max_blocks": 10})
        self.assertIn("pdf", output.getvalue())
        self.assertIn("attachment", output.getvalue())
        self.assertIn("対象外", output.getvalue())

    def test_bookmark_and_table_cell_link_destinations_are_retained(self):
        page = {"results": [
            {"id": "bookmark", "type": "bookmark", "has_children": False,
             "bookmark": {"url": "https://example.invalid/bookmark",
                          "caption": [{"plain_text": "Reference"}]}},
            {"id": "row", "type": "table_row", "has_children": False,
             "table_row": {"cells": [[{"plain_text": "Details",
                                        "href": "https://example.invalid/cell"}]]}},
        ], "has_more": False}
        output = io.StringIO()
        with patch.object(notion, "request", return_value=page):
            with contextlib.redirect_stdout(output):
                notion.walk("root", 0, {"n": 0, "max_depth": 3, "max_blocks": 10})
        self.assertIn("Reference", output.getvalue())
        self.assertIn("https://example.invalid/bookmark", output.getvalue())
        self.assertIn("https://example.invalid/cell", output.getvalue())


if __name__ == "__main__":
    unittest.main()
