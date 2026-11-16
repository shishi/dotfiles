#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('live', Path(__file__).with_name('output-gate-rules-live.py'))
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)


class LiveResultsTest(unittest.TestCase):
    def test_evidence_scope_good_case_rejects_a_false_failure_finding(self):
        result = subprocess.CompletedProcess([], 0, json.dumps({
            'status': 'checked', 'findings': [{'kind': 'missing_request', 'rule': '',
                'evidence': [{'id': 'read-report', 'state': 'failed'}]}]}).encode(), b'')
        with patch.object(live.subprocess, 'run', return_value=result):
            self.assertFalse(live.run(('evidence_scope', 'good', {'draft': '例'}))['ok'])

    def test_unchecked_result_is_not_a_pass(self):
        result = subprocess.CompletedProcess([], 0, json.dumps({'status': 'unchecked', 'findings': []}).encode(), b'')
        with patch.object(live.subprocess, 'run', return_value=result):
            self.assertFalse(live.run(('W1', 'good', {'draft': '例'}))['ok'])


if __name__ == '__main__':
    unittest.main()
