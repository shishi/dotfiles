#!/usr/bin/env python3
"""出力ゲートの検査処理を、偽の検査役と偽の gitleaks で確かめる。検査役の判定の質は扱わない。"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

REPO = Path(__file__).resolve().parents[1]
CHECK = REPO / 'agent-shared/bin/output-gate-check.py'

RULES = textwrap.dedent('''\
    # 共通指示

    ## 応答

    - 説明で「効く」を使わない。

    ## 作業環境

    - 無関係な節。
    ''')


class CheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.rules = self.tmp / 'AGENTS.md'
        self.rules.write_text(RULES, encoding='utf-8')
        self.prompt_log = self.tmp / 'prompt.txt'
        self.instructions_log = self.tmp / 'instructions.txt'
        self.gitleaks = self.fake_gitleaks([])

    def fake_checker(self, reply, sleep=0, exit_code=0):
        """偽の検査役。標準入力と、作業ディレクトリに置かれた検査役への指示を記録する。"""
        script = self.tmp / 'checker.py'
        script.write_text(textwrap.dedent(f'''\
            import os, shutil, sys, time
            prompt = sys.stdin.read()
            open({str(self.prompt_log)!r}, 'w', encoding='utf-8').write(prompt)
            if os.path.exists('checker-instructions.md'):
                shutil.copyfile('checker-instructions.md', {str(self.instructions_log)!r})
            time.sleep({sleep})
            sys.stdout.write({reply!r})
            sys.exit({exit_code})
            '''), encoding='utf-8')
        return json.dumps([sys.executable, '-I', str(script)])

    def fake_gitleaks_from_file(self, start, end):
        """入力ファイルを読み、start から end までをファイル上のバイト列のまま秘密情報として報告する。"""
        script = self.tmp / 'gitleaks-file.py'
        script.write_text(textwrap.dedent(f'''\
            import json, sys
            args = sys.argv[1:]
            source = open(args[args.index('--source') + 1], 'rb').read().decode('utf-8')
            begin = source.index({start!r})
            finish = source.index({end!r}, begin) + len({end!r})
            path = args[args.index('--report-path') + 1]
            open(path, 'w', encoding='utf-8').write(json.dumps([{{'Secret': source[begin:finish], 'RuleID': 'pk'}}]))
            '''), encoding='utf-8')
        return json.dumps([sys.executable, '-I', str(script)])

    def fake_gitleaks(self, secrets):
        script = self.tmp / 'gitleaks.py'
        findings = [{'Secret': s, 'RuleID': 'test'} for s in secrets]
        script.write_text(textwrap.dedent(f'''\
            import json, sys
            args = sys.argv[1:]
            path = args[args.index('--report-path') + 1]
            open(path, 'w', encoding='utf-8').write(json.dumps({findings!r}))
            '''), encoding='utf-8')
        return json.dumps([sys.executable, '-I', str(script)])

    def run_check(self, draft, reply, sleep=0, timeout=10, gitleaks=None, extra=None, exit_code=0):
        env = dict(os.environ)
        env.update({
            'OUTPUT_GATE_CHECKER_CMD': self.fake_checker(reply, sleep, exit_code),
            'OUTPUT_GATE_TIMEOUT': str(timeout),
            'OUTPUT_GATE_RULES': str(self.rules),
            'OUTPUT_GATE_GITLEAKS': self.gitleaks if gitleaks is None else gitleaks,
        })
        payload = {'cli': 'codex', 'latest_user': '説明して', 'conversation': [],
                   'draft': draft, 'cyber_program': None, 'compacted_note': False}
        payload.update(extra or {})
        result = subprocess.run([sys.executable, '-I', str(CHECK)], input=json.dumps(payload),
                                capture_output=True, text=True, encoding='utf-8', env=env, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    @staticmethod
    def pairs(*items):
        return json.dumps({'pairs': [dict(zip(('find', 'replace', 'rule', 'meaning_changed'), i))
                                     for i in items]})

    def assert_unchecked(self, out, draft):
        self.assertEqual(out['status'], 'unchecked')
        self.assertTrue(out['reason'])
        self.assertTrue(out['text'].endswith(draft))
        self.assertIn(out['reason'], out['text'])

    def test_applies_valid_pairs(self):
        out = self.run_check('この設定は効く。', self.pairs(('効く', '速くなる', '「効く」を使わない', False)))
        self.assertEqual(out, {'status': 'checked', 'text': 'この設定は速くなる。', 'reason': None, 'applied': 1})

    def test_no_change_returns_checked_original(self):
        out = self.run_check('問題ありません。', json.dumps({'pairs': []}))
        self.assertEqual(out['status'], 'checked')
        self.assertEqual(out['text'], '問題ありません。')
        self.assertEqual(out['applied'], 0)

    def test_rejects_pair_inside_fenced_code_block(self):
        draft = '例:\n```\nx = 効く\n```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_rejects_pair_inside_inline_code(self):
        draft = '名前は `効く` です。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_rejects_pair_inside_quote(self):
        draft = '> 元の文: 効く\n\n説明です。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_rejects_pair_without_rule(self):
        draft = 'この設定は効く。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', '', False))), draft)

    def test_rejects_meaning_changed(self):
        draft = 'テストは失敗した。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('失敗した', '成功した', 'r', True))), draft)

    def test_find_not_found_is_unchecked(self):
        draft = 'この設定は速い。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_checker_timeout_is_unchecked(self):
        draft = 'この設定は効く。'
        self.assert_unchecked(self.run_check(draft, json.dumps({'pairs': []}), sleep=5, timeout=1), draft)

    def test_checker_bad_json_is_unchecked(self):
        draft = 'この設定は効く。'
        self.assert_unchecked(self.run_check(draft, 'not json'), draft)

    def test_secret_is_masked_before_send(self):
        self.gitleaks = self.fake_gitleaks(['sk-test-SECRETVALUE'])
        self.run_check('鍵は sk-test-SECRETVALUE です。', json.dumps({'pairs': []}))
        prompt = self.prompt_log.read_text(encoding='utf-8')
        self.assertNotIn('sk-test-SECRETVALUE', prompt)
        self.assertIn('鍵は', prompt)

    def test_no_gitleaks_is_unchecked(self):
        draft = 'この設定は効く。'
        out = self.run_check(draft, json.dumps({'pairs': []}),
                             gitleaks=json.dumps([str(self.tmp / 'missing-gitleaks')]))
        self.assert_unchecked(out, draft)
        self.assertFalse(self.prompt_log.exists())

    def test_rules_section_extracted(self):
        self.run_check('問題ありません。', json.dumps({'pairs': []}))
        prompt = self.prompt_log.read_text(encoding='utf-8')
        self.assertIn('「効く」を使わない', prompt)
        self.assertNotIn('無関係な節', prompt)

    def test_conversation_and_latest_user_in_prompt(self):
        self.run_check('問題ありません。', json.dumps({'pairs': []}), extra={
            'latest_user': '最新の依頼', 'conversation': [{'role': 'assistant', 'text': '前の回答'}]})
        prompt = self.prompt_log.read_text(encoding='utf-8')
        self.assertIn('最新の依頼', prompt)
        self.assertIn('前の回答', prompt)

    def test_checker_instructions_are_a_file_in_the_workdir(self):
        self.run_check('問題ありません。', json.dumps({'pairs': []}))
        instructions = self.instructions_log.read_text(encoding='utf-8')
        prompt = self.prompt_log.read_text(encoding='utf-8')
        self.assertIn('{"pairs": []}', instructions)
        self.assertNotIn('{"pairs": []}', prompt)
        self.assertIn('問題ありません。', prompt)

    def test_protected_parts_of_the_draft_are_listed_for_the_checker(self):
        self.run_check('> 引用の効く\n\n本文は効く。`code` も。', json.dumps({'pairs': []}))
        prompt = self.prompt_log.read_text(encoding='utf-8')
        protected = prompt.split('## Protected parts of the draft', 1)[1].split('## Draft answer', 1)[0]
        self.assertIn('> 引用の効く', protected)
        self.assertIn('`code`', protected)
        self.assertNotIn('本文は効く', protected)

    def test_draft_without_code_or_quotes_lists_no_protected_parts(self):
        self.run_check('本文は効く。', json.dumps({'pairs': []}))
        prompt = self.prompt_log.read_text(encoding='utf-8')
        protected = prompt.split('## Protected parts of the draft', 1)[1].split('## Draft answer', 1)[0]
        self.assertEqual(protected.strip(), '(none)')

    def test_occurrence_inside_a_quote_is_kept_and_the_one_outside_is_replaced(self):
        out = self.run_check('> 引用の効く\n\n本文は効く。', self.pairs(('効く', '速い', 'r', False)))
        self.assertEqual(out['status'], 'checked')
        self.assertEqual(out['text'], '> 引用の効く\n\n本文は速い。')

    def test_occurrence_inside_code_is_kept_and_the_one_outside_is_replaced(self):
        out = self.run_check('`効く` は効く。', self.pairs(('効く', '速い', 'r', False)))
        self.assertEqual(out['status'], 'checked')
        self.assertEqual(out['text'], '`効く` は速い。')

    def test_checker_login_failure_names_the_fix(self):
        draft = 'この設定は効く。'
        out = self.run_check(draft, '', exit_code=77)
        self.assert_unchecked(out, draft)
        self.assertIn('codex login', out['reason'])

    def test_multiline_secret_is_masked(self):
        self.gitleaks = self.fake_gitleaks_from_file('-----BEGIN KEY-----', '-----END KEY-----')
        draft = '鍵:\n-----BEGIN KEY-----\nAAAASECRETBODY\n-----END KEY-----\n以上。'
        self.run_check(draft, json.dumps({'pairs': []}))
        prompt = self.prompt_log.read_text(encoding='utf-8')
        self.assertNotIn('AAAASECRETBODY', prompt)

    def test_replacements_apply_only_to_original_text(self):
        draft = '良い設定は効く。'
        out = self.run_check(draft, self.pairs(('効く', '良く効く', 'r', False), ('良', '悪', 'r', False)))
        self.assertEqual(out['status'], 'checked')
        self.assertEqual(out['text'], '悪い設定は良く効く。')

    def test_overlapping_pairs_are_unchecked(self):
        draft = 'この設定は効く。'
        out = self.run_check(draft, self.pairs(('設定は効く', 'x', 'r', False), ('効く', 'y', 'r', False)))
        self.assert_unchecked(out, draft)

    def test_invalid_payload_types_exit_2(self):
        env = dict(os.environ, OUTPUT_GATE_CHECKER_CMD=self.fake_checker('{"pairs": []}'),
                   OUTPUT_GATE_RULES=str(self.rules), OUTPUT_GATE_GITLEAKS=self.gitleaks)
        payload = {'draft': 'x', 'conversation': ['not a dict']}
        result = subprocess.run([sys.executable, '-I', str(CHECK)], input=json.dumps(payload),
                                capture_output=True, text=True, encoding='utf-8', env=env, timeout=60)
        self.assertEqual(result.returncode, 2)

    def test_rejects_pair_inside_four_backtick_fence(self):
        draft = '````\n```\nx = 効く\n````\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_unmatched_backtick_does_not_hide_later_inline_code(self):
        draft = 'バッククォート (` ) で囲む。\n\n```\nx\n```\n\nNG 語は `効く` です。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_backtick_inside_tilde_fence_does_not_hide_later_inline_code(self):
        draft = '~~~\n`example\n~~~\n`foo`'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_rejects_pair_inside_indented_code_block(self):
        draft = '説明:\n\n    x = 効く\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_rejects_pair_inside_quote_continuation_line(self):
        draft = '> 引用の始まり\n続きは効く\n\n本文です。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_indented_list_continuation_is_not_code(self):
        out = self.run_check('- 項目\n\n    続きは効く。', self.pairs(('効く', '速い', 'r', False)))
        self.assertEqual(out['text'], '- 項目\n\n    続きは速い。')

    def test_rejects_pair_inside_indented_code_in_a_list(self):
        draft = '- item\n\n      foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_rejects_pair_inside_fence_opened_on_a_list_marker(self):
        draft = '- ```\n  foo\n  ```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_rejects_pair_inside_deeply_indented_fence_with_blank_line(self):
        draft = '1. 手順\n   - サブ\n     ```bash\n     echo 効く\n\n     more\n     ```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)

    def test_deeply_indented_fence_line_does_not_close_the_fence(self):
        draft = '```\n    ```\nfoo\n```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_closing_fence_is_measured_from_the_container(self):
        draft = '   ```\n    ```\nfoo\n   ```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_fence_opened_on_a_nested_list_marker_closes_at_the_item_content(self):
        out = self.run_check('- a\n  - ```\n    code\n    ```\nfoo\n', self.pairs(('foo', 'bar', 'r', False)))
        self.assertEqual(out['text'], '- a\n  - ```\n    code\n    ```\nbar\n')

    def test_shallower_fence_line_keeps_the_list_fence_protected(self):
        draft = '1. 手順:\n   ```sh\n   echo x\n```\nfoo の説明\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_shallower_fence_line_opens_a_new_fence(self):
        # 入れ物より浅い囲みの行はリスト項目を終わらせ、新しい囲みを開く (CommonMark)。
        draft = '1. step\n   ```sh\n   echo\n```\ncode\n    ```\nfoo\n```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_shallower_line_in_nested_list_fence_protects_the_rest(self):
        draft = '- a\n  - b\n    ```\n    x\n  ```\n  y\n```\nz\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('z', 'w', 'r', False))), draft)

    def test_shallower_fence_line_in_nested_list_fence_protects_the_rest(self):
        draft = '1. outer\n   1. inner\n      ```sh\n      echo\n   ```\n```\nfoo\n```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_shallower_text_line_in_list_fence_protects_the_rest(self):
        draft = '1. 設定:\n   ```yaml\nkey: value\n   ```\n2. 次に foo を見る\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_fence_after_a_sub_item_belongs_to_the_parent_item(self):
        draft = '1. 設定\n   - 対象: app\n   ```yaml\nkey: value\n   ```\n2. 次に foo を見る\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_fence_after_a_list_ends_the_list(self):
        draft = '- a\n\n```\ncode\n```\ntext\n\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_indented_fence_line_is_code_not_a_fence(self):
        draft = '例:\n\n    ```\n    x\n    ```\n\n本文\n\n```\nfoo\n```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_indented_code_may_follow_a_closed_fence(self):
        draft = '- a\n  1. b\n    ```\n    x\n    ```\n      foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_heading_ends_the_list(self):
        draft = '- a\n# title\n\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_thematic_break_ends_the_list(self):
        draft = '- a\n***\n\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_quote_after_a_list_marker_is_protected(self):
        draft = '- > 引用の foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_wide_space_after_a_list_marker_starts_indented_code(self):
        draft = '1.     foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_ordered_marker_other_than_one_does_not_interrupt_a_paragraph(self):
        draft = '手順\n2. a\n\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_line_shallower_than_the_fence_characters_protects_the_rest(self):
        draft = '- - a\n    ```\n    x\n  foo\n    ```\n    bar\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('bar', 'baz', 'r', False))), draft)

    def test_list_marker_after_a_quote_starts_a_list_that_is_checked(self):
        # > の無い行では引用が続かないため、記号は段落への割り込みではなく新しいリストになる (CommonMark)。
        out = self.run_check('> quote\n2. foo\n', self.pairs(('foo', 'bar', 'r', False)))
        self.assertEqual(out['text'], '> quote\n2. bar\n')

    def test_fence_on_a_list_marker_after_a_quote_is_protected(self):
        draft = '> 注意\n2. ```bash\n   make\n   ```\n\n   続けて実行:\n\n   ```\n   foo\n   ```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_paragraph_with_backticks_and_a_link_is_protected(self):
        draft = '[docs](https://example.test/`) と `foo`\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_angle_bracket_inside_inline_code_does_not_protect_the_paragraph(self):
        out = self.run_check('`Array<String>` を返します。\n', self.pairs(('返します', '返すよ', 'r', False)))
        self.assertEqual(out['text'], '`Array<String>` を返すよ。\n')

    def test_table_cells_pair_backticks_separately(self):
        draft = '| 記号 | 意味 |\n|---|---|\n| ` | 区切り |\n| `foo` | 実行 |\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_html_block_runs_to_a_blank_line(self):
        draft = '<!-- note -->\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_backtick_in_a_reference_label_protects_the_paragraph(self):
        draft = '[a`]: /url\n`foo`\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_inline_tag_does_not_interrupt_a_paragraph(self):
        draft = '`foo\n<span>\n`\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_html_comment_runs_past_a_blank_line(self):
        draft = '<!--\n\nnote\n-->\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_code_with_a_pipe_after_a_table_like_line_is_protected(self):
        draft = '| A | B |\n|---|\n`foo|bar`\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'baz', 'r', False))), draft)

    def test_table_inside_a_list_item_pairs_backticks_per_cell(self):
        draft = '1.  | Sign | Meaning |\n    |---|---|\n    | ` | delimiter |\n    | `foo` | run |\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_one_column_table_pairs_backticks_per_cell(self):
        draft = '| H |\n:---\n| ` |\n| `foo` |\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_empty_header_cell_counts_as_a_column(self):
        draft = '| a || b |\n|---|---|---|\n| ` | x | y |\n| `foo` | run | x |\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_line_without_cells_ends_a_table(self):
        draft = '| ` |\n|---|\n|\n`foo\nbar`\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'baz', 'r', False))), draft)

    def test_delimiter_row_may_contain_vertical_tab(self):
        draft = '| H |\n|---\v|\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_leading_vertical_tab_is_a_table_cell(self):
        draft = '\v| H |\n|---|---|\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_lazy_header_may_count_its_leading_space_as_a_cell(self):
        draft = '- x\n | a |\n  |---|---|\n      foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_lazy_header_reading_is_consistent_across_the_answer(self):
        for delimiter in ('   |---|', '   |---|---|'):
            draft = '| ` |\n|---|\n2. y\n | a |\n' + delimiter + '\n   | ` foo |\n   | ` |\n'
            self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_paragraph_that_failed_to_become_a_table_stays_a_paragraph(self):
        draft = '| ` |\n|---|\n|\n|---|---|\n| a | b |\n|---|---|\n| ` foo |\n| ` |\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_indented_code_may_follow_a_table(self):
        draft = '| a | b |\n|---|---|\n| 1 | 2 |\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_html_tag_names_match_ascii_letters_only(self):
        draft = '`foo\n<ſcript>\n`\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_colon_after_a_bracket_in_code_is_not_a_reference_definition(self):
        out = self.run_check('`def load(self) -> dict[str, Any]:` を追加して確認しておいて\n',
                             self.pairs(('確認しておいて', '見ておいて', 'r', False)))
        self.assertEqual(out['text'], '`def load(self) -> dict[str, Any]:` を追加して見ておいて\n')

    def test_backtick_in_one_item_does_not_pair_with_the_next_item(self):
        draft = '- 区切りはバッククォート (`) です\n- `foo` を実行\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_setext_heading_ends_the_paragraph(self):
        draft = 'Title\n===\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_thematic_break_after_a_list_marker_ends_the_paragraph(self):
        draft = '- ***\n      foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_every_list_marker_on_a_line_opens_an_item(self):
        draft = '- - > foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_empty_item_content_starts_one_column_after_the_marker(self):
        draft = '-   \n      foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_full_width_space_does_not_close_a_fence(self):
        draft = '```\nx\n```　\nfoo\n```\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_dash_setext_underline_ends_the_paragraph(self):
        draft = 'Title\n--\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_zero_padded_one_starts_a_list_inside_a_paragraph(self):
        draft = 'text\n01. > quote\nfoo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_line_after_a_quote_in_a_list_item_leaves_the_item(self):
        draft = '- 設定例:\n  > ```\n  > x = 1\n  > ```\n補足\n\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_empty_item_ends_at_a_blank_line(self):
        draft = '- -\n\n      foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_crlf_blank_line_ends_a_paragraph_for_inline_code(self):
        draft = 'a ` b\r\n\r\n`foo` c'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_single_crlf_does_not_split_inline_code(self):
        draft = '名前は `foo\r\nbar` です。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'FOO', 'r', False))), draft)

    def test_full_width_digit_is_not_a_list_marker(self):
        draft = '手順\n１. a\n\n    foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_marker_outside_the_paragraph_item_starts_a_new_list(self):
        # 段落を含む項目がこの行で続かないとき、記号は段落への割り込みではなく新しいリストになる (CommonMark)。
        draft = '- 準備\n  - 詳細\n2. 実行\n\n       foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_sibling_items_and_lazy_lines_are_still_checked(self):
        out = self.run_check('1. a\n2. b の foo\n- c\n続きの foo\n', self.pairs(('foo', 'bar', 'r', False)))
        self.assertEqual(out['text'], '1. a\n2. b の bar\n- c\n続きの bar\n')

    def test_deep_lazy_line_stays_in_the_quote(self):
        draft = '> 引用\n      foo\n'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_escaped_backtick_does_not_hide_inline_code(self):
        draft = '\\`ignored `foo`'
        self.assert_unchecked(self.run_check(draft, self.pairs(('foo', 'bar', 'r', False))), draft)

    def test_text_beside_inline_code_is_replaced(self):
        out = self.run_check('`code` は効く。', self.pairs(('効く', '速い', 'r', False)))
        self.assertEqual(out['text'], '`code` は速い。')

    def load_check_module(self, codex_home):
        import importlib.util
        os.environ['CODEX_HOME'] = str(codex_home)
        self.addCleanup(os.environ.pop, 'CODEX_HOME', None)
        spec = importlib.util.spec_from_file_location('output_gate_check', CHECK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_default_command_reads_the_instructions_file(self):
        check = self.load_check_module(self.tmp / 'codex')
        path = self.tmp / 'work' / 'checker-instructions.md'
        command = check.checker_command(None, path)
        self.assertIn(f'model_instructions_file={json.dumps(str(path))}', command)
        self.assertIn('skills.include_instructions=false', command)

    def test_checker_model_follows_cyber_program(self):
        home = self.tmp / 'codex'
        home.mkdir()
        models = [{'slug': 'gpt-6-luna', 'available_access_programs': {'cyber': ['standard']}},
                  {'slug': 'gpt-6.1-sol', 'available_access_programs': {'cyber': ['standard', 'daybreak_blue']}}]
        (home / 'models_cache.json').write_text(json.dumps({'models': models}), encoding='utf-8')
        check = self.load_check_module(home)
        self.assertEqual(check.checker_model(None), 'gpt-6-luna')
        self.assertEqual(check.checker_model('standard'), 'gpt-6-luna')
        self.assertEqual(check.checker_model('daybreak_blue'), 'gpt-6.1-sol')
        with self.assertRaises(RuntimeError):
            check.checker_model('daybreak_red')

    def test_rejects_pair_inside_multiline_inline_code(self):
        draft = '名前は `foo\n効く` です。'
        self.assert_unchecked(self.run_check(draft, self.pairs(('効く', '速い', 'r', False))), draft)


if __name__ == '__main__':
    unittest.main()
