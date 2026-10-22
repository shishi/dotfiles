import contextlib
import importlib.util
import io
from pathlib import Path
import unittest
import sys
import os
import tempfile

sys.dont_write_bytecode = True
from unittest.mock import patch


source = Path(__file__).resolve().parents[1] / "codex/skills/notion-read/notion-read.py"
spec = importlib.util.spec_from_file_location("notion_read", source)
notion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notion)


class NotionReadTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
