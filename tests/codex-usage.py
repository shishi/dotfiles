#!/usr/bin/env python3
"""Quota RPC の双方向プロトコルと終了回収を、認証不要のstubで確認する。"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / 'agent-shared/bin/codex-usage.py'


class QuotaTests(unittest.TestCase):
    def test_early_exit_returns_unknown_and_closes_streams(self):
        spec = importlib.util.spec_from_file_location('quota', HELPER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        server = subprocess.Popen([sys.executable, '-c', 'pass'], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        server.wait(timeout=3)
        try:
            server.stdin.write(b'unflushed')
            with patch.object(module.subprocess, 'Popen', return_value=server):
                value, code = module.read_rate_limits(timeout=0.4)
            self.assertEqual(code, 1)
            self.assertEqual(value['status'], 'unknown')
            self.assertIsNone(value['rate_limits'])
            self.assertIsInstance(json.loads(json.dumps(value)), dict)
            self.assertTrue(server.stdin.closed)
            self.assertTrue(server.stdout.closed)
        finally:
            for stream in (server.stdin, server.stdout):
                try:
                    stream.close()
                except BrokenPipeError:
                    pass

    def test_protocol_errors_timeout_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stub = root / 'codex'
            stub.write_text('#!' + sys.executable + '\n' + textwrap.dedent('''\
                import json, os, sys, time
                from pathlib import Path
                Path(os.environ['STUB_PID']).write_text(str(os.getpid()))
                assert sys.argv[1:] == ['app-server']
                def read():
                    value = json.loads(sys.stdin.readline())
                    with open(os.environ['STUB_LOG'], 'a') as log:
                        log.write(json.dumps(value) + '\\n')
                    return value
                def send(value):
                    print(json.dumps(value), flush=True)
                init = read()
                assert init['method'] == 'initialize'
                send({'id': init['id'], 'result': {'userAgent': 'stub'}})
                assert read()['method'] == 'initialized'
                quota = read()
                assert quota['method'] == 'account/rateLimits/read'
                mode = os.environ['STUB_MODE']
                if mode == 'timeout':
                    time.sleep(60)
                elif mode == 'error':
                    send({'id': quota['id'], 'error': {'code': -32000, 'message': 'PRIVATE_ERROR'}})
                else:
                    send({'id': 90, 'method': 'server/request', 'params': {}})
                    reply = read()
                    assert reply['id'] == 90 and 'error' in reply
                    send({'method': 'account/updated', 'params': {'secret': 'PRIVATE_NOTIFICATION'}})
                    send({'id': quota['id'], 'result': {'rateLimits': {
                        'primary': {'usedPercent': 14, 'windowDurationMins': 300, 'resetsAt': 1800000000},
                        'secondary': None, 'credits': {'hasCredits': False, 'unlimited': False, 'balance': None}},
                        'rateLimitsByLimitId': {
                            'codex': {'limitId': 'codex', 'primary': {'usedPercent': 14}},
                            'codex_other': {'limitId': 'codex_other', 'primary': {'usedPercent': 42},
                                            'accountId': 'PRIVATE_ACCOUNT'},
                            'org-PRIVATE_ACCOUNT': {'limitId': 'org-PRIVATE_ACCOUNT',
                                                    'primary': {'usedPercent': 1}},
                            'RateLimitResetCredit_PRIVATE': {'primary': {'usedPercent': 1}},
                            'a6d4b651-f338-426f-a381-e9915730fb42': {'primary': {'usedPercent': 1}}},
                        'privateExtra': 'PRIVATE_RESPONSE'}})
                sys.stdin.read()
            '''))
            stub.chmod(0o755)
            for mode in ['normal', 'error', 'timeout']:
                with self.subTest(mode=mode):
                    pid_file, log_file = root / (mode + '.pid'), root / (mode + '.log')
                    env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                               STUB_MODE=mode, STUB_PID=str(pid_file), STUB_LOG=str(log_file))
                    # Import for a shorter deadline; the production CLI retains its 30s default.
                    runner = '''import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('quota', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value, code = module.read_rate_limits(timeout=0.4)
print(json.dumps(value))
sys.exit(code)
'''
                    started = time.monotonic()
                    result = subprocess.run([sys.executable, '-c', runner, str(HELPER)], env=env,
                                            capture_output=True, text=True, timeout=4)
                    elapsed = time.monotonic() - started
                    self.assertTrue(result.stdout, result.stderr)
                    value = json.loads(result.stdout)
                    self.assertIsInstance(value['observed_at'], str)
                    self.assertEqual(value['status'], 'ok' if mode == 'normal' else 'unknown')
                    self.assertEqual(result.returncode == 0, mode == 'normal')
                    if mode == 'normal':
                        self.assertEqual(value['rate_limits']['primary']['usedPercent'], 14)
                        self.assertEqual(value['rate_limits_by_id'], {
                            'codex': {'primary': {'usedPercent': 14}},
                            'codex_other': {'primary': {'usedPercent': 42}}})
                    else:
                        self.assertIsNone(value['rate_limits'])
                    self.assertNotIn('PRIVATE_', result.stdout + result.stderr)
                    self.assertLess(elapsed, 3)
                    pid = int(pid_file.read_text())
                    with self.assertRaises(ProcessLookupError):
                        os.kill(pid, 0)
                    methods = [json.loads(line).get('method') for line in log_file.read_text().splitlines()]
                    self.assertEqual(methods[:3], ['initialize', 'initialized', 'account/rateLimits/read'])


if __name__ == '__main__':
    unittest.main()
