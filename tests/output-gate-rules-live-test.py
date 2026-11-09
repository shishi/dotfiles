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
    def test_unchecked_result_is_not_a_pass(self):
        result = subprocess.CompletedProcess([], 0, json.dumps({'status': 'unchecked', 'findings': []}).encode(), b'')
        with patch.object(live.subprocess, 'run', return_value=result):
            self.assertFalse(live.run(('W1', 'good', {'draft': '例'}))['ok'])


if __name__ == '__main__':
    unittest.main()
