#!/usr/bin/env python3
"""出力ゲートの中継を、偽の上流と偽の検査処理で確かめる。"""
import http.client
import http.server
import json
import os
from pathlib import Path
import socket
import struct
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
UNAVAILABLE = '回答の確認を完了できませんでした。\n\n'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def input_text(item):
    return ''.join(p.get('text') or '' for p in item.get('content') or [])


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
        # 共通の検査処理 (output-gate-check.py) の入出力の形を真似る。findings-on の印があれば、最終回答に未達を 1 件返す。
        cls.checker.write_text(textwrap.dedent(f'''\
            import json, sys, time, os
            payload = json.load(sys.stdin)
            open({str(cls.tmp / 'checker-input.json')!r}, 'a', encoding='utf-8').write(json.dumps(payload) + "\\n")
            time.sleep(float(os.environ.get('FAKE_CHECK_SLEEP', '0')))
            open({str(cls.tmp / 'checker-finished')!r}, 'a').write('x')
            bodies = payload.get("bodies") or [payload.get("draft", "")]
            if payload.get('independent_recheck') and os.path.exists({str(cls.tmp / 'recheck-fail')!r}):
                print(json.dumps({{"status": "unchecked", "reason": "recheck unavailable", "text": "\\n\\n".join(bodies), "bodies": bodies}}))
            elif os.environ.get('FAKE_CHECK_NO_REASON'):
                print(json.dumps({{"status": "unchecked", "text": "\\n\\n".join(bodies), "bodies": bodies}}))
            elif os.environ.get('FAKE_CHECK_FAIL'):
                shown = ["[出力ゲート: 検査できませんでした — fake failure]\\n\\n" + bodies[0]] + bodies[1:]
                print(json.dumps({{"status": "unchecked", "reason": "fake failure", "text": "\\n\\n".join(shown),
                                   "bodies": shown}}))
            else:
                fixed = [b.replace("効く", "速い") for b in bodies]
                result = {{"status": "checked", "reason": None, "findings": [], "agent_message": None,
                          "fallback_text": None, "fallback_bodies": None, "unmet_text": None, "applied": 1,
                          "engine": {{"family": "codex", "model": "m", "effort": "high"}},
                          "engine_failures": [{{"family": "claude", "reason": "claude failed first"}}],
                          "dropped": [{{"finding": {{}}, "reason": "excerpt not in source"}}],
                          "progress_state": {{"round": payload.get("round", 0), "stalled": 0,
                            "bodies": fixed, "findings": [], "evidence": payload.get("evidence", [])}},
                          "text": "\\n\\n".join(fixed), "bodies": fixed}}
                if os.path.exists({str(cls.tmp / 'findings-on')!r}) and payload.get("final") and not (payload.get('independent_recheck') and os.path.exists({str(cls.tmp / 'recheck-clean')!r})):
                    found = [{{"kind": "unverified_claim", "source": "draft", "excerpt": open({str(cls.tmp / 'findings-on')!r}, encoding='utf-8').read() or "確認済み", "evidence": []}}]
                    unmet = "出力ゲート: 次の点は確かめられていません\\n- UNMET-ITEM"
                    marked = fixed[:-1] + [fixed[-1] + "\\n\\n---\\n" + unmet]
                    result.update(findings=found, unmet_text=unmet, display_text="\\n\\n".join(marked),
                                  display_bodies=marked, corrected_bodies=fixed)
                    if payload.get("continuation") == "none":
                        result.update(text="\\n\\n".join(marked), bodies=marked)
                    else:
                        fallback = ["[出力ゲート: 指摘を保存できなかったため、直させずに表示します]\\n\\n" + marked[0]] + marked[1:]
                        result.update(text=None, bodies=None, agent_message="AGENT-MSG: 確かめて",
                                      fallback_text="\\n\\n".join(fallback), fallback_bodies=fallback)
                print(json.dumps(result))
            sys.exit(int(os.environ.get('FAKE_CHECK_EXIT', '0')))
            '''), encoding='utf-8')

    @classmethod
    def tearDownClass(cls):
        cls.upstream.shutdown()

    def setUp(self):
        Upstream.script, Upstream.requests, Upstream.plain = [], [], None
        (self.tmp / 'checker-input.json').unlink(missing_ok=True)
        (self.tmp / 'checker-finished').unlink(missing_ok=True)
        (self.tmp / 'findings-on').unlink(missing_ok=True)
        (self.tmp / 'recheck-clean').unlink(missing_ok=True)
        (self.tmp / 'recheck-fail').unlink(missing_ok=True)
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

    def turn(self, body=None, kind='turn', extra_headers=None, timeout=10, session='s1', turn_id=None):
        meta = {'session_id': session, 'request_kind': kind} if kind else {}
        if turn_id:
            meta['turn_id'] = turn_id
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
        self.assertEqual(sent['origin'], 'codex')
        self.assertTrue(sent['final'])

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
        self.assertEqual(text, UNAVAILABLE + 'これは効く。')

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
    def assistant_notice(marker):
        return {'id': marker, 'type': 'message', 'role': 'assistant',
                'content': [{'type': 'output_text', 'text': ''}]}

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
        texts = [t['text'] for t in sent['recent_messages'] if t['role'] == 'assistant']
        self.assertEqual(texts, ['答え1', '答え2'])
        self.assertFalse(sent['compacted_note'])

    def test_compaction_pairs_survive_restart(self):
        self.compact([self.user('q1'), self.assistant('答え1')], 'ENC1')
        self.restart_relay()
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC1'}, self.user('q3')])
        self.assertIn('答え1', [t['text'] for t in sent['recent_messages']])

    def test_compaction_chain(self):
        self.compact([self.user('q1'), self.assistant('答え1')], 'ENC1')
        self.compact([{'type': 'compaction', 'encrypted_content': 'ENC1'}, self.user('q2'), self.assistant('答え2')], 'ENC2')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC2'}, self.user('q3')])
        texts = [t['text'] for t in sent['recent_messages'] if t['role'] == 'assistant']
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
        self.assertEqual(out['overall_explanation'], UNAVAILABLE + '効く説明')
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
        self.assertFalse(thread.is_alive())
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            _, _, data = self.call('GET', '/__gate/version')
            if json.loads(data)['active'] == 0:
                break
            time.sleep(0.05)
        self.assertEqual(json.loads(data)['active'], 0)
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
        self.assertIn('答え1', [t['text'] for t in sent['recent_messages']])

    def test_commentary_not_kept_for_compaction(self):
        commentary = dict(self.assistant('途中経過'), phase='commentary')
        self.compact([self.user('q1'), self.assistant('答え1'), commentary], 'ENC7')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC7'}, self.user('q2')])
        texts = [t['text'] for t in sent['recent_messages']]
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
        self.assertIn('最新の依頼', [t['text'] for t in sent['recent_messages'] if t['role'] == 'user'])

    def test_review_json_inside_fence_gets_failure_reason(self):
        # Codex は最初の { から最後の } までを JSON として読み、外側の文字列は捨てる
        self.restart_relay(check_fail='1')
        evs, item = message_events('msg_r', '```json\n' + self.review_text() + '\n```')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'})
        text = self.final_text(events)
        out = json.loads(text[text.index('{'):text.rindex('}') + 1])
        self.assertEqual(out['overall_explanation'], UNAVAILABLE + '効く説明')

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
        self.assertEqual(done[0]['content'][0]['text'], 'これは効く。')
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
                               'OUTPUT_GATE_SETTINGS': '/s/checker.json',
                               'OPENAI_API_KEY': 'x', 'SOME_SESSION_VALUE': 'y'})
        # 検査役の設定ファイルの場所は、どの環境から起動した中継でも同じ設定を使うために通す。
        self.assertEqual(env, {'PATH': '/bin', 'HOME': '/h', 'SYSTEMROOT': 'C:\\Windows',
                               'OUTPUT_GATE_SETTINGS': '/s/checker.json'})

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
        self.assertEqual(text, UNAVAILABLE + 'これは効く。')

    def test_partial_answer_not_kept_for_compaction(self):
        partials = [dict(self.assistant(f'断片{n}'), phase='partial_answer') for n in range(3)]
        self.compact([self.user('q1'), dict(self.assistant('答え1'), phase='final_answer'), *partials], 'ENC8')
        sent = self.turn_after([{'type': 'compaction', 'encrypted_content': 'ENC8'}, self.user('q2')])
        texts = [t['text'] for t in sent['recent_messages']]
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
        self.restart_with_real_checker(sleeper.read_text(encoding='utf-8'))
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

    AUTH_ERROR_LINE = ('2026-11-02T03:25:44.557043Z ERROR codex_api::endpoint::responses_websocket: failed to '
                       'connect to websocket: HTTP error: 401 Unauthorized, url: wss://api.openai.com/v1/responses')

    def restart_with_real_checker(self, fake_codex_source, fake_claude_source=None, secrets=()):
        """実物の検査処理 (output-gate-check.py → run-judge.py) の先に、偽の検査役を置いて中継を起動し直す。
        試験の差し替えは中継のプロセスの環境変数で渡す (hook が切り離して起動する中継は RELAY_ENV だけを受け取る)。
        中継は origin=codex を渡すため、既定では Claude の系統が先に動く。偽の claude を渡さない試験は、設定
        (first=same) で Codex の系統を先にし、Claude の系統は未ログインですぐ失敗させる。"""
        fake = self.tmp / 'fake-codex.py'
        fake.write_text(fake_codex_source, encoding='utf-8')
        claude = self.tmp / 'fake-claude.py'
        claude.write_text(fake_claude_source or (
            'import json, sys\nsys.stdin.read()\n'
            'print(json.dumps({"is_error": True, "result": "Not logged in - Please run /login"}))\n'),
            encoding='utf-8')
        # 本物の gitleaks と同じく、検査した入力に残っている秘密情報だけを報告する。検査処理は伏せた後の入力に
        # もう一度 gitleaks をかけ、検出が残れば検査役を起動しないため。
        gitleaks = self.tmp / 'gitleaks-fake.py'
        gitleaks.write_text('import json, sys\nargs = sys.argv[1:]\n'
                            'text = open(args[args.index("--source") + 1], encoding="utf-8").read()\n'
                            f'found = [{{"Secret": s}} for s in {list(secrets)!r} if s in text]\n'
                            'open(args[args.index("--report-path") + 1], "w").write(json.dumps(found))\n',
                            encoding='utf-8')
        rules = self.tmp / 'rules.md'
        rules.write_text('## 応答\n\n- 規則\n', encoding='utf-8')
        settings = self.tmp / 'checker-settings.json'
        settings.write_text(json.dumps({'first': 'same' if fake_claude_source is None else 'opposite'}),
                            encoding='utf-8')
        check = Path(RELAY).with_name('output-gate-check.py')
        self.restart_relay(extra_env={
            'OUTPUT_GATE_CHECK_CMD': json.dumps([sys.executable, '-I', str(check)]),
            'OUTPUT_GATE_CODEX_CMD': json.dumps([sys.executable, '-I', str(fake)]),
            'OUTPUT_GATE_CLAUDE_CMD': json.dumps([sys.executable, '-I', str(claude)]),
            'OUTPUT_GATE_SETTINGS': str(settings),
            'OUTPUT_GATE_GITLEAKS': json.dumps([sys.executable, '-I', str(gitleaks)]),
            'OUTPUT_GATE_RULES': str(rules)})

    def test_checker_login_failure_is_reported_quickly(self):
        # 検査役の Codex のログインが無効だと、Codex は 401 を出しながら 15 秒ほど再試行してから終わる (実測)。
        # 再試行を待たずに、ログインし直す手順を理由に添えて原文を返す。
        self.restart_with_real_checker(
            'import sys, time\nsys.stdin.read()\n'
            f'for _ in range(4):\n    print({self.AUTH_ERROR_LINE!r}, file=sys.stderr, flush=True)\n    time.sleep(0.05)\n'
            'time.sleep(30)\n')
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        started = time.time()
        status, events = self.turn(timeout=40)
        elapsed = time.time() - started
        text = self.final_text(events)
        self.assertEqual(text, UNAVAILABLE + 'これは効く。')
        self.assertLess(elapsed, 3, f'took {elapsed:.1f} s')

    def test_checker_recovering_from_auth_errors_is_not_stopped(self):
        # Codex はログイン情報の読み直しとトークンの更新で立ち直ることがあり、それまでに 401 が 3 回まで出うる。
        self.restart_with_real_checker(
            'import sys, time\nsys.stdin.read()\n'
            f'for _ in range(3):\n    print({self.AUTH_ERROR_LINE!r}, file=sys.stderr, flush=True)\n'
            'time.sleep(0.3)\n'
            'print(\'{"replacements": [], "findings": []}\')\n')
        evs, item = message_events('msg_1', 'これは正しい。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(timeout=40)
        self.assertEqual(self.final_text(events), 'これは正しい。')

    def test_auth_error_lines_in_the_conversation_are_not_counted(self):
        # codex exec は渡された入力を標準エラーにそのまま書き出す (実測)。会話や草稿に 401 のログ行が
        # 並んでいても、ログインが有効な検査役は止めない。
        self.restart_with_real_checker(
            'import sys\nprompt = sys.stdin.read()\n'
            'print("user\\n" + prompt, file=sys.stderr, flush=True)\n'
            'import time\ntime.sleep(1)   # モデルの応答を待つ間\n'
            'print(\'{"replacements": [], "findings": []}\')\n')
        logs = '\n'.join([self.AUTH_ERROR_LINE] * 4)
        draft = f'ログを見ると認証で落ちてる。\n\n{logs}\n'
        evs, item = message_events('msg_1', draft)
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        body = {'model': 'm', 'stream': True, 'input': [
            {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': f'これを見て\n{logs}'}]}]}
        status, events = self.turn(body=body, timeout=40)
        self.assertEqual(self.final_text(events), draft)

    def test_injected_context_does_not_take_the_recent_conversation_slots(self):
        # Codex は AGENTS.md と環境の情報を利用者の発言の形で送る。これを除いてから直近の発言を数える。
        def message(role, text):
            kind = 'input_text' if role == 'user' else 'output_text'
            return {'type': 'message', 'role': role, 'content': [{'type': kind, 'text': text}]}
        items = [message('user', '# AGENTS.md instructions for C:/w\n\n<INSTRUCTIONS>\n規則\n</INSTRUCTIONS>'),
                 message('user', '<environment_context>\n  <cwd>C:/w</cwd>\n</environment_context>')]
        for n in range(6):
            items += [message('user', f'質問{n}'), message('assistant', f'回答{n}')]
        items.append(message('user', '<environment_context>\n  <cwd>C:/x</cwd>\n</environment_context>'))
        evs, item = message_events('msg_1', 'これは効く。')
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        self.turn(body={'model': 'm', 'stream': True, 'input': items})
        payload = self.checker_inputs()[-1]
        texts = [turn['text'] for turn in payload['recent_messages']]
        self.assertEqual(texts, [t for n in range(1, 6) for t in (f'質問{n}', f'回答{n}')])
        self.assertEqual(payload['latest_user'], '質問5')

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
        self.assertEqual(text, UNAVAILABLE + 'これは効く。')


    # ---- 未達の差し戻し・証拠・状態-----------------------------------------------------------
    def register(self, session='s1'):
        (self.state / 'continue').mkdir(parents=True, exist_ok=True)
        (self.state / 'continue' / session).write_text('', encoding='utf-8')

    def gate_state(self, session='s1', turn_id='t1'):
        path = self.state / 'gate' / session / f'{turn_id}.json'
        return json.loads(path.read_text(encoding='utf-8')) if path.exists() else None

    def write_gate_state(self, state, session='s1', turn_id='t1'):
        (self.state / 'gate' / session / f'{turn_id}.json').write_text(json.dumps(state), encoding='utf-8')

    def answer(self, text, turn_id='t1', body=None, session='s1', before=(), end=None, item_id='msg_f'):
        """最終回答 (before に呼び出しの項目を足せば途中の応答) を流させ、届いたイベントを返す。"""
        evs, item = message_events(item_id, text)
        script = [(0, e) for e in before] + [(0, e) for e in evs]
        output = [e['item'] for e in before if e['type'] == 'response.output_item.done'] + [item]
        script.append((0, end or completed(output)))
        Upstream.script = script
        status, events = self.turn(body=body or {'input': [self.user('元の依頼')]}, session=session,
                                   turn_id=turn_id)
        return events

    @staticmethod
    def call_events(call):
        return [{'type': 'response.output_item.added', 'output_index': 0, 'item': call},
                {'type': 'response.output_item.done', 'output_index': 0, 'item': call}]

    @staticmethod
    def exec_call(call_id, script='await exec("ls")'):
        return {'type': 'custom_tool_call', 'name': 'exec', 'call_id': call_id, 'input': script, 'status': 'completed'}

    @staticmethod
    def exec_output(call_id, text):
        return {'type': 'custom_tool_call_output', 'call_id': call_id, 'output': [{'type': 'input_text', 'text': text}]}

    @staticmethod
    def all_text(events):
        return json.dumps(events, ensure_ascii=False)

    def test_web_search_and_message_is_a_final_answer(self):
        search = {'id': 'ws_1', 'type': 'web_search_call', 'status': 'completed', 'action': {'query': 'q'}}
        self.answer('結果だよ', before=self.call_events(search))
        sent = self.checker_inputs()[-1]
        self.assertTrue(sent['final'])
        self.assertEqual(sent['origin'], 'codex')

    def test_tool_call_answer_is_not_final_and_becomes_shown_text(self):
        call = {'id': 'fc_1', 'type': 'function_call', 'name': 'shell', 'arguments': '{}', 'call_id': 'c1'}
        self.answer('先に見ておくね。これは効く。', before=self.call_events(call), item_id='msg_a')
        self.assertEqual(self.checker_inputs(), [])
        body = {'input': [self.user('元の依頼'), call, {'type': 'function_call_output', 'call_id': 'c1', 'output': 'ok'}]}
        self.answer('終わったよ', body=body)
        sent = self.checker_inputs()[-1]
        self.assertTrue(sent['final'])
        self.assertIn('先に見ておくね。これは効く。', sent['shown_text'])

    def test_findings_with_registration_send_the_notice(self):
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        events = self.answer('全部確認済みだよ')
        received = time.time()
        self.assertNotIn('全部確認済みだよ', self.all_text(events))
        notice = self.final_text(events)
        self.assertEqual(notice, '')
        self.assertFalse([e for e in events if e['type'] == 'response.completed'][0]['response']['end_turn'])
        state = self.gate_state()
        self.assertEqual(state['phase'], 'substituted')
        self.assertEqual(state['round'], 0)
        self.assertEqual(state['original'], '全部確認済みだよ')
        self.assertEqual(state['agent_message'], 'AGENT-MSG: 確かめて')
        done = [e for e in events if e['type'] == 'response.output_item.done'][-1]['item']
        self.assertEqual(done['id'], state['notice_marker'])
        self.assertLessEqual(state['created'], received)
        self.assertEqual(self.checker_inputs()[-1]['continuation'], 'withhold')

    def test_recovery_text_is_the_rewritten_answer_without_findings(self):
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        self.answer('全部確認済みで効く')
        state = self.gate_state()
        self.assertEqual(state['original'], '全部確認済みで効く')
        # 検査処理が返す表示用の本文 (display_text) をそのまま使う
        self.assertEqual(state['display'], '全部確認済みで速い')
        self.assertNotIn('unmet_text', state)

    def test_recovery_of_an_answer_with_an_evidence_gap_hides_the_findings(self):
        # 実物の検査処理で、Web 検索 (結果の本文を取得できない印) を含む回答を差し戻す。
        self.register()
        reply = json.dumps({'replacements': [], 'findings': [
            {'kind': 'unverified_claim', 'source': 'draft', 'excerpt': '全部確認済みだよ', 'evidence': [{'id': None, 'state': 'absent'}]}]})
        self.restart_with_real_checker('import sys\nsys.stdin.read()\nsys.exit(1)\n', fake_claude_source=(
            'import json, sys\nsys.stdin.read()\n'
            f'print(json.dumps({{"is_error": False, "stop_reason": "end_turn", "structured_output": json.loads({reply!r})}}))\n'))
        search = {'id': 'ws_1', 'type': 'web_search_call', 'status': 'completed', 'action': {'query': 'q'}}
        self.answer('全部確認済みだよ', before=self.call_events(search))
        display = self.gate_state()['display']
        self.assertTrue(display.startswith('全部確認済みだよ'), display)
        self.assertNotIn('出力ゲート', display)
        self.assertNotIn('出力ゲート: 証拠の一部を確認できませんでした', display)

    def test_engines_and_dropped_findings_are_recorded(self):
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        self.answer('全部確認済みだよ')
        state = self.gate_state()
        self.assertEqual(state['engine'], {'family': 'codex', 'model': 'm', 'effort': 'high'})
        self.assertEqual(state['engine_failures'], [{'family': 'claude', 'reason': 'claude failed first'}])
        self.assertEqual(state['dropped'], [{'finding': {}, 'reason': 'excerpt not in source'}])
        checked = [json.loads(line) for line in (self.state / 'relay.log').read_text(encoding='utf-8').splitlines()
                   if json.loads(line).get('event') == 'checked']
        self.assertEqual(checked[-1]['engine'], {'family': 'codex', 'model': 'm', 'effort': 'high'})
        self.assertEqual(checked[-1]['engine_failures'], [{'family': 'claude', 'reason': 'claude failed first'}])
        self.assertEqual(checked[-1]['dropped'], 1)
        self.assertEqual(checked[-1]['dropped_reasons'], ['excerpt not in source'])
        self.assertEqual(checked[-1]['statuses'], ['checked'])

    def test_intermediate_answer_is_logged_as_unchecked_by_design(self):
        call = {'id': 'fc_1', 'type': 'function_call', 'name': 'shell', 'arguments': '{}', 'call_id': 'c1'}
        self.answer('先に見るね', before=self.call_events(call), item_id='msg_a')
        checked = [json.loads(line) for line in (self.state / 'relay.log').read_text(encoding='utf-8').splitlines()
                   if json.loads(line).get('event') == 'checked']
        self.assertEqual(checked[-1]['statuses'], ['skipped'])

    def test_steer_findings_stay_in_later_requests_of_the_turn(self):
        notice = self.substituted()
        body = {'input': [self.user('元の依頼'), self.assistant(notice), self.user('ついでにこれも')]}
        call = {'id': 'fc_1', 'type': 'function_call', 'name': 'shell', 'arguments': '{}', 'call_id': 'c1'}
        self.answer('見てみる', body=body, before=self.call_events(call), item_id='msg_a')
        later = {'input': body['input'] + [call, {'type': 'function_call_output', 'call_id': 'c1', 'output': 'ok'}]}
        self.answer('追加分もやったよ', body=later)
        sent = json.loads(Upstream.requests[-1][2])
        texts = [input_text(i) for i in sent['input'] if i.get('type') == 'message']
        self.assertTrue(any('AGENT-MSG: 確かめて' in t for t in texts))
        self.assertEqual(self.checker_inputs()[-1]['round'], 1)

    def test_server_side_calls_of_the_same_response_are_evidence(self):
        search = {'id': 'ws_1', 'type': 'web_search_call', 'status': 'completed', 'action': {'query': 'codex hooks'}}
        self.answer('調べた結果だよ', before=self.call_events(search))
        evidence = self.checker_inputs()[-1]['evidence']
        self.assertEqual(evidence[0]['tool'], 'web_search_call')
        self.assertEqual(evidence[0]['input'], {'query': 'codex hooks'})
        self.assertTrue(evidence[1]['unavailable'])

    def test_client_tool_search_is_not_final(self):
        call = {'id': 'ts_1', 'type': 'tool_search_call', 'call_id': 'c1', 'execution': 'client', 'arguments': {}}
        self.answer('探すね', before=self.call_events(call), item_id='msg_a')
        self.assertEqual(self.checker_inputs(), [])

    def test_end_turn_false_is_not_final(self):
        evs, item = message_events('msg_e', '続けるね')
        end = completed([item])
        end['response']['end_turn'] = False
        self.answer('続けるね', end=end)
        self.assertEqual(self.checker_inputs(), [])

    def test_interrupted_incomplete_is_not_final(self):
        # Codex 0.164.0 のソース (rust-v0.164.0 のタグ) では reason が interrupted の打ち切りを end_turn=false の完了として扱い、同じターンを続ける。
        end = {'type': 'response.incomplete', 'response': {'id': 'r', 'status': 'incomplete',
                                                            'incomplete_details': {'reason': 'interrupted'}}}
        self.answer('途中まで', end=end)
        self.assertEqual(self.checker_inputs(), [])

    def test_findings_without_stop_registration_continue_silently(self):
        self.register('other-session')
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        events = self.answer('全部確認済みだよ')
        text = self.final_text(events)
        self.assertEqual(text, '')
        self.assertEqual(self.checker_inputs()[-1]['continuation'], 'withhold')
        self.assertEqual(self.gate_state()['phase'], 'substituted')

    def test_incomplete_content_filter_is_not_final(self):
        # Codex は content_filter の打ち切りだけ同じターンで要求し直し、届いた出力を残す (Codex のソース)。
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        end = {'type': 'response.incomplete', 'response': {'id': 'r', 'status': 'incomplete',
                                                            'incomplete_details': {'reason': 'content_filter'}}}
        events = self.answer('途中まで', end=end)
        self.assertEqual(self.checker_inputs(), [])
        self.assertNotIn('UNMET', self.all_text(events))
        (self.tmp / 'findings-on').unlink()
        self.answer('続きの回答')
        self.assertIn('途中まで', self.checker_inputs()[-1]['shown_text'])

    def test_incomplete_that_ends_the_turn_hides_the_findings(self):
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        end = {'type': 'response.incomplete', 'response': {'id': 'r', 'status': 'incomplete',
                                                            'incomplete_details': {'reason': 'max_output_tokens'}}}
        events = self.answer('全部確認済み', end=end)
        sent = self.checker_inputs()[-1]
        self.assertTrue(sent['final'])
        self.assertEqual(sent['continuation'], 'none')
        self.assertEqual(self.final_text(events), UNAVAILABLE + '全部確認済み')
        self.assertIsNone(self.gate_state())

    def test_missing_turn_identifier_hides_the_findings(self):
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        text = self.final_text(self.answer('全部確認済みだよ', turn_id=None))
        self.assertEqual(text, UNAVAILABLE + '全部確認済みだよ')

    def substituted(self):
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        self.answer('全部確認済みだよ')
        return self.gate_state()['notice_marker']

    def sent_back(self):
        """Stop hook が block したときと同じく、状態を blocked にして直させた回数を 1 つ増やす。"""
        state = self.gate_state()
        self.write_gate_state(dict(state, phase='blocked', round=state['round'] + 1))

    def upstream_texts(self):
        sent = json.loads(Upstream.requests[-1][2])
        return [input_text(i) for i in sent['input'] if i.get('type') == 'message']

    def test_continued_request_restores_the_original(self):
        notice = self.substituted()
        self.answer('確かめ直したよ', body={'input': [self.user('元の依頼'), self.assistant_notice(notice)]})
        texts = self.upstream_texts()
        self.assertIn('全部確認済みだよ', texts)
        self.assertNotIn(notice, texts)
        self.assertTrue(any('AGENT-MSG: 確かめて' in text for text in texts))
        sent = json.loads(Upstream.requests[-1][2])
        self.assertEqual([item['id'] for item in sent['input'] if item.get('role') == 'assistant'], ['msg_f'])
        payload = self.checker_inputs()[-1]
        self.assertEqual(payload['latest_user'], '元の依頼')
        self.assertEqual(payload['round'], 1)

    def test_compaction_preserves_pending_answer_and_findings(self):
        notice = self.substituted()
        compacted = {'id': 'cmp', 'type': 'compaction', 'encrypted_content': 'ENC-PENDING'}
        Upstream.script = [(0, {'type': 'response.output_item.done', 'output_index': 0, 'item': compacted}),
                           (0, completed([compacted]))]
        self.turn({'input': [self.user('元の依頼'), self.assistant_notice(notice)]},
                  kind='compaction', session='s1', turn_id='t1')
        sent = self.upstream_texts()
        self.assertIn('全部確認済みだよ', sent)
        self.assertTrue(any('AGENT-MSG: 確かめて' in text for text in sent))
        self.assertEqual((self.gate_state()['phase'], self.gate_state()['round']), ('substituted', 0))
        self.answer('確かめ直したよ', body={'input': [self.user('元の依頼'), compacted]})
        sent = self.upstream_texts()
        self.assertIn('全部確認済みだよ', sent)
        self.assertTrue(any('AGENT-MSG: 確かめて' in text for text in sent))
        self.assertEqual(self.checker_inputs()[-1]['round'], 1)

    def test_subagent_compaction_does_not_receive_parent_findings(self):
        notice = self.substituted()
        compacted = {'id': 'cmp', 'type': 'compaction', 'encrypted_content': 'ENC-CHILD'}
        Upstream.script = [(0, {'type': 'response.output_item.done', 'output_index': 0, 'item': compacted}),
                           (0, completed([compacted]))]
        self.turn({'input': [self.user('元の依頼'), self.assistant_notice(notice)]},
                  kind='compaction', session='s1', turn_id='t1', extra_headers={'x-openai-subagent': 'review'})
        sent = self.upstream_texts()
        self.assertNotIn('全部確認済みだよ', sent)
        self.assertFalse(any('AGENT-MSG: 確かめて' in text for text in sent))
        self.assertEqual((self.gate_state()['phase'], self.gate_state()['round']), ('substituted', 0))

    def test_steer_without_stop_hook_adds_the_findings_and_sends_back_again(self):
        notice = self.substituted()
        first = self.gate_state()
        body = {'input': [self.user('元の依頼'), self.assistant_notice(notice), self.user('ついでにこれも')]}
        events = self.answer('追加分も確認済み', body=body)
        texts = self.upstream_texts()
        self.assertIn('全部確認済みだよ', texts)
        self.assertTrue(any('AGENT-MSG: 確かめて' in t for t in texts))
        payload = self.checker_inputs()[-1]
        self.assertEqual(payload['round'], 1)
        self.assertEqual(payload['previous_findings'], first['findings'])
        # 未達が残る間は、直させた後の回答も案内にして直させ続ける
        state = self.gate_state()
        self.assertEqual(self.final_text(events), '')
        second = state['notice_marker']
        self.assertNotEqual(state['notice_marker'], first['notice_marker'])
        self.assertEqual((state['phase'], state['round'], state['original']), ('substituted', 1, '追加分も確認済み'))
        # 次の回でも、前の回の案内は原文に戻り、Codex の履歴に無い指摘は足し直す
        self.sent_back()
        hook = self.user('<hook_prompt hook_run_id="h2">AGENT-MSG: 確かめて</hook_prompt>')
        later = {'input': body['input'] + [self.assistant_notice(second), hook]}
        self.answer('直したよ', body=later)
        texts = self.upstream_texts()
        self.assertEqual(texts[:5], ['元の依頼', '全部確認済みだよ',
                                     '<hook_prompt hook_run_id="output-gate">AGENT-MSG: 確かめて</hook_prompt>',
                                     'ついでにこれも', '追加分も確認済み'])
        self.assertEqual(self.checker_inputs()[-1]['round'], 2)

    def test_retry_before_the_stop_hook_is_withheld_at_the_same_round(self):
        self.substituted()
        # 案内を流した後に接続が切れ、Codex が案内を履歴に入れずに同じ要求を送り直した: まだ直させていない
        events = self.answer('全部確認済みだよ')
        self.assertEqual(self.checker_inputs()[-1]['round'], 0)
        self.assertNotIn('previous_findings', self.checker_inputs()[-1])
        state = self.gate_state()
        self.assertEqual((state['phase'], state['round']), ('substituted', 0))
        self.assertEqual(self.final_text(events), '')
        self.assertEqual([e for e in events if e['type'] == 'response.output_item.done'][-1]['item']['id'],
                         state['notice_marker'])

    def test_progress_checkpoint_is_forwarded_after_a_repair(self):
        notice = self.substituted()
        checkpoint = self.gate_state().get('progress_state')
        self.assertIsNotNone(checkpoint)
        self.sent_back()
        self.answer('直し中だよ', body={'input': [self.user('元の依頼'), self.assistant_notice(notice)]})
        self.assertEqual(self.checker_inputs()[-1].get('progress_state'), checkpoint)

    def test_second_answer_resolves_from_blocked_and_drops_the_original(self):
        notice = self.substituted()
        self.sent_back()
        (self.tmp / 'findings-on').unlink()
        hook = self.user('<hook_prompt hook_run_id="h1">AGENT-MSG</hook_prompt>')
        events = self.answer('直したよ', body={'input': [self.user('元の依頼'), self.assistant_notice(notice), hook]})
        self.assertEqual(self.final_text(events), '直したよ')
        state = self.gate_state()
        self.assertEqual(state['phase'], 'resolved')
        self.assertEqual(state['round'], 1)
        self.assertNotIn('original', state)   # 原文はエージェントに届いた: 回収の対象から外す
        self.assertNotIn('agent_message', state)

    def test_failed_recheck_does_not_recover_the_old_answer(self):
        notice = self.substituted()
        self.restart_relay(check_fail='1')
        events = self.answer('確認し直したよ', body={'input': [self.user('元の依頼'), self.assistant_notice(notice)]})
        self.assertEqual(self.final_text(events), UNAVAILABLE + '確認し直したよ')
        state = self.gate_state()
        self.assertEqual(state['phase'], 'resolved')
        self.assertNotIn('original', state)
        self.assertNotIn('agent_message', state)

    def test_every_answer_with_findings_is_sent_back_until_none_remain(self):
        items = [self.user('元の依頼')]
        notice = self.substituted()
        for number, draft in enumerate(['まだ確認済み', 'やっぱり確認済み'], 1):
            self.sent_back()
            items += [self.assistant_notice(notice), self.user(f'<hook_prompt hook_run_id="h{number}">AGENT-MSG</hook_prompt>')]
            previous = self.gate_state()['findings']
            events = self.answer(draft, body={'input': list(items)})
            payload = self.checker_inputs()[-1]
            self.assertEqual(payload['round'], number)
            self.assertEqual(payload['previous_findings'], previous)
            state = self.gate_state()
            self.assertEqual(self.final_text(events), '')
            notice = state['notice_marker']
            self.assertEqual((state['phase'], state['round'], state['original']), ('substituted', number, draft))
        self.sent_back()
        (self.tmp / 'findings-on').unlink()
        items += [self.assistant_notice(notice), self.user('<hook_prompt hook_run_id="h3">AGENT-MSG</hook_prompt>')]
        events = self.answer('全部直したよ', body={'input': items})
        self.assertEqual(self.final_text(events), '全部直したよ')
        self.assertEqual(self.checker_inputs()[-1]['round'], 3)
        # どの回の案内も、モデルへ送る前に原文へ戻す
        answers = [t for t in self.upstream_texts() if not t.startswith(('元の依頼', '<hook_prompt'))]
        self.assertEqual(answers, ['全部確認済みだよ', 'まだ確認済み', 'やっぱり確認済み'])
        self.assertEqual((self.gate_state()['phase'], self.gate_state()['round']), ('resolved', 3))

    def test_recheck_through_relay_checker_and_stop_hook(self):
        low = {'replacements': [], 'findings': [{'kind': 'unverified_claim', 'rule': '', 'source': 'draft',
                'excerpt': '全部確認済みだよ', 'evidence': [{'id': None, 'state': 'absent'}]}]}
        high = {'replacements': [], 'findings': []}
        self.restart_with_real_checker('import json,sys\nsys.stdin.read()\n'
            f'print(json.dumps({high!r} if "gpt-6-astra" in sys.argv else {low!r}))\n')
        self.register()
        xdg = Path(tempfile.mkdtemp())
        root = xdg / 'output-gate'
        root.mkdir()
        (root / 'codex.json').write_text('{"enabled": true}')
        (root / 'relay').symlink_to(self.state, target_is_directory=True)
        hook = Path(RELAY).parent.parent / 'hooks/output-gate-codex.sh'
        items = [self.user('元の依頼')]
        self.answer('全部確認済みだよ')
        notice = self.gate_state()['notice_marker']
        for number in range(1, 4):
            stopped = subprocess.run(['bash', str(hook), 'stop'], input='{"session_id":"s1","turn_id":"t1"}',
                                     text=True, capture_output=True, env=dict(os.environ, XDG_STATE_HOME=str(xdg)), check=True)
            self.assertEqual(json.loads(stopped.stdout)['decision'], 'block')
            items += [self.assistant_notice(notice), self.user(f'<hook_prompt hook_run_id="h{number}">再確認</hook_prompt>')]
            events = self.answer('全部確認済みだよ', body={'input': list(items)})
            self.assertEqual(self.upstream_texts().count('全部確認済みだよ'), number)
            if number < 3:
                self.assertEqual(self.final_text(events), '')
            notice = self.gate_state().get('notice_marker')
        self.assertEqual(self.final_text(events), '全部確認済みだよ')
        state = self.gate_state()
        self.assertEqual(state['phase'], 'resolved')
        self.assertEqual(state['engine']['model'], 'gpt-6-astra')

    def test_new_tool_evidence_is_sent_to_the_checker(self):
        items = [self.user('元の依頼')]
        notice = self.substituted()
        self.sent_back()
        items += [self.assistant_notice(notice), self.user('<hook_prompt hook_run_id="h1">AGENT-MSG</hook_prompt>')]
        self.answer('まだ確認済み', body={'input': list(items)})
        notice = self.gate_state()['notice_marker']
        self.sent_back()
        call = {'type': 'function_call', 'name': 'shell', 'arguments': '{}', 'call_id': 'new-call'}
        items += [self.assistant_notice(notice), self.user('<hook_prompt hook_run_id="h2">AGENT-MSG</hook_prompt>'),
                  call, {'type': 'function_call_output', 'call_id': 'new-call', 'output': 'new evidence'}]
        events = self.answer('もう一度確認済み', body={'input': items})
        text = self.final_text(events)
        self.assertNotIn('UNMET-ITEM', text)
        self.assertEqual(self.gate_state()['phase'], 'substituted')
        self.assertTrue(any(item.get('output') == 'new evidence' for item in self.checker_inputs()[-1]['evidence']))

    def stalled_answers(self, fail_high=False, advancing=False):
        reply = {'replacements': [], 'findings': [{'kind': 'unverified_claim', 'rule': '', 'source': 'draft',
                 'excerpt': '全部確認済みだよ', 'evidence': [{'id': None, 'state': 'absent'}]}],
                 'progress': {'state': 'advanced' if advancing else 'stalled', 'reason': 'comparison'}}
        source = 'import json,sys\nsys.stdin.read()\n'
        if fail_high:
            source += 'if "gpt-6-astra" in sys.argv: sys.exit(1)\n'
        source += f'print(json.dumps({reply!r}))\n'
        self.restart_with_real_checker(source)
        self.register()
        items = [self.user('元の依頼')]
        events = self.answer('全部確認済みだよ')
        for number in range(1, 6 if advancing else 4):
            notice = self.gate_state()['notice_marker']
            items += [self.assistant_notice(notice), self.user(f'<hook_prompt hook_run_id="h{number}">再確認</hook_prompt>')]
            events = self.answer('全部確認済みだよ', body={'input': list(items)})
        return self.final_text(events)

    def test_stalled_recheck_stops_and_preserves_unmet_findings(self):
        text = self.stalled_answers()
        self.assertIn('自動差戻し停止・未解決', text)
        self.assertIn('全部確認済みだよ', text)
        self.assertIn('次の点は確かめられていません', text)
        state = self.gate_state()
        self.assertEqual(state['phase'], 'stopped')
        self.assertEqual(state['progress_state']['stalled'], 3)
        self.assertTrue(state['findings'])
        self.assertNotIn('agent_message', state)

    def test_failed_independent_recheck_stops_with_the_initial_finding(self):
        text = self.stalled_answers(fail_high=True)
        self.assertIn('再判定不能で自動差戻し停止・未解決', text)
        self.assertIn('全部確認済みだよ', text)
        self.assertTrue(self.gate_state()['findings'])
        self.assertEqual(self.gate_state()['phase'], 'stopped')

    def test_advancing_repairs_are_not_capped_by_the_total_rounds(self):
        self.assertEqual(self.stalled_answers(advancing=True), '')
        self.assertEqual(self.gate_state()['round'], 5)
        self.assertEqual(self.gate_state()['progress_state']['stalled'], 0)
        self.assertEqual(self.gate_state()['phase'], 'substituted')

    def test_new_turn_has_no_previous_progress_checkpoint(self):
        self.substituted()
        self.answer('別の依頼への回答', turn_id='t2', body={'input': [self.user('新しい依頼')]})
        self.assertEqual(self.checker_inputs()[-1]['round'], 0)
        self.assertNotIn('progress_state', self.checker_inputs()[-1])

    def test_unwritable_state_falls_back_to_the_original(self):
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        (self.state / 'gate').write_text('not a directory', encoding='utf-8')
        text = self.final_text(self.answer('全部確認済みだよ'))
        self.assertIn('全部確認済みだよ', text)
        self.assertIn('UNMET-ITEM', text)
        self.assertIn('保存できなかった', text)

    def test_evidence_is_saved_in_order_with_failures_and_truncation(self):
        out1 = 'Script failed\nExit code: 3\nboom'
        out2 = 'Warning: truncated output (original token count: 99)\nok'
        items = [self.user('元の依頼'), self.exec_call('c1', 'await exec("make test")'), self.exec_output('c1', out1),
                 self.exec_call('c2', 'await exec("make test")'), self.exec_output('c2', out2)]
        self.answer('直して通ったよ', body={'input': items})
        evidence = self.checker_inputs()[-1]['evidence']
        self.assertEqual([e['output'] for e in evidence], [out1, out2])
        self.assertTrue(evidence[0]['failed'])
        self.assertEqual(evidence[0]['exit_code'], 3)
        self.assertFalse(evidence[1].get('failed'))
        self.assertIn('make test', evidence[0]['input'])

    def test_previous_turn_calls_go_to_previous_evidence(self):
        old = [self.user('前の依頼'), self.exec_call('c0', 'await exec("old")'), self.exec_output('c0', 'old-out'),
               self.assistant('前の回答')]
        items = old + [self.user('元の依頼'), self.exec_call('c1'), self.exec_output('c1', 'new-out')]
        self.answer('やったよ', body={'input': items}, turn_id='t2')   # 状態ディレクトリは空
        sent = self.checker_inputs()[-1]
        self.assertEqual([e['output'] for e in sent['evidence']], ['new-out'])
        previous = sent['previous_evidence']
        self.assertEqual([i['output'] for t in previous for i in t['items']], ['old-out'])
        self.assertEqual(previous[0]['turn_id'], '前のターン (区別不明)')
        ids = [e['id'] for e in sent['evidence']] + [i['id'] for t in previous for i in t['items']]
        self.assertEqual(len(ids), len(set(ids)))

    def test_saved_previous_turn_is_used(self):
        items = [self.user('前の依頼'), self.exec_call('c0'), self.exec_output('c0', 'old-out')]
        self.answer('前の回答', body={'input': items}, turn_id='t1')
        items += [self.assistant('前の回答'), self.user('元の依頼')]
        self.answer('前のターンで通ってたよ', body={'input': items}, turn_id='t2')
        sent = self.checker_inputs()[-1]
        self.assertEqual(sent['evidence'], [])
        self.assertEqual(sent['previous_evidence'][0]['turn_id'], 't1')
        self.assertEqual([i['output'] for i in sent['previous_evidence'][0]['items']], ['old-out'])

    def test_turn_start_context_keeps_the_original_request(self):
        start = [self.user('元の依頼: A と B を直して'), self.assistant('計画: A を直して B を直す'), self.user('じゃあ進めて')]
        self.answer('途中', body={'input': start}, before=self.call_events(self.exec_call('c0')), item_id='msg_0')
        items = list(start)
        for n in range(12):
            items += [dict(self.assistant(f'途中報告{n}'), phase='commentary'), self.exec_call(f'c{n}'),
                      self.exec_output(f'c{n}', f'out{n}')]
        for _ in range(2):   # 最終回答の検査と、差し戻した後の再検査
            self.answer('全部終わった', body={'input': items})
            sent = self.checker_inputs()[-1]
            texts = [m['text'] for m in sent['turn_start_context']]
            self.assertIn('元の依頼: A と B を直して', texts)
            self.assertIn('計画: A を直して B を直す', texts)
            self.assertEqual(sent['latest_user'], 'じゃあ進めて')

    def test_compaction_keeps_the_saved_evidence(self):
        items = [self.user('元の依頼'), self.exec_call('c1', 'await exec("make test")'), self.exec_output('c1', 'passed')]
        self.answer('途中', body={'input': items}, before=self.call_events(self.exec_call('c2')), item_id='msg_0')
        self.compact(items + [self.assistant('途中')], 'ENC-T')
        compacted = [self.user('元の依頼'), {'type': 'compaction', 'encrypted_content': 'ENC-T'}]
        self.answer('テスト通ったよ', body={'input': compacted})
        sent = self.checker_inputs()[-1]
        self.assertEqual([e['output'] for e in sent['evidence']], ['passed'])
        self.assertFalse([e for e in sent['evidence'] if e.get('unavailable')])

    def test_compaction_without_saved_evidence_is_marked(self):
        compacted = [self.user('元の依頼'), {'type': 'compaction', 'encrypted_content': 'ENC-U'}]
        self.answer('テスト通ったよ', body={'input': compacted})
        evidence = self.checker_inputs()[-1]['evidence']
        self.assertTrue(evidence and evidence[0].get('unavailable'))

    def test_two_body_elements_are_checked_once(self):
        texts = ['前半は効く。', '後半も効く。']
        item = {'id': 'msg_m', 'type': 'message', 'role': 'assistant', 'status': 'completed',
                'content': [{'type': 'output_text', 'text': t, 'annotations': []} for t in texts]}
        Upstream.script = [(0, {'type': 'response.output_item.done', 'output_index': 0, 'item': item}),
                           (0, completed([item]))]
        status, events = self.turn(turn_id='t1')
        inputs = self.checker_inputs()
        self.assertEqual(len(inputs), 1)
        self.assertEqual(inputs[0]['bodies'], texts)
        self.assertNotIn('効く', self.all_text(events))

    def test_review_is_not_final_and_keeps_no_round(self):
        self.register()
        (self.tmp / 'findings-on').write_text('', encoding='utf-8')
        evs, item = message_events('msg_r', self.review_text())
        Upstream.script = [(0, e) for e in evs] + [(0, completed([item]))]
        status, events = self.turn(extra_headers={'x-openai-subagent': 'review'}, turn_id='t1')
        self.assertFalse(self.checker_inputs()[-1]['final'])
        self.assertEqual(json.loads(self.final_text(events))['overall_explanation'], '速い説明')
        self.assertIsNone(self.gate_state())

    def test_old_states_are_swept(self):
        old = time.time() - 25 * 3600
        gate = self.state / 'gate' / 's9'
        gate.mkdir(parents=True)
        (gate / 'old.json').write_text(json.dumps({'phase': 'resolved', 'round': 1, 'created': old}), encoding='utf-8')
        (gate / 'unread.json').write_text(json.dumps({'phase': 'substituted', 'round': 0, 'created': old,
                                                      'original': 'x'}), encoding='utf-8')
        turns = self.state / 'turns' / 's1'
        turns.mkdir(parents=True)
        (turns / 'stale.json').write_text(json.dumps({'turn_id': 'stale', 'time': old, 'records': []}), encoding='utf-8')
        for n in range(12):
            (turns / f'k{n}.json').write_text(json.dumps({'turn_id': f'k{n}', 'time': time.time() - 100 + n,
                                                          'records': []}), encoding='utf-8')
        self.answer('やったよ', turn_id='t-new')
        self.assertFalse((gate / 'old.json').exists())
        self.assertFalse((gate / 'unread.json').exists())
        self.assertFalse((turns / 'stale.json').exists())
        left = sorted(p.stem for p in turns.glob('*.json'))
        self.assertEqual(len(left), 10)
        self.assertNotIn('k0', left)
        self.assertIn('t-new', left)

    def test_secrets_in_evidence_and_shown_text_are_masked(self):
        secret = 'fake-' + os.urandom(8).hex()
        prompt_file = self.tmp / 'claude-prompt.txt'
        self.restart_with_real_checker(
            'import sys\nsys.stdin.read()\nsys.exit(1)\n',
            fake_claude_source=('import json, sys\n'
                                f'open({str(prompt_file)!r}, "a", encoding="utf-8").write(sys.stdin.read())\n'
                                'print(json.dumps({"is_error": False, "stop_reason": "end_turn", '
                                '"structured_output": {"replacements": [], "findings": []}}))\n'),
            secrets=[secret])
        call = {'id': 'fc_1', 'type': 'function_call', 'name': 'shell', 'arguments': '{}', 'call_id': 'c1'}
        self.answer(f'見るね {secret}', before=self.call_events(call), item_id='msg_a')
        items = [self.user('元の依頼'), call,
                 {'type': 'function_call_output', 'call_id': 'c1', 'output': f'token={secret}'}]
        self.answer('終わったよ', body={'input': items})
        prompt = prompt_file.read_text(encoding='utf-8')
        self.assertIn('token=', prompt)
        self.assertNotIn(secret, prompt)

    def test_self_test_covers_the_notice_and_restore(self):
        # 自己試験の偽の検査処理が未達を返し、案内への差し替えと、続けた要求での原文への戻しを通す。
        result = subprocess.run([sys.executable, '-I', str(RELAY), '--port', '0', '--state-dir', str(self.state),
                                 '--self-test'], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('notice', result.stdout)


class RunJudgeTests(unittest.TestCase):
    RUN_JUDGE = REPO / 'agent-shared/hooks/lib/run-judge.py'

    def test_deadline_holds_after_the_judge_closes_its_output(self):
        # 標準出力を先に閉じて動き続ける検査役でも、締切で止めて 124 を返す。
        work = tempfile.mkdtemp()
        started = time.time()
        result = subprocess.run([sys.executable, '-I', str(self.RUN_JUDGE), '0.2', work, sys.executable, '-I', '-c',
                                 'import os, time; os.close(1); time.sleep(3)'],
                                input=b'', capture_output=True, timeout=30)
        elapsed = time.time() - started
        self.assertEqual(result.returncode, 124)
        self.assertLess(elapsed, 2, f'took {elapsed:.1f} s')


if __name__ == '__main__':
    unittest.main()
