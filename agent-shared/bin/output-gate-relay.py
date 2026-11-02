#!/usr/bin/env python3
"""出力ゲートの Codex 用の中継: Codex のモデル API の要求を受けて上流へ送り、回答を検査してから返す。

  output-gate-relay.py --port N --state-dir DIR [--upstream URL]   中継として待ち受ける
  output-gate-relay.py --port N --state-dir DIR --ensure           動いていなければ切り離して起動し、
                                                                   古い版が動いていれば入れ替える
  output-gate-relay.py --port 0 --state-dir DIR --self-test        手元だけで終わる自己試験

入れ替え: 動いている中継の版がこのファイルと違えば、まずこのファイルで自己試験をする。通らなければ
古い版のまま動かし続ける。通れば古い版に終了を頼む。処理中の要求がある間は古い版が断るので、その回は
入れ替えず次の hook に任せる。古い版が終わってから新しい版を起動する。その間の要求は Codex の再試行で吸収する。

Codex は組み込みの openai provider の openai_base_url をこの中継 (http://127.0.0.1:N/backend-api/codex)
に向けて使う。中継は利用者が読む回答の項目 (message) を応答の終わりまで止め、共通の検査処理
(output-gate-check.py) に渡し、訂正した文字列でイベントを組み直して流す。止めている間は
response.in_progress を流し、Codex が待ち時間切れで切断しないようにする。

守ること:
- 127.0.0.1 だけで待ち受ける。ヘッダーと本文はログに残さない (記録は種類と時刻だけ)。
- WebSocket への切り替えは全ての経路で 426 で断り、Upgrade を上流へ送らない。差分送信では
  サーバーが保存した訂正前の原文が次の要求の文脈になるため。
- 回答の項目の暗号化された出力 (encrypted_content) は、要求と応答の両方から取り除く。
- 上流の失敗や切断は、そのまま Codex に伝える (Codex 本来の再試行に任せる)。

状態ディレクトリ:
  delegated/<session_id>  委譲の子セッションの登録 (hook が書く)。24 時間以内のものは検査せずに流す。
  compaction.json         サーバー側の compaction の項目 (暗号化データの SHA-256) と、その時点の直近の回答の組。
                          compaction の後は要求本文から前の回答が消えるため、検査役へはここから渡す。
  relay.log               種類・判定・時刻の記録。
"""
import argparse
import concurrent.futures
import gzip
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import queue
import re
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

try:
    from compression import zstd
    DECODE_ERRORS = (ValueError, OSError, EOFError, zstd.ZstdError)
except ImportError:  # Python 3.14 より前
    zstd = None
    DECODE_ERRORS = (ValueError, OSError, EOFError)

SCRIPT = Path(__file__).resolve()
VERSION = hashlib.sha256(SCRIPT.read_bytes()).hexdigest()[:12]
PREFIX = '/backend-api/codex'
DEFAULT_UPSTREAM = 'https://chatgpt.com/backend-api/codex'
HOP = {'host', 'connection', 'keep-alive', 'proxy-connection', 'proxy-authorization', 'proxy-authenticate',
       'te', 'trailer', 'trailers', 'transfer-encoding', 'upgrade', 'content-length', 'content-encoding',
       'accept-encoding'}
PASS_KINDS = {'compaction', 'memory', 'prewarm'}
KEEPALIVE = b'event: response.in_progress\ndata: {"type":"response.in_progress","response":{}}\n\n'
UNCHECKED_PREFIX = '[出力ゲート: 検査できませんでした — {}]\n\n'
RECENT_MESSAGES = 10
# Codex が会話の先頭などに利用者の発言として入れる文脈 (AGENTS.md と環境の情報) の書き出し。
INJECTED_CONTEXT = ('# AGENTS.md instructions', '<environment_context>')
COMPACTION_TYPES = {'compaction', 'context_compaction'}
KEEP_ANSWERS = 3
# compaction の組に残す回答の phase。途中経過 (commentary) と回答の断片 (partial_answer) は残さない。
# phase の無い項目は、phase を送らない版の最終回答として残す。
FINAL_PHASES = (None, 'final_answer')
STORE_LIMIT = 1000
DELEGATED_TTL = 24 * 3600
REVIEW_MARK = '\n<<<OUTPUT-GATE-FIELD-{}>>>\n'
# 切り離して起動する中継に渡す環境変数。中継は複数のセッションが共有して長く動くため、起動した
# セッション固有の値 (委譲の印、OUTPUT_GATE_* の上書き、API キー) を持ち込まない。検査役 (codex と
# gitleaks) の起動・ログイン情報の場所・通信に要るものだけを渡す。
RELAY_ENV = {'PATH', 'PATHEXT', 'HOME', 'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH', 'SYSTEMROOT', 'SYSTEMDRIVE',
             'WINDIR', 'COMSPEC', 'TEMP', 'TMP', 'TMPDIR', 'APPDATA', 'LOCALAPPDATA', 'PROGRAMDATA',
             'PROGRAMFILES', 'LANG', 'LC_ALL', 'LC_CTYPE', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
             'XDG_RUNTIME_DIR', 'CODEX_HOME', 'SSL_CERT_FILE', 'SSL_CERT_DIR', 'HTTP_PROXY', 'HTTPS_PROXY',
             'ALL_PROXY', 'NO_PROXY'}


class Settings:
    upstream = urllib.parse.urlsplit(DEFAULT_UPSTREAM)
    state_dir = Path('.')
    keepalive = float(os.environ.get('OUTPUT_GATE_KEEPALIVE') or 5)
    upstream_idle = float(os.environ.get('OUTPUT_GATE_UPSTREAM_IDLE') or 300)
    check_cmd = json.loads(os.environ['OUTPUT_GATE_CHECK_CMD']) if os.environ.get('OUTPUT_GATE_CHECK_CMD') \
        else [sys.executable, '-I', str(SCRIPT.parent / 'output-gate-check.py')]
    log_lock = threading.Lock()
    store_lock = threading.Lock()
    active_lock = threading.Lock()
    active = 0
    closing = False
    server = None


def log(**fields):
    """種類・判定・時刻だけを記録する。本文とヘッダーは書かない。"""
    fields['t'] = round(time.time(), 3)
    try:
        with Settings.log_lock, open(Settings.state_dir / 'relay.log', 'a', encoding='utf-8') as f:
            f.write(json.dumps(fields, ensure_ascii=False) + '\n')
    except OSError:
        pass


def parse_event(lines):
    etype, data = None, []
    for line in lines:
        if line.startswith('event:'):
            etype = line[6:].strip()
        elif line.startswith('data:'):
            data.append(line[5:].lstrip(' '))
    obj = None
    if data:
        try:
            obj = json.loads('\n'.join(data))
        except ValueError:
            obj = None
    if etype is None and isinstance(obj, dict):
        etype = obj.get('type')
    return etype, obj


def encode_event(etype, obj):
    head = f'event: {etype}\n' if etype else ''
    return (head + 'data: ' + json.dumps(obj, ensure_ascii=False, separators=(',', ':')) + '\n\n').encode('utf-8')


def strip_message_ciphertext(item):
    """回答の項目から暗号化された出力を取り除く。取り除いたら True。"""
    if isinstance(item, dict) and item.get('type') == 'message' and 'encrypted_content' in item:
        del item['encrypted_content']
        return True
    return False


def text_parts(item):
    """回答の項目の本文パートを (content の位置, パート) の並びで返す。位置はイベントの content_index と同じ。"""
    return [(index, part) for index, part in enumerate(item.get('content') or [])
            if isinstance(part, dict) and part.get('type') == 'output_text']


def input_text(item):
    return ''.join(p.get('text') or '' for p in item.get('content') or []
                   if p.get('type') in ('input_text', 'output_text', 'text'))


def compaction_key(item):
    enc = item.get('encrypted_content') if isinstance(item, dict) else None
    return hashlib.sha256(enc.encode('utf-8')).hexdigest() if isinstance(enc, str) and enc else None


def load_store():
    try:
        store = json.loads((Settings.state_dir / 'compaction.json').read_text(encoding='utf-8'))
        return store if isinstance(store, dict) else {}
    except (OSError, ValueError):
        return {}


def split_at_compaction(items):
    """要求本文の項目を、最後の compaction の項目と、それより後の項目に分ける。"""
    last = None
    for index, item in enumerate(items):
        if isinstance(item, dict) and item.get('type') in COMPACTION_TYPES:
            last = index
    if last is None:
        return None, items
    return items[last], items[last + 1:]


def stored_answers(compaction_item):
    """compaction の項目に結び付けた回答。組が無ければ None。"""
    key = compaction_key(compaction_item)
    if key is None:
        return None
    with Settings.store_lock:
        store = load_store()
        entry = store.get(key)
        if not isinstance(entry, dict):
            return None
        entry['used'] = time.time()
        try:
            save_store(store)
        except OSError:
            pass
    return list(entry.get('answers') or [])


def save_store(store):
    if len(store) > STORE_LIMIT:
        for key in sorted(store, key=lambda k: store[k].get('used', 0))[:len(store) - STORE_LIMIT]:
            del store[key]
    path = Settings.state_dir / 'compaction.json'
    tmp = path.with_name(f'.compaction.{os.getpid()}.{threading.get_ident()}.tmp')
    tmp.write_text(json.dumps(store, ensure_ascii=False), encoding='utf-8')
    os.replace(tmp, path)


def remember_compaction(body, output_items):
    """compaction の応答の項目と、その要求本文の直近の回答を組にして保存する。失敗は OSError。"""
    compaction_item, rest = split_at_compaction(body.get('input') or [])
    answers = (stored_answers(compaction_item) or []) if compaction_item else []
    answers += [input_text(i) for i in rest if isinstance(i, dict) and i.get('type') == 'message'
                and i.get('role') == 'assistant' and i.get('phase') in FINAL_PHASES]
    answers = answers[-KEEP_ANSWERS:]
    with Settings.store_lock:
        store = load_store()
        for item in output_items:
            if isinstance(item, dict) and item.get('type') in COMPACTION_TYPES and compaction_key(item):
                store[compaction_key(item)] = {'answers': answers, 'used': time.time()}
        save_store(store)


def checker_payload(body, draft):
    items = body.get('input') or []
    compaction_item, rest = split_at_compaction(items)
    after = len(items) - len(rest)
    # 利用者の発言は compaction より前にも保持されて届く。回答は compaction より前の分を保存済みの組から取る。
    # Codex が利用者の発言の形で送る AGENTS.md と環境の情報は、会話ではないので数える前に除く。
    messages = [i for n, i in enumerate(items) if isinstance(i, dict) and i.get('type') == 'message'
                and ((i.get('role') == 'user' and not input_text(i).startswith(INJECTED_CONTEXT))
                     or (i.get('role') == 'assistant' and n >= after))]
    users = [m for m in messages if m.get('role') == 'user']
    conversation = [{'role': m['role'], 'text': input_text(m)} for m in messages[-RECENT_MESSAGES:]]
    compacted_note = False
    if compaction_item is not None:
        answers = stored_answers(compaction_item)
        if answers is None:
            compacted_note = True
            log(event='compaction-pair-missing')
        else:
            conversation = [{'role': 'assistant', 'text': a} for a in answers] + conversation
    programs = body.get('access_programs') or {}
    return {'cli': 'codex', 'latest_user': input_text(users[-1]) if users else '',
            'conversation': conversation, 'draft': draft,
            'cyber_program': programs.get('cyber') if isinstance(programs, dict) else None,
            'compacted_note': compacted_note}


def kill_tree(proc):
    """検査処理のプロセスを子孫ごと止める (Windows の codex の shim は孫を起動するため)。"""
    try:
        if os.name == 'nt':
            subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=10)
        else:
            # まず TERM を送る。検査処理の下の run-judge.py は検査役を別のプロセスグループで起動しているため、
            # TERM を受けた run-judge.py がそのグループを止める。止まらなければ KILL する。
            os.killpg(proc.pid, signal.SIGTERM)
            deadline = time.time() + 2
            while time.time() < deadline:
                proc.poll()   # 回収しないと、終了した検査処理がグループに残って待ち続ける
                try:
                    os.killpg(proc.pid, 0)
                except ProcessLookupError:
                    return
                time.sleep(0.05)
            os.killpg(proc.pid, signal.SIGKILL)
    except (OSError, subprocess.SubprocessError):
        pass


class Checks:
    """1 つの要求で起動した検査処理を持ち、Codex が切断したら止める。"""

    def __init__(self):
        self.lock = threading.Lock()
        self.procs = []
        self.cancelled = False

    def run(self, payload):
        with self.lock:
            if self.cancelled:
                raise OSError('the request was cancelled')
            proc = subprocess.Popen(Settings.check_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL, start_new_session=os.name != 'nt')
            self.procs.append(proc)
        try:
            out, _ = proc.communicate(json.dumps(payload, ensure_ascii=False).encode('utf-8'), timeout=300)
        except subprocess.TimeoutExpired:
            kill_tree(proc)
            raise
        if proc.returncode != 0:
            raise OSError(f'exit code {proc.returncode}')
        return out

    def cancel(self):
        with self.lock:
            self.cancelled = True
            procs = list(self.procs)
        for proc in procs:
            if proc.poll() is None:
                kill_tree(proc)


def run_check(payload, checks):
    try:
        out = json.loads(checks.run(payload).decode('utf-8'))
        if not isinstance(out, dict) or not isinstance(out.get('text'), str) or \
                out.get('status') not in ('checked', 'unchecked') or \
                (out['status'] == 'unchecked' and not (isinstance(out.get('reason'), str) and out['reason'].strip())):
            raise ValueError('unexpected result')
        return out
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        reason = f'検査処理を実行できなかった ({type(error).__name__})'
        return {'status': 'unchecked', 'text': UNCHECKED_PREFIX.format(reason) + payload['draft'], 'reason': reason}


def check_text(body, draft, checks):
    result = run_check(checker_payload(body, draft), checks)
    return result['text'], result.get('status')


def review_json(draft):
    """Codex と同じく、全体か、最初の { から最後の } までを /review の JSON として読む。
    読めたら (JSON, 開始位置, 終了位置)、読めなければ None。"""
    for start, end in ((0, len(draft)), (draft.find('{'), draft.rfind('}') + 1)):
        if 0 <= start < end:
            try:
                review = json.loads(draft[start:end])
            except ValueError:
                continue
            if is_review(review):
                return review, start, end
    return None


def is_review(value):
    """Codex の ReviewOutputEvent として読める形か。読めない JSON を、Codex は説明文として全文表示する。"""
    def number(v):
        return isinstance(v, (int, float)) and not isinstance(v, bool)

    def integer(v, low, high):   # Codex の i32 / u32 に収まる整数
        return isinstance(v, int) and not isinstance(v, bool) and low <= v <= high

    def finding(f):
        if not isinstance(f, dict):
            return False
        location = f.get('code_location')
        lines = location.get('line_range') if isinstance(location, dict) else None
        return (isinstance(f.get('title'), str) and isinstance(f.get('body'), str)
                and number(f.get('confidence_score')) and integer(f.get('priority'), -2 ** 31, 2 ** 31 - 1)
                and isinstance(location, dict) and isinstance(location.get('absolute_file_path'), str)
                and isinstance(lines, dict) and integer(lines.get('start'), 0, 2 ** 32 - 1)
                and integer(lines.get('end'), 0, 2 ** 32 - 1))

    return (isinstance(value, dict) and isinstance(value.get('findings'), list)
            and all(finding(f) for f in value['findings'])
            and isinstance(value.get('overall_correctness'), str)
            and isinstance(value.get('overall_explanation'), str)
            and number(value.get('overall_confidence_score')))


def check_review(body, draft, checks):
    """/review の JSON は、説明の欄 (overall_explanation、各指摘の title と body) だけを検査する。"""
    found = review_json(draft)
    if found is None:
        return check_text(body, draft, checks)   # JSON でなければ Codex も説明文として扱う
    review, start, end = found
    slots = [(review, 'overall_explanation')] + [(f, key) for f in review['findings'] for key in ('title', 'body')]
    joined = ''.join(REVIEW_MARK.format(n) + obj[key] for n, (obj, key) in enumerate(slots))
    result = run_check(checker_payload(body, joined), checks)
    status = 'checked'
    if result.get('status') == 'checked':
        pieces = result['text'].split('\n<<<OUTPUT-GATE-FIELD-')
        values = [piece.split('>>>\n', 1)[1] if '>>>\n' in piece else None for piece in pieces[1:]]
        if len(values) == len(slots) and None not in values and pieces[0] == '':
            for (obj, key), value in zip(slots, values):
                obj[key] = value
        else:
            result, status = {'reason': '検査役が説明の欄の区切りを変えた'}, 'unchecked'
    else:
        status = 'unchecked'
    if status == 'unchecked':
        review['overall_explanation'] = UNCHECKED_PREFIX.format(result.get('reason') or '検査できなかった') + \
            (review.get('overall_explanation') or '')
    # JSON の外側の文字列は Codex が捨てるので、そのまま残す
    return draft[:start] + json.dumps(review, ensure_ascii=False) + draft[end:], status


TEXT_EVENT_PREFIXES = ('response.output_text.', 'response.content_part.', 'response.refusal.')


def message_key(etype, obj):
    """回答の項目 (message) に関わるイベントなら、その項目の識別子 (id か出力位置) を返す。"""
    if not isinstance(obj, dict) or not etype:
        return None
    if etype.startswith('response.output_item.'):
        item = obj.get('item')
        if not isinstance(item, dict) or item.get('type') != 'message':
            return None
        return item.get('id') or ('idx', obj.get('output_index'))
    if etype.startswith(TEXT_EVENT_PREFIXES):
        return obj.get('item_id') or ('idx', obj.get('output_index'))
    return None


def is_message_event(etype, obj):
    return message_key(etype, obj) is not None


def item_key_of(item, position):
    return item.get('id') or ('idx', position)


def collect_drafts(held):
    """止めたイベントから、回答の本文パートごとの文字列を集める。キーは (項目の識別子, content の位置)。
    項目の done を優先し、無ければ delta をつなぐ。"""
    done_items, deltas, order = {}, {}, []
    for etype, obj, raw in held:
        key = message_key(etype, obj)
        if key is None:
            continue
        if key not in order:
            order.append(key)
        if etype == 'response.output_item.done':
            done_items[key] = obj['item']
        elif etype == 'response.output_text.delta':
            deltas.setdefault((key, obj.get('content_index', 0)), []).append(obj.get('delta') or '')
    end = held[-1][1] if held and isinstance(held[-1][1], dict) else {}
    for position, item in enumerate((end.get('response') or {}).get('output') or []):
        if isinstance(item, dict) and item.get('type') == 'message':
            key = item_key_of(item, position)
            done_items.setdefault(key, item)
            if key not in order:
                order.append(key)
    drafts = {}
    for key in order:
        parts = text_parts(done_items[key]) if key in done_items else []
        if parts:
            for index, part in parts:
                drafts[(key, index)] = part.get('text') or ''
        else:
            for (owner, index), chunks in deltas.items():
                if owner == key:
                    drafts[(owner, index)] = ''.join(chunks)
    return drafts


def replace_item_text(item, key, results):
    for index, part in text_parts(item):
        if (key, index) in results:
            part['text'] = results[(key, index)]


def clear_item_text(item, key, results):
    for index, part in text_parts(item):
        if (key, index) in results:
            part['text'] = ''


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'output-gate-relay'

    def log_message(self, *args):
        pass

    # ---- 共通の入口 -------------------------------------------------------------------------
    def handle_any(self):
        if self.headers.get('Upgrade') or 'upgrade' in (self.headers.get('Connection') or '').lower():
            log(event='websocket-refused')
            return self.reply(426, b'')
        if self.path == '/__gate/version':
            info = {'version': VERSION, 'pid': os.getpid(), 'active': Settings.active}
            return self.reply(200, json.dumps(info).encode(), 'application/json')
        if self.path == '/__gate/shutdown' and self.command == 'POST':
            with Settings.active_lock:
                if Settings.active:
                    return self.reply(409, b'busy')
                Settings.closing = True
            self.reply(200, b'bye')
            log(event='shutdown')
            threading.Thread(target=Settings.server.shutdown, daemon=True).start()
            return None
        if not self.path.startswith(PREFIX):
            return self.reply(404, b'')
        suffix = self.path[len(PREFIX):]
        body = self.rfile.read(int(self.headers.get('Content-Length') or 0))
        if self.command == 'POST' and suffix.split('?', 1)[0] == '/responses':
            with Settings.active_lock:
                if Settings.closing:
                    return self.reply_error(503, 'relay is restarting')
                Settings.active += 1
            try:
                return self.handle_responses(suffix, body)
            finally:
                with Settings.active_lock:
                    Settings.active -= 1
        return self.proxy(suffix, body, self.headers.get('Content-Encoding'))

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = handle_any

    def reply(self, status, payload, ctype='text/plain'):
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def reply_error(self, status, message):
        self.reply(status, json.dumps({'error': {'message': f'output-gate relay: {message}'}}, ensure_ascii=False)
                   .encode('utf-8'), 'application/json')

    # ---- 上流への送信 -----------------------------------------------------------------------
    def open_upstream(self, suffix, body, encoding):
        up = Settings.upstream
        cls = http.client.HTTPSConnection if up.scheme == 'https' else http.client.HTTPConnection
        conn = cls(up.hostname, up.port, timeout=Settings.upstream_idle + 30)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        headers['Accept-Encoding'] = 'identity'
        if encoding:
            headers['Content-Encoding'] = encoding
        if body:
            headers['Content-Length'] = str(len(body))
        conn.request(self.command, up.path.rstrip('/') + suffix, body=body or None, headers=headers)
        return conn, conn.getresponse()

    def start_chunked(self, resp):
        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() not in HOP:
                self.send_header(k, v)
        self.send_header('Transfer-Encoding', 'chunked')
        self.end_headers()

    def end_chunked(self):
        self.wfile.write(b'0\r\n\r\n')
        self.wfile.flush()

    def proxy(self, suffix, body, encoding):
        try:
            conn, resp = self.open_upstream(suffix, body, encoding)
        except OSError as error:
            return self.reply_error(502, f'upstream unreachable ({type(error).__name__})')
        try:
            self.start_chunked(resp)
            while True:
                chunk = resp.read1(65536)
                if not chunk:
                    break
                self.send_chunk(chunk)
            self.end_chunked()
        finally:
            conn.close()

    # ---- /responses ----------------------------------------------------------------------
    def handle_responses(self, suffix, raw):
        encoding = (self.headers.get('Content-Encoding') or '').lower()
        try:
            if encoding == 'zstd':
                if zstd is None:
                    raise ValueError('zstd is not available')
                raw = zstd.decompress(raw)
            elif encoding == 'gzip':
                raw = gzip.decompress(raw)
            elif encoding not in ('', 'identity'):
                raise ValueError(f'unknown content encoding {encoding}')
            body = json.loads(raw.decode('utf-8'))
            if not isinstance(body, dict):
                raise ValueError('body is not an object')
        except DECODE_ERRORS as error:
            log(event='unreadable-body', error=type(error).__name__)
            return self.reply_error(400, f'cannot read the request body ({error}); the answer was not sent unchecked')
        mode, reason, kind = self.classify(body)
        for item in body.get('input') or []:
            if isinstance(item, dict) and item.get('role') == 'assistant':
                strip_message_ciphertext(item)
        data = json.dumps(body, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        up_encoding = None
        if zstd is not None:
            data, up_encoding = zstd.compress(data), 'zstd'
        started = time.time()
        self.checks = Checks()
        try:
            conn, resp = self.open_upstream(suffix, data, up_encoding)
        except OSError as error:
            return self.reply_error(502, f'upstream unreachable ({type(error).__name__})')
        try:
            ctype = resp.getheader('Content-Type') or ''
            # ChatGPT のバックエンドは Content-Type を付けずに SSE を返すことがある (実測)。JSON と明示された時だけ SSE でないとみなす。
            if resp.status != 200 or ctype.startswith('application/json'):
                self.start_chunked(resp)
                while True:
                    chunk = resp.read1(65536)
                    if not chunk:
                        break
                    self.send_chunk(chunk)
                self.end_chunked()
                log(event='responses', mode=mode, status=resp.status, sse=False, ctype=ctype)
                return
            self.start_chunked(resp)
            decision = self.stream_events(resp, body, mode, reason, kind)
            log(event='responses', mode=mode, decision=decision, dur=round(time.time() - started, 3))
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # Codex が切断した: 検査役と上流の応答を止める (Codex は同じ要求を再試行する)。
            self.checks.cancel()
            log(event='client-gone', mode=mode)
        finally:
            try:
                if conn.sock is not None:
                    conn.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            conn.close()

    def classify(self, body):
        """要求をどう扱うかを決める: check (検査する) / review / unchecked (理由を添える) / pass (そのまま)。"""
        try:
            meta = json.loads(self.headers.get('x-codex-turn-metadata') or '{}')
        except ValueError:
            meta = {}
        if not isinstance(meta, dict):
            meta = {}
        kind = meta.get('request_kind')
        text = body.get('text')
        if isinstance(text, dict) and text.get('format'):
            return 'pass', None, kind   # 出力の形式を指定した要求: 機械が読む
        if self.delegated(meta.get('session_id')):
            return 'pass', None, kind   # 委譲の子セッション: 親が出力を読む
        if kind in PASS_KINDS:
            return 'pass', None, kind
        if kind != 'turn':
            return 'unchecked', '知らない種類の要求', kind
        subagent = self.headers.get('x-openai-subagent')
        if subagent == 'review':
            return 'review', None, kind
        if subagent:
            return 'pass', None, kind
        return 'check', None, kind

    @staticmethod
    def delegated(session_id):
        if not isinstance(session_id, str) or not re.fullmatch(r'[0-9A-Za-z_-]{1,128}', session_id):
            return False
        path = Settings.state_dir / 'delegated' / session_id
        try:
            return time.time() - path.stat().st_mtime < DELEGATED_TTL
        except OSError:
            return False

    def read_events(self, resp, out):
        """上流の SSE を読んで (種類, オブジェクト, 生のバイト列) を out に入れる。終わりは None。"""
        lines, raw = [], b''
        try:
            while True:
                line = resp.readline()
                if not line:
                    break
                raw += line
                text = line.decode('utf-8', 'replace').rstrip('\r\n')
                if text == '':
                    if lines:
                        etype, obj = parse_event(lines)
                        out.put((etype, obj, raw))
                    lines, raw = [], b''
                    continue
                lines.append(text)
        except (OSError, ValueError, http.client.HTTPException):
            pass
        out.put(None)

    def send_chunk(self, data):
        if data:
            self.wfile.write(b'%x\r\n%s\r\n' % (len(data), data))
            self.wfile.flush()
            self.last_write = time.time()

    def keepalive_if_due(self):
        if time.time() - self.last_write >= Settings.keepalive:
            self.send_chunk(KEEPALIVE)

    def stream_events(self, resp, body, mode, reason, kind):
        """上流のイベントを流す。回答の項目に関わるイベントは応答の終わりまで止める。"""
        events = queue.Queue()
        threading.Thread(target=self.read_events, args=(resp, events), daemon=True).start()
        self.last_write = time.time()
        held, holding, decision = [], False, 'passed'
        compaction_items = []
        last_upstream = time.time()
        while True:
            try:
                ev = events.get(timeout=min(Settings.keepalive, 1.0))
            except queue.Empty:
                if time.time() - last_upstream > Settings.upstream_idle:
                    # 上流が止まった: 止めていた回答は流さずに切る。Codex は再試行する。
                    self.abort_held(held, None)
                    return 'upstream-idle'
                if holding:
                    self.keepalive_if_due()
                continue
            last_upstream = time.time()
            if ev is None:
                self.abort_held(held, None)
                return 'upstream-ended-while-holding' if held else decision
            etype, obj, raw = ev
            item = obj.get('item') if isinstance(obj, dict) else None
            if kind == 'compaction' and etype == 'response.output_item.done' and isinstance(item, dict) \
                    and item.get('type') in COMPACTION_TYPES:
                compaction_items.append(item)
            if mode == 'pass':
                if etype == 'response.completed' and kind == 'compaction':
                    output = (obj.get('response') or {}).get('output') or []
                    try:
                        remember_compaction(body, compaction_items + list(output))
                    except OSError as error:
                        # 組を保存できないまま compaction を確定させない。Codex の再試行に任せる。
                        log(event='compaction-store-failed', error=type(error).__name__)
                        self.end_chunked()
                        return 'compaction-store-failed'
                self.send_chunk(self.stripped(etype, obj, raw))
                continue
            if not holding and is_message_event(etype, obj):
                holding = True
            if not holding:
                self.send_chunk(self.stripped(etype, obj, raw))
                continue
            held.append([etype, obj, raw])
            if etype in ('response.completed', 'response.incomplete'):
                decision = self.release(held, body, mode, reason)
                held, holding = [], False
            elif etype in ('response.failed', 'error'):
                self.abort_held(held[:-1], held[-1])
                held, holding, decision = [], False, 'upstream-failed'
            else:
                self.keepalive_if_due()

    def abort_held(self, held, end_event):
        """止めていた間に上流が失敗した: 回答の項目のイベントは流さず、それ以外と終わりのイベントを流す。"""
        dropped = 0
        for etype, obj, raw in held:
            if is_message_event(etype, obj):
                dropped += 1
                continue
            self.send_chunk(self.stripped(etype, obj, raw))
        if end_event is not None:
            self.send_chunk(self.stripped(*end_event))
        self.end_chunked()
        if dropped:
            log(event='dropped-unchecked-answer', events=dropped)

    def stripped(self, etype, obj, raw):
        if not isinstance(obj, dict):
            return raw
        changed = strip_message_ciphertext(obj.get('item'))
        response = obj.get('response')
        if isinstance(response, dict):
            for item in response.get('output') or []:
                changed = strip_message_ciphertext(item) or changed
        return encode_event(etype, obj) if changed else raw

    def release(self, held, body, mode, reason):
        """止めていたイベントを、検査した文字列で組み直して流す。"""
        drafts = collect_drafts(held)
        results, statuses = {}, []
        check_started = time.time()
        if mode == 'unchecked':
            for key, draft in drafts.items():
                results[key] = UNCHECKED_PREFIX.format(reason) + draft
        else:
            func = check_review if mode == 'review' else check_text
            pool = concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(drafts)))
            try:
                # 空白だけのパートは規則に反しようがないので、検査役を起動せずにそのまま流す。
                results.update({key: draft for key, draft in drafts.items() if not draft.strip()})
                futures = {key: pool.submit(func, body, draft, self.checks) for key, draft in drafts.items()
                           if draft.strip()}
                while not all(f.done() for f in futures.values()):
                    concurrent.futures.wait(futures.values(), timeout=min(Settings.keepalive, 1.0))
                    self.keepalive_if_due()
                for key, future in futures.items():
                    try:
                        results[key], status = future.result()
                    except Exception as error:  # 想定外の失敗でも応答を切らず、原文に理由を添えて流す
                        reason = f'中継の内部エラー ({type(error).__name__})'
                        results[key], status = UNCHECKED_PREFIX.format(reason) + drafts[key], 'unchecked'
                    statuses.append(status)
            finally:
                pool.shutdown(wait=False, cancel_futures=True)
        delta_sent = set()
        for etype, obj, raw in held:
            key = message_key(etype, obj)
            part_key = (key, obj.get('content_index', 0)) if key is not None else None
            new = results.get(part_key)
            if etype == 'response.output_item.done' and key is not None:
                replace_item_text(obj['item'], key, results)
                raw = encode_event(etype, obj)
            elif etype == 'response.output_item.added' and key is not None:
                # 開始のイベントに本文が入っていても原文を流さない。訂正版は後の delta と done で届く。
                clear_item_text(obj['item'], key, results)
                raw = encode_event(etype, obj)
            elif etype == 'response.content_part.added' and part_key in results and \
                    isinstance(obj.get('part'), dict) and obj['part'].get('text'):
                obj['part']['text'] = ''
                raw = encode_event(etype, obj)
            elif new is not None and etype.startswith(TEXT_EVENT_PREFIXES):
                if etype == 'response.output_text.delta':
                    if part_key in delta_sent:
                        continue
                    delta_sent.add(part_key)
                    obj['delta'] = new
                elif etype == 'response.output_text.done':
                    obj['text'] = new
                elif etype == 'response.content_part.done' and (obj.get('part') or {}).get('type') == 'output_text':
                    obj['part']['text'] = new
                raw = encode_event(etype, obj)
            elif etype in ('response.completed', 'response.incomplete') and isinstance(obj, dict):
                for position, item in enumerate((obj.get('response') or {}).get('output') or []):
                    if isinstance(item, dict) and item.get('type') == 'message':
                        replace_item_text(item, item_key_of(item, position), results)
                raw = encode_event(etype, obj)
            self.send_chunk(self.stripped(etype, obj, raw))
        log(event='checked', mode=mode, items=len(results), check_dur=round(time.time() - check_started, 3),
            statuses=sorted({s or '' for s in statuses}))
        return 'rewritten' if results else 'no-message'


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    # POSIX では、直前の中継の接続が TIME_WAIT で残っていても待受を取り直せるようにする。Windows の
    # SO_REUSEADDR は使用中のポートの横取りまで許すため付けない。
    allow_reuse_address = os.name != 'nt'

    def handle_error(self, request, client_address):
        # Codex が接続を先に閉じることはよくある。中断の記録だけ残し、標準エラーに履歴を出さない。
        log(event='connection-error', error=type(sys.exc_info()[1]).__name__)


def version_of(port, timeout=1.0):
    try:
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
        conn.request('GET', '/__gate/version')
        resp = conn.getresponse()
        data = json.loads(resp.read().decode('utf-8')) if resp.status == 200 else None
        conn.close()
        return data
    except (OSError, ValueError, http.client.HTTPException):
        return None


def relay_env(environ):
    return {name: value for name, value in environ.items() if name.upper() in RELAY_ENV}


def detach(args):
    """呼び出し元 (hook) から切り離して中継を起動し、待受が応答するまで待つ。応答したら True。"""
    command = [sys.executable, '-I', str(SCRIPT), '--port', str(args.port), '--state-dir', args.state_dir,
               '--upstream', args.upstream]
    kwargs = {'stdin': subprocess.DEVNULL, 'stdout': subprocess.DEVNULL, 'stderr': subprocess.DEVNULL,
              'close_fds': True, 'env': relay_env(os.environ),
              # 起動したセッションの作業ディレクトリを掴んだままにしない (Windows ではそのフォルダーを消せなくなる)。
              'cwd': args.state_dir}
    if os.name == 'nt':
        flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        try:
            # hook を動かす側がジョブで子を束ねていても、hook の終了と一緒に止まらないようにする。
            child = subprocess.Popen(command, creationflags=flags | subprocess.CREATE_BREAKAWAY_FROM_JOB, **kwargs)
        except OSError:
            child = subprocess.Popen(command, creationflags=flags, **kwargs)
    else:
        child = subprocess.Popen(command, start_new_session=True, **kwargs)
    deadline = time.time() + 5
    while time.time() < deadline:
        if version_of(args.port, timeout=0.5):
            return True
        if child.poll() is not None:
            break
        time.sleep(0.1)
    return False


def request_shutdown(port):
    try:
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
        conn.request('POST', '/__gate/shutdown')
        status = conn.getresponse().status
        conn.close()
        return status
    except (OSError, http.client.HTTPException):
        return None


def ensure(args):
    """中継が動いていなければ起動し、古い版なら自己試験を通してから入れ替える。"""
    found = version_of(args.port)
    if found and found.get('version') == VERSION:
        return {'state': 'running', 'version': VERSION}
    if not found:
        return {'state': 'started' if detach(args) else 'failed', 'version': VERSION}
    running = found.get('version')
    ok, detail = self_test()
    if not ok:
        return {'state': 'update-failed', 'version': VERSION, 'running_version': running, 'detail': detail}
    now = version_of(args.port)
    if now and now.get('version') == VERSION:
        return {'state': 'running', 'version': VERSION}   # 同時に動いた別の hook が入れ替え済み
    status = request_shutdown(args.port)
    if status == 409:
        return {'state': 'update-deferred', 'version': VERSION, 'running_version': running}
    if status not in (200, None):
        return {'state': 'update-failed', 'version': VERSION, 'running_version': running,
                'detail': f'shutdown answered {status}'}
    # None は、同時に動いた別の hook が先に終了させた場合にも返る。そのまま新しい版の起動へ進む。
    deadline = time.time() + 5
    while time.time() < deadline:
        now = version_of(args.port, timeout=0.3)
        if now is None or now.get('version') == VERSION:
            break
        time.sleep(0.1)
    return {'state': 'updated' if detach(args) else 'failed', 'version': VERSION, 'running_version': running}


SELF_TEST_TEXT = 'これは効く。'


def self_test():
    """偽の上流と偽の検査処理で、要求の処理経路と WebSocket の拒否を確かめる。上流や認証情報は使わない。"""
    checker = SCRIPT.parent / 'output-gate-check.py'
    try:
        compile(checker.read_text(encoding='utf-8'), str(checker), 'exec')
    except (SyntaxError, OSError, ValueError) as error:
        return False, f'checker does not compile: {error}'
    item = {'id': 'msg_t', 'type': 'message', 'role': 'assistant', 'status': 'completed',
            'content': [{'type': 'output_text', 'text': SELF_TEST_TEXT, 'annotations': []}]}
    events = [{'type': 'response.output_item.added', 'output_index': 0, 'item': dict(item, content=[])},
              {'type': 'response.output_text.delta', 'item_id': 'msg_t', 'output_index': 0, 'content_index': 0,
               'delta': SELF_TEST_TEXT},
              {'type': 'response.output_text.done', 'item_id': 'msg_t', 'output_index': 0, 'content_index': 0,
               'text': SELF_TEST_TEXT},
              {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
              {'type': 'response.completed', 'response': {'id': 'r', 'status': 'completed', 'output': [item]}}]
    stream = b''.join(encode_event(e['type'], e) for e in events)

    class Fake(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *a):
            pass

        def do_POST(self):
            self.rfile.read(int(self.headers.get('Content-Length') or 0))
            self.send_response(200)
            self.send_header('Content-Length', str(len(stream)))
            self.end_headers()
            self.wfile.write(stream)

    saved = (Settings.upstream, Settings.check_cmd, Settings.state_dir)
    fake = Server(('127.0.0.1', 0), Fake)
    relay = Server(('127.0.0.1', 0), Handler)
    try:
        threading.Thread(target=fake.serve_forever, daemon=True).start()
        threading.Thread(target=relay.serve_forever, daemon=True).start()
        Settings.upstream = urllib.parse.urlsplit(f'http://127.0.0.1:{fake.server_port}{PREFIX}')
        Settings.check_cmd = [sys.executable, '-I', '-c', 'import json,sys; p=json.load(sys.stdin); '
                              'print(json.dumps({"status":"checked","text":p["draft"].replace("効く","速い")}))']
        conn = http.client.HTTPConnection('127.0.0.1', relay.server_port, timeout=30)
        conn.request('POST', PREFIX + '/responses', json.dumps({'input': []}).encode(),
                     {'x-codex-turn-metadata': json.dumps({'request_kind': 'turn'})})
        body = conn.getresponse().read().decode('utf-8')
        conn.close()
        if 'これは速い。' not in body or SELF_TEST_TEXT in body:
            return False, 'the answer was not rebuilt with the checked text'
        conn = http.client.HTTPConnection('127.0.0.1', relay.server_port, timeout=10)
        conn.request('GET', PREFIX + '/responses', headers={'Connection': 'Upgrade', 'Upgrade': 'websocket'})
        status = conn.getresponse().status
        conn.close()
        if status != 426:
            return False, f'websocket upgrade answered {status}'
        return True, 'ok'
    except (OSError, http.client.HTTPException) as error:
        return False, f'{type(error).__name__}: {error}'
    finally:
        Settings.upstream, Settings.check_cmd, Settings.state_dir = saved
        fake.shutdown()
        relay.shutdown()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--state-dir', required=True)
    parser.add_argument('--upstream', default=DEFAULT_UPSTREAM)
    parser.add_argument('--ensure', action='store_true', help='start or update the relay in the background')
    parser.add_argument('--self-test', action='store_true', help='run the local self test and exit')
    args = parser.parse_args()
    Settings.state_dir = Path(args.state_dir)
    if args.self_test:
        Settings.state_dir = Path(tempfile.mkdtemp(prefix='output-gate-selftest-'))
        ok, detail = self_test()
        print(detail)
        sys.exit(0 if ok else 1)
    if args.ensure:
        Settings.state_dir.mkdir(parents=True, exist_ok=True)
        result = ensure(args)
        print(json.dumps(result, ensure_ascii=False))
        sys.exit(0 if result['state'] in ('running', 'started', 'updated', 'update-deferred') else 1)
    Settings.upstream = urllib.parse.urlsplit(args.upstream)
    Settings.state_dir = Path(args.state_dir)
    Settings.state_dir.mkdir(parents=True, exist_ok=True)
    try:
        server = Server(('127.0.0.1', args.port), Handler)
    except OSError as error:
        print(f'output-gate-relay: 127.0.0.1:{args.port} で待ち受けられない: {error}', file=sys.stderr)
        sys.exit(3)
    Settings.server = server
    log(event='start', version=VERSION, port=args.port)
    server.serve_forever()
    server.server_close()


if __name__ == '__main__':
    main()
