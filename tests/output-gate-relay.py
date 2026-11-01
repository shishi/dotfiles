#!/usr/bin/env python3
"""出力ゲートの中継を、偽の上流と偽の検査処理で確かめる。"""
import http.client
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
RELAY = REPO / 'agent-shared/bin/output-gate-relay.py'
PREFIX = '/backend-api/codex'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def sse(event):
    return f"event: {event['type']}\ndata: {json.dumps(event, ensure_ascii=False)}\n\n".encode('utf-8')



def pid_alive(pid):
    if os.name == 'nt':
        out = subprocess.run(['tasklist', '/FI', f'PID eq {pid}', '/NH'], capture_output=True, text=True).stdout
        return str(pid) in out
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def message_events(item_id, text, encrypted=None):
    item = {'id': item_id, 'type': 'message', 'role': 'assistant', 'status': 'completed',
            'content': [{'type': 'output_text', 'text': text, 'annotations': []}]}
    if encrypted:
        item['encrypted_content'] = encrypted
    added = dict(item, status='in_progress', content=[])
    half = len(text) // 2
    return [
        {'type': 'response.output_item.added', 'output_index': 0, 'item': added},
        {'type': 'response.content_part.added', 'item_id': item_id, 'output_index': 0, 'content_index': 0,
         'part': {'type': 'output_text', 'text': '', 'annotations': []}},
        {'type': 'response.output_text.delta', 'item_id': item_id, 'output_index': 0, 'content_index': 0, 'delta': text[:half]},
        {'type': 'response.output_text.delta', 'item_id': item_id, 'output_index': 0, 'content_index': 0, 'delta': text[half:]},
        {'type': 'response.output_text.done', 'item_id': item_id, 'output_index': 0, 'content_index': 0, 'text': text},
        {'type': 'response.content_part.done', 'item_id': item_id, 'output_index': 0, 'content_index': 0,
         'part': {'type': 'output_text', 'text': text, 'annotations': []}},
        {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
    ], item


def completed(items):
    return {'type': 'response.completed', 'response': {'id': 'resp_1', 'status': 'completed', 'output': items}}


class Upstream(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    script = []          # [(delay_seconds, event dict | None)]  None で接続を切る
    requests = []        # [(path, headers dict, body bytes)]
    plain = None         # (status, content_type, body) for non-SSE answers

    def log_message(self, *a):
        pass

    def handle_any(self):
        n = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(n) if n else b''
        if (self.headers.get('Content-Encoding') or '').lower() == 'zstd':
            from compression import zstd
            body = zstd.decompress(body)
        Upstream.requests.append((self.path, {k.lower(): v for k, v in self.headers.items()}, body))
        if Upstream.plain:
            status, ctype, payload = Upstream.plain
            self.send_response(status)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_response(200)
        self.send_header('Transfer-Encoding', 'chunked')   # 実物の上流は Content-Type を付けないことがある
        self.end_headers()
        for delay, event in Upstream.script:
            time.sleep(delay)
            if event is None:
                self.close_connection = True
                return
            chunk = sse(event)
            self.wfile.write(b'%x\r\n%s\r\n' % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b'0\r\n\r\n')

    do_POST = handle_any
    do_GET = handle_any


class RelayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.upstream = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
        threading.Thread(target=cls.upstream.serve_forever, daemon=True).start()
        cls.checker = cls.tmp / 'check.py'
        cls.checker.write_text(textwrap.dedent(f'''\
            import json, sys, time, os
            payload = json.load(sys.stdin)
            open({str(cls.tmp / 'checker-input.json')!r}, 'a', encoding='utf-8').write(json.dumps(payload) + "\\n")
            time.sleep(float(os.environ.get('FAKE_CHECK_SLEEP', '0')))
            open({str(cls.tmp / 'checker-finished')!r}, 'a').write('x')
            if os.environ.get('FAKE_CHECK_NO_REASON'):
                print(json.dumps({{"status": "unchecked", "text": payload["draft"]}}))
            elif os.environ.get('FAKE_CHECK_FAIL'):
                print(json.dumps({{"status": "unchecked", "reason": "fake failure",
                                   "text": "[出力ゲート: 検査できませんでした — fake failure]\\n\\n" + payload["draft"]}}))
            else:
                print(json.dumps({{"status": "checked", "text": payload["draft"].replace("効く", "速い"),
                                   "reason": None, "applied": 1}}))
            sys.exit(int(os.environ.get('FAKE_CHECK_EXIT', '0')))
            '''), encoding='utf-8')

    @classmethod
    def tearDownClass(cls):
        cls.upstream.shutdown()

    def setUp(self):
        Upstream.script, Upstream.requests, Upstream.plain = [], [], None
        (self.tmp / 'checker-input.json').unlink(missing_ok=True)
        (self.tmp / 'checker-finished').unlink(missing_ok=True)
        self.port = free_port()
        self.state = Path(tempfile.mkdtemp())
        self.start_relay()

    def start_relay(self, check_sleep='0', check_fail='', check_exit='0', check_no_reason='', extra_env=None):
        env = dict(os.environ, OUTPUT_GATE_CHECK_CMD=json.dumps([sys.executable, '-I', str(self.checker)]),
                   OUTPUT_GATE_KEEPALIVE='0.5', FAKE_CHECK_SLEEP=check_sleep, FAKE_CHECK_FAIL=check_fail,
                   FAKE_CHECK_EXIT=check_exit, FAKE_CHECK_NO_REASON=check_no_reason)
        env.update(extra_env or {})
        self.relay = subprocess.Popen(
            [sys.executable, '-I', str(RELAY), '--port', str(self.port), '--state-dir', str(self.state),
             '--upstream', f'http://127.0.0.1:{self.upstream.server_port}{PREFIX}'],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                status, _, body = self.call('GET', '/__gate/version')
                if status == 200:
                    return
            except OSError:
                time.sleep(0.1)
        self.fail('relay did not start: ' + self.relay.stderr.read().decode(errors='replace'))

    def tearDown(self):
        self.relay.kill()
        self.relay.wait(5)
        self.relay.stderr.close()

    def call(self, method, path, body=None, headers=None, timeout=10):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=timeout)
        payload = json.dumps(body).encode() if isinstance(body, dict) else body
        conn.request(method, path, body=payload, headers=headers or {})
        resp = conn.getresponse()
        data = resp.read()
        conn.close()
        return resp.status, dict(resp.getheaders()), data

    def restart_relay(self, **kw):
        self.relay.kill(); self.relay.wait(5); self.relay.stderr.close()
        self.start_relay(**kw)

    def checker_inputs(self):
        path = self.tmp / 'checker-input.json'
        return [json.loads(l) for l in path.read_text(encoding='utf-8').splitlines()] if path.exists() else []

    def turn(self, body=None, kind='turn', extra_headers=None, timeout=10, session='s1'):
        meta = {'session_id': session, 'request_kind': kind} if kind else {}
        headers = {'Content-Type': 'application/json', 'x-codex-turn-metadata': json.dumps(meta)}
        headers.update(extra_headers or {})
        body = body or {'model': 'm', 'input': [
            {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': '設定を教えて'}]}],
            'stream': True}
        status, _, data = self.call('POST', PREFIX + '/responses', body, headers, timeout)
        events = []
        for block in data.decode('utf-8').split('\n\n'):
            for line in block.splitlines():
                if line.startswith('data:'):
                    events.append(json.loads(line[5:]))
        return status, events

    @staticmethod
    def final_text(events):
        done = [e for e in events if e['type'] == 'response.output_text.done']
        return done[-1]['text'] if done else None

    def test_turn_answer_rewritten(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, {'type': 'response.created', 'response': {}})] + [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn()
        self.assertEqual(status, 200)
        self.assertEqual(self.final_text(events), 'これは速い。')
        deltas = ''.join(e['delta'] for e in events if e['type'] == 'response.output_text.delta')
        self.assertEqual(deltas, 'これは速い。')
        done_item = [e for e in events if e['type'] == 'response.output_item.done'][-1]['item']
        self.assertEqual(done_item['content'][0]['text'], 'これは速い。')
        out = [e for e in events if e['type'] == 'response.completed'][0]['response']['output'][0]
        self.assertEqual(out['content'][0]['text'], 'これは速い。')
        sent = json.loads((self.tmp / 'checker-input.json').read_text(encoding='utf-8').splitlines()[0])
        self.assertEqual(sent['latest_user'], '設定を教えて')
        self.assertEqual(sent['cli'], 'codex')

    def test_tool_call_item_passes_immediately(self):
        call = {'id': 'fc_1', 'type': 'function_call', 'name': 'shell', 'arguments': '{"cmd":"ls"}', 'call_id': 'c1'}
        Upstream.script = [(0, {'type': 'response.output_item.added', 'output_index': 0, 'item': call}),
                           (0, {'type': 'response.output_item.done', 'output_index': 0, 'item': call}),
                           (1.5, completed([call]))]
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=10)
        conn.request('POST', PREFIX + '/responses', json.dumps({'input': []}).encode(),
                     {'x-codex-turn-metadata': json.dumps({'request_kind': 'turn'})})
        resp = conn.getresponse()
        start = time.time()
        first = resp.read1(65536)
        self.assertLess(time.time() - start, 1.0)
        self.assertIn(b'function_call', first)
        conn.close()

    def test_keepalive_during_hold(self):
        self.relay.kill(); self.relay.wait(5); self.relay.stderr.close()
        self.start_relay(check_sleep='3')
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=1.5)
        conn.request('POST', PREFIX + '/responses', json.dumps({'input': []}).encode(),
                     {'x-codex-turn-metadata': json.dumps({'request_kind': 'turn'})})
        resp = conn.getresponse()
        data = b''
        while True:
            chunk = resp.read1(65536)   # raises socket.timeout if idle > 1.5 s
            if not chunk:
                break
            data += chunk
        self.assertIn(b'response.in_progress', data)
        self.assertIn('これは速い。'.encode(), data)
        conn.close()

    def test_output_schema_not_checked(self):
        evs, item = message_events('msg_1', '{"a": "効く"}')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn({'input': [], 'text': {'format': {'type': 'json_schema', 'name': 'x', 'schema': {}}}})
        self.assertEqual(self.final_text(events), '{"a": "効く"}')
        self.assertFalse((self.tmp / 'checker-input.json').exists())

    def test_unknown_request_kind_unchecked(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(kind=None)
        text = self.final_text(events)
        self.assertTrue(text.startswith('[出力ゲート: 検査できませんでした'))
        self.assertTrue(text.endswith('これは効く。'))

    def test_compaction_kind_passes(self):
        item = {'id': 'cmp_1', 'type': 'compaction', 'encrypted_content': 'ENC'}
        Upstream.script = [(0, {'type': 'response.output_item.done', 'output_index': 0, 'item': item}),
                           (0, completed([item]))]
        status, events = self.turn(kind='compaction')
        self.assertEqual(events[0]['item']['encrypted_content'], 'ENC')
        self.assertFalse((self.tmp / 'checker-input.json').exists())

    def test_websocket_upgrade_426(self):
        status, _, _ = self.call('GET', PREFIX + '/responses',
                                 headers={'Connection': 'Upgrade', 'Upgrade': 'websocket',
                                          'Sec-WebSocket-Key': 'x', 'Sec-WebSocket-Version': '13'})
        self.assertEqual(status, 426)
        self.assertEqual(Upstream.requests, [])

    def test_encrypted_content_stripped(self):
        evs, item = message_events('msg_1', 'OK', encrypted='ENC-OUT')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        body = {'input': [
            {'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': 'prev'}],
             'encrypted_content': 'ENC-PREV'},
            {'type': 'reasoning', 'summary': [], 'encrypted_content': 'ENC-REASON'},
            {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': 'q'}]}]}
        status, events = self.turn(body)
        sent = json.loads(Upstream.requests[0][2])
        self.assertNotIn('encrypted_content', sent['input'][0])
        self.assertEqual(sent['input'][1]['encrypted_content'], 'ENC-REASON')
        self.assertNotIn(b'ENC-OUT', json.dumps(events).encode())

    def test_failed_response_passthrough(self):
        evs, item = message_events('msg_1', 'これは効く。')
        failed = {'type': 'response.failed', 'response': {'id': 'r', 'status': 'failed', 'error': {'message': 'boom'}}}
        Upstream.script = [(0, e) for e in evs[:3]] + [(0, failed)]
        status, events = self.turn()
        self.assertEqual(events[-1]['type'], 'response.failed')
        self.assertFalse((self.tmp / 'checker-input.json').exists())

    def test_unreadable_body_error(self):
        status, _, data = self.call('POST', PREFIX + '/responses', b'\x00garbage',
                                    {'Content-Encoding': 'zstd', 'x-codex-turn-metadata': '{"request_kind":"turn"}'})
        self.assertGreaterEqual(status, 400)
        self.assertEqual(Upstream.requests, [])

    def test_non_responses_path_proxied(self):
        Upstream.plain = (200, 'application/json', b'{"models": []}')
        status, _, data = self.call('GET', PREFIX + '/models?client_version=1')
        self.assertEqual(status, 200)
        self.assertEqual(data, b'{"models": []}')
        self.assertEqual(Upstream.requests[0][0], PREFIX + '/models?client_version=1')

    def test_upstream_error_status_passthrough(self):
        Upstream.plain = (429, 'application/json', b'{"error": {"message": "rate"}}')
        status, _, data = self.call('POST', PREFIX + '/responses', {'input': []},
                                    {'x-codex-turn-metadata': '{"request_kind":"turn"}'})
        self.assertEqual(status, 429)
        self.assertEqual(data, b'{"error": {"message": "rate"}}')

    # ---- 委譲・compaction・/review・cyber ---------------------------------------------------------
    def test_delegated_session_passthrough(self):
        (self.state / 'delegated').mkdir(parents=True, exist_ok=True)
        (self.state / 'delegated' / 'child-1').write_text('', encoding='utf-8')
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(session='child-1')
        self.assertEqual(self.final_text(events), 'これは効く。')
        self.assertEqual(self.checker_inputs(), [])

    @staticmethod
    def assistant(text):
        return {'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': text}]}

    @staticmethod
    def user(text):
        return {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': text}]}

    def compact(self, input_items, enc):
        item = {'id': 'cmp', 'type': 'compaction', 'encrypted_content': enc}
        Upstream.script = [(0, {'type': 'response.output_item.done', 'output_index': 0, 'item': item}),
                           (0, completed([item]))]
        status, events = self.turn({'input': input_items}, kind='compaction')
        self.assertEqual(events[-1]['type'], 'response.completed')

    def turn_after(self, input_items):
        evs, item = message_events('msg_9', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        self.turn({'input': input_items})
        return self.checker_inputs()[-1]

    def test_compaction_pairs_saved_and_used(self):
        self.compact([self.user('q1'), self.assistant('答え1'), self.user('q2'), self.assistant('答え2')], 'ENC1')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC1'}, self.user('q3')])
        texts = [t['text'] for t in sent['conversation'] if t['role'] == 'assistant']
        self.assertEqual(texts, ['答え1', '答え2'])
        self.assertFalse(sent['compacted_note'])

    def test_compaction_pairs_survive_restart(self):
        self.compact([self.user('q1'), self.assistant('答え1')], 'ENC1')
        self.restart_relay()
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC1'}, self.user('q3')])
        self.assertIn('答え1', [t['text'] for t in sent['conversation']])

    def test_compaction_chain(self):
        self.compact([self.user('q1'), self.assistant('答え1')], 'ENC1')
        self.compact([{'type': 'compaction', 'encrypted_content': 'ENC1'}, self.user('q2'), self.assistant('答え2')], 'ENC2')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC2'}, self.user('q3')])
        texts = [t['text'] for t in sent['conversation'] if t['role'] == 'assistant']
        self.assertEqual(texts, ['答え1', '答え2'])

    def test_unknown_compaction_item_noted(self):
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC-UNKNOWN'}, self.user('q3')])
        self.assertTrue(sent['compacted_note'])

    def review_text(self):
        return json.dumps({'findings': [{'title': '効くタイトル', 'body': '効く本文', 'confidence_score': 0.5,
                                         'priority': 1, 'code_location': {'absolute_file_path': '/a.py',
                                                                         'line_range': {'start': 1, 'end': 2}}}],
                           'overall_correctness': 'patch is correct', 'overall_explanation': '効く説明',
                           'overall_confidence_score': 0.9}, ensure_ascii=False)

    def test_review_explanation_only(self):
        evs, item = message_events('msg_r', self.review_text())
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'})
        out = json.loads(self.final_text(events))
        self.assertEqual(out['overall_explanation'], '速い説明')
        self.assertEqual(out['findings'][0]['title'], '速いタイトル')
        self.assertEqual(out['findings'][0]['body'], '速い本文')
        original = json.loads(self.review_text())
        self.assertEqual(out['findings'][0]['code_location'], original['findings'][0]['code_location'])
        self.assertEqual(out['overall_correctness'], 'patch is correct')

    def test_review_failure_reason_in_explanation(self):
        self.restart_relay(check_fail='1')
        evs, item = message_events('msg_r', self.review_text())
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'})
        out = json.loads(self.final_text(events))
        self.assertTrue(out['overall_explanation'].startswith('[出力ゲート: 検査できませんでした'))
        self.assertEqual(out['findings'][0]['title'], '効くタイトル')

    def test_other_subagent_passthrough(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'collab_spawn'})
        self.assertEqual(self.final_text(events), 'これは効く。')

    def test_cyber_program_forwarded(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        self.turn({'input': [self.user('q')], 'access_programs': {'cyber': 'daybreak_blue'}})
        self.assertEqual(self.checker_inputs()[-1]['cyber_program'], 'daybreak_blue')


    # ---- 版の入れ替えと自己試験 -----------------------------------------------------------------------
    def test_version_reports_active_requests(self):
        status, _, data = self.call('GET', '/__gate/version')
        info = json.loads(data)
        self.assertEqual(info['active'], 0)
        self.assertIn('version', info)

    def test_shutdown_refused_while_busy(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs[:2]] + [(2.0, e) for e in evs[2:]] + [(0, completed([item]))]
        result = {}
        thread = threading.Thread(target=lambda: result.setdefault('r', self.turn()))
        thread.start()
        time.sleep(0.7)
        status, _, _ = self.call('POST', '/__gate/shutdown')
        self.assertEqual(status, 409)
        thread.join(20)
        status, _, _ = self.call('POST', '/__gate/shutdown')
        self.assertEqual(status, 200)
        self.relay.wait(5)

    def test_self_test_passes(self):
        result = subprocess.run([sys.executable, '-I', str(RELAY), '--port', '0', '--state-dir', str(self.state),
                                 '--self-test'], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ensure_replaces_old_version(self):
        old = self.tmp / 'old-relay.py'
        old.write_text(RELAY.read_text(encoding='utf-8') + '\n# old version marker\n', encoding='utf-8')
        self.relay.kill(); self.relay.wait(5); self.relay.stderr.close()
        env = dict(os.environ, OUTPUT_GATE_CHECK_CMD=json.dumps([sys.executable, '-I', str(self.checker)]))
        self.relay = subprocess.Popen([sys.executable, '-I', str(old), '--port', str(self.port),
                                       '--state-dir', str(self.state)], env=env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            try:
                if self.call('GET', '/__gate/version')[0] == 200:
                    break
            except OSError:
                time.sleep(0.1)
        old_version = json.loads(self.call('GET', '/__gate/version')[2])['version']
        result = subprocess.run([sys.executable, '-I', str(RELAY), '--port', str(self.port),
                                 '--state-dir', str(self.state), '--ensure'], capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)['state'], 'updated')
        info = json.loads(self.call('GET', '/__gate/version')[2])
        self.assertNotEqual(info['version'], old_version)
        self.relay.wait(5)   # 古い版は終了している
        new_pid = info['pid']
        self.addCleanup(lambda: subprocess.run(['taskkill', '/PID', str(new_pid), '/F'], capture_output=True)
                        if os.name == 'nt' else os.kill(new_pid, 9))


    # ---- 失敗・切断・イベントの組み立て -------------------------------------------------------------
    def test_failed_while_holding_drops_answer(self):
        evs, item = message_events('msg_1', 'これは効く。')
        failed = {'type': 'response.failed', 'response': {'id': 'r', 'status': 'failed', 'error': {'message': 'x'}}}
        Upstream.script = [(0, e) for e in evs[:4]] + [(0, failed)]
        status, events = self.turn()
        self.assertEqual(events[-1]['type'], 'response.failed')
        self.assertNotIn('これは', json.dumps(events, ensure_ascii=False))

    def test_disconnect_while_holding_drops_answer(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs[:4]] + [(0, None)]
        status, events = self.turn()
        self.assertNotIn('これは', json.dumps(events, ensure_ascii=False))

    def test_keepalive_while_upstream_keeps_streaming(self):
        evs, item = message_events('msg_1', 'これは効く。')
        extra = [{'type': 'response.output_text.delta', 'item_id': 'msg_1', 'output_index': 0,
                  'content_index': 0, 'delta': ''} for _ in range(10)]
        Upstream.script = [(0, evs[0])] + [(0.3, e) for e in extra] + [(0, e) for e in evs[1:]] + [(0, completed([item]))]
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=1.2)
        conn.request('POST', PREFIX + '/responses', json.dumps({'input': []}).encode(),
                     {'x-codex-turn-metadata': json.dumps({'request_kind': 'turn'})})
        resp = conn.getresponse()
        data = b''
        while True:
            chunk = resp.read1(65536)   # socket.timeout if nothing arrives for 1.2 s
            if not chunk:
                break
            data += chunk
        self.assertIn('これは速い。'.encode(), data)
        conn.close()

    def test_message_without_added_event_is_checked(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs[1:]] + [(0, completed([item]))]
        status, events = self.turn()
        self.assertEqual(self.final_text(events), 'これは速い。')
        self.assertNotIn('これは効く', json.dumps(events, ensure_ascii=False))

    def test_message_missing_from_completed_output_is_checked(self):
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([]))]
        status, events = self.turn()
        self.assertEqual(self.final_text(events), 'これは速い。')
        self.assertNotIn('これは効く', json.dumps(events, ensure_ascii=False))

    def test_two_messages_are_both_checked(self):
        evs1, item1 = message_events('msg_1', '途中で効く。')
        evs2, item2 = message_events('msg_2', '最後に効く。')
        for e in evs2:
            e['output_index'] = 1
        Upstream.script = [(0, e) for e in evs1 + evs2] + [(0, completed([item1, item2]))]
        status, events = self.turn()
        text = json.dumps(events, ensure_ascii=False)
        self.assertIn('途中で速い。', text)
        self.assertIn('最後に速い。', text)
        self.assertNotIn('効く', text)

    def test_client_disconnect_stops_checker(self):
        self.restart_relay(check_sleep='4')
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=10)
        conn.request('POST', PREFIX + '/responses', json.dumps({'input': []}).encode(),
                     {'x-codex-turn-metadata': json.dumps({'request_kind': 'turn'})})
        resp = conn.getresponse()
        resp.read1(10)
        time.sleep(1.0)
        conn.sock.close()
        conn.close()
        time.sleep(6)
        self.assertFalse((self.tmp / 'checker-finished').exists())

    def test_compaction_item_only_in_output_item_done(self):
        item = {'id': 'cmp', 'type': 'compaction', 'encrypted_content': 'ENC9'}
        Upstream.script = [(0, {'type': 'response.output_item.done', 'output_index': 0, 'item': item}),
                           (0, completed([]))]
        self.turn({'input': [self.user('q1'), self.assistant('答え1')]}, kind='compaction')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC9'}, self.user('q2')])
        self.assertIn('答え1', [t['text'] for t in sent['conversation']])

    def test_commentary_not_kept_for_compaction(self):
        commentary = dict(self.assistant('途中経過'), phase='commentary')
        self.compact([self.user('q1'), self.assistant('答え1'), commentary], 'ENC7')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC7'}, self.user('q2')])
        texts = [t['text'] for t in sent['conversation']]
        self.assertIn('答え1', texts)
        self.assertNotIn('途中経過', texts)

    def test_multi_part_message_checked_per_part(self):
        texts = ['これは効く。', '次も効く。']
        item = {'id': 'msg_m', 'type': 'message', 'role': 'assistant', 'status': 'completed',
                'content': [{'type': 'output_text', 'text': t, 'annotations': []} for t in texts]}
        evs = [{'type': 'response.output_item.added', 'output_index': 0, 'item': dict(item, content=[])}]
        for ci, text in enumerate(texts):
            base = {'item_id': 'msg_m', 'output_index': 0, 'content_index': ci}
            evs += [dict(base, type='response.content_part.added', part={'type': 'output_text', 'text': ''}),
                    dict(base, type='response.output_text.delta', delta=text),
                    dict(base, type='response.output_text.done', text=text),
                    dict(base, type='response.content_part.done', part={'type': 'output_text', 'text': text})]
        evs.append({'type': 'response.output_item.done', 'output_index': 0, 'item': item})
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn()
        want = ['これは速い。', '次も速い。']
        done = {e['content_index']: e['text'] for e in events if e['type'] == 'response.output_text.done'}
        self.assertEqual(done, {0: want[0], 1: want[1]})
        deltas = {}
        for e in events:
            if e['type'] == 'response.output_text.delta':
                deltas[e['content_index']] = deltas.get(e['content_index'], '') + e['delta']
        self.assertEqual(deltas, {0: want[0], 1: want[1]})
        parts = {e['content_index']: e['part']['text'] for e in events if e['type'] == 'response.content_part.done'}
        self.assertEqual(parts, {0: want[0], 1: want[1]})
        done_item = [e for e in events if e['type'] == 'response.output_item.done'][-1]['item']
        self.assertEqual([p['text'] for p in done_item['content']], want)
        out = [e for e in events if e['type'] == 'response.completed'][0]['response']['output'][0]
        self.assertEqual([p['text'] for p in out['content']], want)

    def test_latest_user_kept_before_compaction_item(self):
        # Codex は保持した利用者の発言の後ろに compaction の項目を置く
        sent = self.turn_after([self.user('最新の依頼'), {'type': 'compaction', 'encrypted_content': 'ENC-L'}])
        self.assertEqual(sent['latest_user'], '最新の依頼')
        self.assertIn('最新の依頼', [t['text'] for t in sent['conversation'] if t['role'] == 'user'])

    def test_review_json_inside_fence_gets_failure_reason(self):
        # Codex は最初の { から最後の } までを JSON として読み、外側の文字列は捨てる
        self.restart_relay(check_fail='1')
        evs, item = message_events('msg_r', '```json\n' + self.review_text() + '\n```')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'})
        text = self.final_text(events)
        out = json.loads(text[text.index('{'):text.rindex('}') + 1])
        self.assertTrue(out['overall_explanation'].startswith('[出力ゲート: 検査できませんでした'))

    # ---- 検査処理の終了・環境・検査結果の形 ------------------------------------------------------------
    def test_tool_call_after_message_keeps_order_and_arguments(self):
        evs, item = message_events('msg_1', 'これは効く。')
        call = {'id': 'fc_1', 'type': 'function_call', 'name': 'shell', 'arguments': '{"cmd":"効く"}', 'call_id': 'c1'}
        Upstream.script = [(0, e) for e in evs] + [
            (0, {'type': 'response.output_item.added', 'output_index': 1, 'item': call}),
            (0, {'type': 'response.output_item.done', 'output_index': 1, 'item': call}),
            (0, completed([item, call]))]
        status, events = self.turn()
        done = [e['item'] for e in events if e['type'] == 'response.output_item.done']
        self.assertEqual([d['type'] for d in done], ['message', 'function_call'])
        self.assertEqual(done[0]['content'][0]['text'], 'これは速い。')
        self.assertEqual(done[1], call)

    def test_missing_compaction_pair_is_logged(self):
        self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC-NONE'}, self.user('q')])
        log = (self.state / 'relay.log').read_text(encoding='utf-8')
        self.assertIn('compaction-pair-missing', log)

    def test_detached_relay_gets_only_needed_environment(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('output_gate_relay', RELAY)
        relay = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(relay)
        env = relay.relay_env({'PATH': '/bin', 'HOME': '/h', 'SYSTEMROOT': 'C:\\Windows',
                               'AGENT_DELEGATED_SESSION': '1', 'OUTPUT_GATE_CHECK_CMD': '[]',
                               'OPENAI_API_KEY': 'x', 'SOME_SESSION_VALUE': 'y'})
        self.assertEqual(env, {'PATH': '/bin', 'HOME': '/h', 'SYSTEMROOT': 'C:\\Windows'})

    def test_ensure_keeps_old_version_when_self_test_fails(self):
        new_dir = self.tmp / 'broken-new'
        new_dir.mkdir(exist_ok=True)
        new_relay = new_dir / 'output-gate-relay.py'
        new_relay.write_text(RELAY.read_text(encoding='utf-8') + '\n# new version marker\n', encoding='utf-8')
        (new_dir / 'output-gate-check.py').write_text('def broken(:\n', encoding='utf-8')
        before = json.loads(self.call('GET', '/__gate/version')[2])
        result = subprocess.run([sys.executable, '-I', str(new_relay), '--port', str(self.port),
                                 '--state-dir', str(self.state), '--ensure'], capture_output=True, text=True, timeout=90)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['state'], 'update-failed')
        after = json.loads(self.call('GET', '/__gate/version')[2])
        self.assertEqual((after['version'], after['pid']), (before['version'], before['pid']))

    def test_checker_exit_code_failure_is_unchecked(self):
        self.restart_relay(check_exit='7')
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn()
        text = self.final_text(events)
        self.assertTrue(text.startswith('[出力ゲート: 検査できませんでした'), text)
        self.assertTrue(text.endswith('これは効く。'))

    def test_partial_answer_not_kept_for_compaction(self):
        partials = [dict(self.assistant(f'断片{n}'), phase='partial_answer') for n in range(3)]
        self.compact([self.user('q1'), dict(self.assistant('答え1'), phase='final_answer'), *partials], 'ENC8')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC8'}, self.user('q2')])
        texts = [t['text'] for t in sent['conversation']]
        self.assertIn('答え1', texts)
        self.assertFalse([t for t in texts if t.startswith('断片')])

    def test_added_events_do_not_carry_original_text(self):
        evs, item = message_events('msg_1', 'これは効く。')
        evs[0]['item']['content'] = [{'type': 'output_text', 'text': 'これは効く。', 'annotations': []}]
        evs[1]['part']['text'] = 'これは効く。'
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn()
        self.assertNotIn('効く', json.dumps(events, ensure_ascii=False))
        self.assertEqual(self.final_text(events), 'これは速い。')

    def test_review_without_review_fields_is_checked_as_text(self):
        evs, item = message_events('msg_r', '{"message": "これは効く。"}')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'})
        self.assertEqual(self.final_text(events), '{"message": "これは速い。"}')

    def test_empty_part_is_not_sent_to_checker(self):
        evs, item = message_events('msg_1', '')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn()
        self.assertEqual(self.final_text(events), '')
        self.assertEqual(self.checker_inputs(), [])

    def test_disconnect_stops_the_whole_checker_tree(self):
        # 実物の検査処理 (output-gate-check.py → run-judge.py → 検査役) を通し、検査役まで止まることを確かめる。
        sleeper = self.tmp / 'sleeper.py'
        pid_file = self.tmp / 'sleeper.pid'
        pid_file.unlink(missing_ok=True)
        sleeper.write_text(f'import os, sys, time\nsys.stdin.read()\nopen({str(pid_file)!r}, "w").write(str(os.getpid()))\n'
                           'time.sleep(30)\n', encoding='utf-8')
        gitleaks = self.tmp / 'gitleaks-none.py'
        gitleaks.write_text('import json, sys\nargs = sys.argv[1:]\n'
                            'open(args[args.index("--report-path") + 1], "w").write("[]")\n', encoding='utf-8')
        rules = self.tmp / 'rules.md'
        rules.write_text('## 応答\n\n- 規則\n', encoding='utf-8')
        check = Path(RELAY).with_name('output-gate-check.py')
        self.restart_relay(extra_env={
            'OUTPUT_GATE_CHECK_CMD': json.dumps([sys.executable, '-I', str(check)]),
            'OUTPUT_GATE_CHECKER_CMD': json.dumps([sys.executable, '-I', str(sleeper)]),
            'OUTPUT_GATE_GITLEAKS': json.dumps([sys.executable, '-I', str(gitleaks)]),
            'OUTPUT_GATE_RULES': str(rules)})
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=10)
        conn.request('POST', PREFIX + '/responses', json.dumps({'input': []}).encode(),
                     {'x-codex-turn-metadata': json.dumps({'request_kind': 'turn'})})
        resp = conn.getresponse()
        resp.read1(10)
        for _ in range(100):
            if pid_file.exists() and pid_file.read_text():
                break
            time.sleep(0.1)
        pid = int(pid_file.read_text())
        conn.sock.close()
        conn.close()
        for _ in range(100):
            if not pid_alive(pid):
                break
            time.sleep(0.1)
        self.assertFalse(pid_alive(pid))

    def review_with_finding(self, **changes):
        review = json.loads(self.review_text())
        review['findings'][0].update(changes)
        review['overall_correctness'] = '効く'   # 説明の欄ではないので、レビューとして読めれば置き換わらない
        return json.dumps(review, ensure_ascii=False)

    def test_review_without_code_location_is_checked_as_text(self):
        review = json.loads(self.review_text())
        del review['findings'][0]['code_location']
        draft = json.dumps(review, ensure_ascii=False)
        evs, item = message_events('msg_r', draft)
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'})
        self.assertEqual(self.final_text(events), draft.replace('効く', '速い'))

    def test_review_with_out_of_range_priority_is_checked_as_text(self):
        draft = self.review_with_finding(priority=2 ** 40)
        evs, item = message_events('msg_r', draft)
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'})
        self.assertEqual(self.final_text(events), draft.replace('効く', '速い'))

    def test_unchecked_result_without_reason_gets_one(self):
        self.restart_relay(check_no_reason='1')
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn()
        text = self.final_text(events)
        self.assertTrue(text.startswith('[出力ゲート: 検査できませんでした'), text)
        self.assertTrue(text.endswith('これは効く。'))


if __name__ == '__main__':
    unittest.main()
