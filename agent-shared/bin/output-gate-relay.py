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

未達のとき: 最終回答を空の message に差し替え、指摘と原文を保存して end_turn=false で続行する。
同じターンの次の要求では、空の message を原文に戻し、指摘を上流の入力へ加える。未達がなくなるまで繰り返す。

状態ディレクトリ:
  delegated/<session_id>  委譲の子セッションの登録 (hook が書く)。24 時間以内のものは検査せずに流す。
  continue/<session_id>   旧版中継の続行登録。24 時間で消去する。
  gate/<session_id>/<turn_id>.json
                          差し戻しの状態 {phase, round, findings, agent_message, original, display, display_clean,
                          notice_marker, notices, shown?, created, engine, engine_failures, dropped}。
                          phase は substituted → blocked で修正を続け、resolved または停滞による stopped で
                          終わる。round は直させた回数。resolved にするときは original と agent_message を消す。
                          original は保留した置き換え前の原文、display は訂正済みの回収用本文、
                          shown は hook の回収が表示した印。notices は保留した回答ごとの
                          {original, inject?} で、同じターンの以後の要求で各回の案内を原文に戻すために使う。inject は
                          Codex の履歴に入らないため要求ごとに足し直す指摘。
  turns/<session_id>/<turn_id>.json
                          ターンの証拠 {turn_id, time, records, shown, start}。records は呼び出しと出力 (と取得
                          できなかった範囲の印) を起きた順に、shown は表示済みの途中の文章、start はターンの開始時の
                          会話。セッションごとに直近 10 ターン・24 時間を残す。
  compaction.json         サーバー側の compaction の項目 (暗号化データの SHA-256) と、その時点の利用者と assistant の会話の組。
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
UNAVAILABLE = '回答の確認を完了できませんでした。\n\n'
# Codex が会話の先頭などに利用者の発言として入れる文脈 (AGENTS.md と環境の情報) の書き出し。
INJECTED_CONTEXT = ('# AGENTS.md instructions', '<environment_context>')
COMPACTION_TYPES = {'compaction', 'context_compaction'}
STORE_LIMIT = 1000
DELEGATED_TTL = 24 * 3600
STATE_TTL = 24 * 3600      # 差し戻しの状態・続行の登録・保存した証拠を残す時間
KEEP_TURNS = 10            # セッションごとに残す直近のターンの証拠
SWEEP_EVERY = 60
# Codex の Stop hook の reason は、次の要求に利用者の発言としてこの形で入る (実測)。依頼として扱わない。
HOOK_PROMPT = '<hook_prompt'
# Codex が実行して結果を返す呼び出し。これを含む応答の後は Codex が同じターンで続きを要求する
# (codex-rs 0.164.0 の ToolRouter::build_tool_call が ToolCall を返す型。tool_search_call は execution が client で
# call_id があるときだけ。local_shell_call は ToolCall にならず、続きを要求しない)。
CLIENT_CALLS = {'function_call', 'custom_tool_call'}
CALL_TYPES = CLIENT_CALLS | {'local_shell_call', 'web_search_call', 'tool_search_call', 'image_generation_call'}
# Codex が同じターンで続きを要求する打ち切りの理由。interrupted は end_turn=false の完了として扱われ、
# content_filter は同じターンで要求し直される。ほかの理由はエラーとしてターンを終える (codex-rs のソース)。
CONTINUED_INCOMPLETE = {'interrupted', 'content_filter'}
OUTPUT_TYPES = {'function_call_output', 'custom_tool_call_output', 'tool_search_output'}
UNKNOWN_TURN = '前のターン (区別不明)'
SAFE_ID = re.compile(r'[0-9A-Za-z_.-]{1,128}')
EXIT_CODE = re.compile(r'(?:exit code|exited with code|exit status)\s*:?\s*(-?\d+)', re.I)
REVIEW_MARK = '\n<<<OUTPUT-GATE-FIELD-{}>>>\n'
# 切り離して起動する中継に渡す環境変数。中継は複数のセッションが共有して長く動くため、起動した
# セッション固有の値 (委譲の印、OUTPUT_GATE_* のコマンドの差し替え、API キー) を持ち込まない。検査役 (codex と
# gitleaks) の起動・ログイン情報の場所・通信に要るものだけを渡す。
RELAY_ENV = {'PATH', 'PATHEXT', 'HOME', 'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH', 'SYSTEMROOT', 'SYSTEMDRIVE',
             'WINDIR', 'COMSPEC', 'TEMP', 'TMP', 'TMPDIR', 'APPDATA', 'LOCALAPPDATA', 'PROGRAMDATA',
             'PROGRAMFILES', 'LANG', 'LC_ALL', 'LC_CTYPE', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
             'XDG_RUNTIME_DIR', 'CODEX_HOME', 'SSL_CERT_FILE', 'SSL_CERT_DIR', 'HTTP_PROXY', 'HTTPS_PROXY',
             'ALL_PROXY', 'NO_PROXY',
             # 検査役の設定 (先に試す系統・モデル) の場所。どの環境から起動した中継でも同じ設定で検査するため。
             'OUTPUT_GATE_SETTINGS'}


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
    last_sweep = 0.0


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


def stored_conversation(compaction_item):
    """旧版の answers には依頼と古い回答が無いため、復元できた発言にも欠落の印を付ける。"""
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
    if isinstance(entry.get('conversation'), list):
        return list(entry['conversation']), bool(entry.get('incomplete'))
    return [{'role': 'assistant', 'text': a} for a in entry.get('answers') or []], True


def save_store(store):
    if len(store) > STORE_LIMIT:
        for key in sorted(store, key=lambda k: store[k].get('used', 0))[:len(store) - STORE_LIMIT]:
            del store[key]
    path = Settings.state_dir / 'compaction.json'
    tmp = path.with_name(f'.compaction.{os.getpid()}.{threading.get_ident()}.tmp')
    tmp.write_text(json.dumps(store, ensure_ascii=False), encoding='utf-8')
    os.replace(tmp, path)


def remember_compaction(body, output_items):
    conversation, incomplete = conversation_with_compaction(body.get('input') or [])
    with Settings.store_lock:
        store = load_store()
        for item in output_items:
            if isinstance(item, dict) and item.get('type') in COMPACTION_TYPES and compaction_key(item):
                store[compaction_key(item)] = {'conversation': conversation, 'incomplete': incomplete, 'used': time.time()}
        save_store(store)


def is_request(item):
    """利用者の依頼か。Codex が利用者の発言の形で送る AGENTS.md・環境の情報と、Stop hook の reason は除く。"""
    if not (isinstance(item, dict) and item.get('type') == 'message' and item.get('role') == 'user'):
        return False
    text = input_text(item).lstrip()
    return not text.startswith(INJECTED_CONTEXT) and not text.startswith(HOOK_PROMPT)


def request_index(items):
    found = None
    for index, item in enumerate(items):
        if is_request(item):
            found = index
    return found


def conversation_of(items, end=None):
    """会話の発言 (依頼と回答) を {role, text} で返す。end までの項目だけを見る。"""
    return [{'role': i['role'], 'text': input_text(i)} for i in items[:end]
            if is_request(i) or (isinstance(i, dict) and i.get('type') == 'message' and i.get('role') == 'assistant'
                                 and i.get('phase') != 'partial_answer')]


def conversation_with_compaction(items):
    compaction_item, rest = split_at_compaction(items)
    if compaction_item is None:
        return conversation_of(items), False
    saved = stored_conversation(compaction_item)
    if saved is None:
        log(event='compaction-pair-missing')
        return conversation_of(items), True
    conversation, incomplete = saved
    before = conversation_of(items[:len(items) - len(rest)])
    cursor, extra = 0, []
    # Codex は過去の user 発言を compaction の前にも残す。位置を進めて照合し、同じ回答の別の出現は区別する。
    for message in before:
        found = next((n for n in range(cursor, len(conversation)) if conversation[n] == message), None)
        if found is None:
            extra.append(message)
        else:
            cursor = found + 1
    return conversation + extra + conversation_of(rest), incomplete or bool(extra)


def checker_payload(body, bodies, **extra):
    conversation, compacted_note = conversation_with_compaction(body.get('input') or [])
    users = [m for m in conversation if m.get('role') == 'user']
    programs = body.get('access_programs') or {}
    payload = {'origin': 'codex', 'latest_user': users[-1]['text'] if users else '',
               'recent_messages': conversation, 'bodies': list(bodies), 'final': False,
               'cyber_program': programs.get('cyber') if isinstance(programs, dict) else None,
               'compacted_note': compacted_note}
    payload.update(extra)
    return payload


# ---- 差し戻しの状態と、ターンの証拠 ----------------------------------------------------------------
def safe_id(value):
    return isinstance(value, str) and SAFE_ID.fullmatch(value) is not None and value not in ('.', '..')


def read_json(path):
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def write_json(path, data):
    """一時ファイルに書いてから置き換える。失敗は OSError。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f'.{path.name}.{os.getpid()}.{threading.get_ident()}.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    os.replace(tmp, path)


def gate_path(sid, tid):
    return Settings.state_dir / 'gate' / sid / f'{tid}.json'


def output_text(item):
    out = item.get('output')
    if isinstance(out, dict):
        out = out.get('content') if 'content' in out else out.get('output')
    if isinstance(out, list):
        return ''.join(p.get('text') or '' for p in out if isinstance(p, dict))
    return out if isinstance(out, str) else json.dumps(out, ensure_ascii=False)


def records_from(items):
    """要求本文の項目から、呼び出しと出力の記録を起きた順に取り出す。key で保存済みかを見分ける。"""
    records = []
    for item in items:
        if not isinstance(item, dict):
            continue
        kind = item.get('type')
        if kind in CALL_TYPES:
            call_id = item.get('call_id') or item.get('id')
            action = item.get('action')
            command = ' '.join(action['command']) if kind == 'local_shell_call' and isinstance(action, dict) and \
                isinstance(action.get('command'), list) else None
            raw = item.get('arguments') if 'arguments' in item else item.get('input', action)
            records.append({'key': f'call:{kind}:{call_id or hashlib.sha256(json.dumps(item, sort_keys=True).encode()).hexdigest()}',
                            'kind': 'call', 'call_id': call_id, 'tool': item.get('name') or kind,
                            'input': raw if isinstance(raw, (str, dict, list)) or raw is None else str(raw),
                            'command': command})
            if not is_client_call(item) and kind != 'tool_search_call':
                # サーバー側で完結する呼び出し (Web 検索など) は、結果の本文が要求にも応答にも届かない。
                records.append({'key': 'nores:' + records[-1]['key'], 'kind': 'gap',
                                'note': f'{kind} の結果の本文は取得できない (サーバー側で完結する呼び出し)'})
        elif kind in OUTPUT_TYPES:
            records.append({'key': f'out:{kind}:{item.get("call_id")}', 'kind': 'output',
                            'call_id': item.get('call_id'), 'output': output_text(item)})
    return records


def is_client_call(item):
    """Codex が実行して結果を返す呼び出しか (これがあると Codex は同じターンで続きを要求する)。"""
    if not isinstance(item, dict):
        return False
    if item.get('type') == 'tool_search_call':
        return item.get('execution') == 'client' and bool(item.get('call_id'))
    return item.get('type') in CLIENT_CALLS


def add_records(sid, tid, items):
    """応答の項目 (サーバー側で完結した呼び出しなど) を、検査の前にターンの証拠へ足す。"""
    with Settings.store_lock:
        path = Settings.state_dir / 'turns' / sid / f'{tid}.json'
        turn = read_json(path)
        if turn is None:
            return
        saved = {record['key'] for record in turn['records']}
        new = [record for record in records_from(items) if record['key'] not in saved]
        if new:
            turn['records'] += new
            write_json(path, turn)


def gap_record(note):
    return {'key': f'gap:{time.time()}:{os.urandom(4).hex()}', 'kind': 'gap', 'note': note}


def has_compaction(items):
    return any(isinstance(i, dict) and i.get('type') in COMPACTION_TYPES for i in items)


def evidence_items(records, prefix):
    """保存した記録から、検査処理へ渡す証拠の項目 (呼び出しと出力の組) を作る。"""
    items, calls = [], {}
    for record in records:
        if record['kind'] == 'gap':
            items.append({'id': f'{prefix}{len(items) + 1}', 'unavailable': True, 'note': record['note']})
            continue
        item = calls.get(record.get('call_id')) if record['kind'] == 'output' else None
        if item is None:
            item = {'id': f'{prefix}{len(items) + 1}', 'tool': record.get('tool')}
            items.append(item)
            if record.get('call_id') is not None:
                calls[record['call_id']] = item
        if record['kind'] == 'call':
            item['input'] = record.get('input')
            if record.get('command'):
                item['command'] = record['command']
        else:
            text = record.get('output') or ''
            item['output'] = text
            codes = EXIT_CODE.findall(text)
            if codes:
                item['exit_code'] = int(codes[-1])
            if (codes and int(codes[-1]) != 0) or text.lstrip().startswith('Script failed'):
                item['failed'] = True
    return items


def sweep(force=False):
    """24 時間を過ぎた状態・登録・証拠と、セッションごとの直近 10 ターンより前の証拠を消す。"""
    now = time.time()
    if not force and now - Settings.last_sweep < SWEEP_EVERY:
        return
    Settings.last_sweep = now
    root = Settings.state_dir
    for path in list(root.glob('gate/*/*.json')):
        state = read_json(path) or {}
        if now - float(state.get('created') or 0) > STATE_TTL:
            path.unlink(missing_ok=True)
    for path in [*root.glob('continue/*'), *root.glob('delegated/*'), *root.glob('unrouted/*'), *root.glob('reported/*')]:
        try:
            if now - path.stat().st_mtime > STATE_TTL:
                path.unlink()
        except OSError:
            pass
    for session in list(root.glob('turns/*')):
        turns = sorted(((float((read_json(p) or {}).get('time') or 0), p) for p in session.glob('*.json')),
                       key=lambda pair: pair[0], reverse=True)
        for rank, (stamp, path) in enumerate(turns):
            if rank >= KEEP_TURNS or now - stamp > STATE_TTL:
                path.unlink(missing_ok=True)


def record_turn(sid, tid, items):
    """要求ごとに、利用者の最新の依頼より後の呼び出しと出力のうち保存していないものを足す。新しいターンの最初の
    要求では、ターンの開始時の会話を保存する。セッションに保存済みの証拠が無ければ、依頼より前の呼び出しを
    「前のターン (区別不明)」として取り込む。失敗は OSError。"""
    start, _ = conversation_with_compaction(items)
    with Settings.store_lock:
        directory = Settings.state_dir / 'turns' / sid
        path = directory / f'{tid}.json'
        turn = read_json(path)
        index = request_index(items)
        after = items[index + 1:] if index is not None else items
        if turn is None:
            known_turns = list(directory.glob('*.json')) if directory.exists() else []
            turn = {'turn_id': tid, 'time': time.time(), 'records': [], 'shown': [],
                    'start': start}
            if not known_turns and index is not None:
                before = records_from(items[:index])
                if has_compaction(items[:index]):
                    before.insert(0, gap_record('compaction で消えた前のターンの範囲 (中継が保存していない)'))
                if before:
                    write_json(directory / 'unknown.json', {'turn_id': UNKNOWN_TURN, 'time': time.time() - 1,
                                                            'records': before})
            if has_compaction(after):
                turn['records'].append(gap_record('compaction で消えたこのターンの範囲 (中継が保存していない)'))
        saved = {record['key'] for record in turn['records']}
        turn['records'] += [record for record in records_from(after) if record['key'] not in saved]
        write_json(path, turn)
    sweep()
    return turn


def turn_evidence(sid, tid):
    """(今のターンの証拠, 前のターンの証拠) を返す。ID はターンごとの接頭辞で全体を通して一意にする。"""
    directory = Settings.state_dir / 'turns' / sid
    current = read_json(directory / f'{tid}.json') or {'records': []}
    others = sorted((t for p in directory.glob('*.json') if p.stem != tid for t in [read_json(p)] if t),
                    key=lambda t: float(t.get('time') or 0))[-KEEP_TURNS:]
    previous = []
    for number, turn in enumerate(others, 1):
        items = evidence_items(turn.get('records') or [], f'p{number}-')
        if items:
            previous.append({'turn_id': str(turn.get('turn_id')), 'time': turn.get('time'), 'items': items})
    return evidence_items(current.get('records') or [], 'e'), previous


def add_shown(sid, tid, text):
    with Settings.store_lock:
        path = Settings.state_dir / 'turns' / sid / f'{tid}.json'
        turn = read_json(path)
        if turn is not None:
            turn.setdefault('shown', []).append(text)
            write_json(path, turn)


def notice_entries(gate):
    """案内の印ごとの {original, inject?}。前の回の案内も、同じターンの以後の要求で原文に戻すために残す。"""
    entries = {marker: dict(entry) for marker, entry in (gate.get('notices') or {}).items()
               if isinstance(entry, dict) and isinstance(entry.get('original'), str)}
    marker = gate.get('notice_marker')
    if marker and isinstance(gate.get('original'), str):
        entries.setdefault(marker, {'original': gate['original']})
    return entries


def restore_notices(items, entries):
    """input の案内の回答を原文に戻す。戻した項目の位置を案内の印ごとに返す。"""
    found = {}
    for index, item in enumerate(items):
        if not (isinstance(item, dict) and item.get('type') == 'message' and item.get('role') == 'assistant'):
            continue
        text = input_text(item)
        for marker, entry in entries.items():
            if item.get('id') == marker or marker in text:
                parts = [p for p in item.get('content') or [] if isinstance(p, dict) and 'text' in p]
                for number, part in enumerate(parts):
                    part['text'] = entry['original'] if number == 0 else ''
                if item.get('id') == marker and 'source_id' in entry:
                    if entry['source_id'] is None:
                        item.pop('id', None)
                    else:
                        item['id'] = entry['source_id']
                found[marker] = index
                break
    return found


def engine_record(result):
    return {'engine': result.get('engine'), 'engine_failures': result.get('engine_failures') or [],
            'dropped': result.get('dropped') or [], 'progress': result.get('progress'),
            'independent_recheck': result.get('independent_recheck')}


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


def strings(value, count):
    return isinstance(value, list) and len(value) == count and all(isinstance(v, str) for v in value)


def run_check(payload, checks):
    """検査処理を 1 回呼ぶ。形の違う結果と実行の失敗は unchecked にする。"""
    count = len(payload['bodies'])
    try:
        out = json.loads(checks.run(payload).decode('utf-8'))
        if not isinstance(out, dict) or out.get('status') not in ('checked', 'unchecked'):
            raise ValueError('unexpected result')
        withheld = out['status'] == 'checked' and out.get('bodies') is None and \
            isinstance(out.get('agent_message'), str) and strings(out.get('fallback_bodies'), count)
        if not (withheld or strings(out.get('bodies'), count)) or \
                (out['status'] == 'unchecked' and not (isinstance(out.get('reason'), str) and out['reason'].strip())):
            raise ValueError('unexpected result')
        return out
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        reason = f'検査処理を実行できなかった ({type(error).__name__})'
        bodies = [UNAVAILABLE + payload['bodies'][0], *payload['bodies'][1:]]
        return {'status': 'unchecked', 'bodies': bodies, 'reason': reason, 'findings': []}


def check_text(body, draft, checks):
    result = run_check(checker_payload(body, [draft]), checks)
    return result['bodies'][0], result.get('status')


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
    result = run_check(checker_payload(body, [joined]), checks)
    status = 'checked'
    if result.get('status') == 'checked':
        pieces = result['bodies'][0].split('\n<<<OUTPUT-GATE-FIELD-')
        values = [piece.split('>>>\n', 1)[1] if '>>>\n' in piece else None for piece in pieces[1:]]
        if len(values) == len(slots) and None not in values and pieces[0] == '':
            for (obj, key), value in zip(slots, values):
                obj[key] = value
        else:
            result, status = {'reason': '検査役が説明の欄の区切りを変えた'}, 'unchecked'
    else:
        status = 'unchecked'
    if status == 'unchecked':
        review['overall_explanation'] = UNAVAILABLE + (review.get('overall_explanation') or '')
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
        self.turn_key, self.result_record, self.silent_item = None, None, None
        if mode in ('check', 'compact'):
            self.prepare_turn(body, advance=kind != 'compaction')
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

    def meta(self):
        try:
            meta = json.loads(self.headers.get('x-codex-turn-metadata') or '{}')
        except ValueError:
            meta = {}
        return meta if isinstance(meta, dict) else {}

    def prepare_turn(self, body, *, advance=True):
        """通常のターンの要求: 保留した回答を復元し、指摘と証拠を加える。"""
        meta = self.meta()
        sid, tid = meta.get('session_id'), meta.get('turn_id')
        if not (safe_id(sid) and safe_id(tid)):
            return
        items = body.get('input') or []
        try:
            turn = record_turn(sid, tid, items)
        except OSError as error:
            log(event='turn-store-failed', error=type(error).__name__)
            turn = None
        self.turn_key = (sid, tid, turn)
        gate = read_json(gate_path(sid, tid))
        if gate is None:
            return
        entries = notice_entries(gate)
        positions = restore_notices(items, entries)
        current = gate.get('notice_marker')
        compaction = next((i for i in range(len(items) - 1, -1, -1)
                           if isinstance(items[i], dict) and items[i].get('type') in COMPACTION_TYPES), None)
        if current in entries and current not in positions and compaction is not None and \
                gate.get('phase') in ('substituted', 'blocked'):
            if isinstance(gate.get('agent_message'), str):
                entries[current]['inject'] = gate['agent_message']
            index = compaction + 1
            items.insert(index, {'type': 'message', 'role': 'assistant',
                                 'content': [{'type': 'output_text', 'text': entries[current]['original']}]})
            positions[current] = index
        if gate.get('phase') == 'substituted' and current in positions:
            entries[current]['inject'] = gate.get('agent_message') or ''
        if advance and gate.get('phase') == 'substituted' and current in positions:
            # 同じ回答を受信し直しただけでは数えず、次の要求に保留した回答が含まれてから数える。
            try:
                write_json(gate_path(sid, tid), dict(gate, phase='blocked', round=int(gate.get('round') or 0) + 1,
                                                     notices=entries))
            except OSError as error:
                log(event='gate-state-failed', error=type(error).__name__)
            log(event='continued')
        # 足した指摘は Codex の履歴に入らないので、同じターンの以後の要求にも足し直す。後ろから入れて位置を保つ。
        for marker, index in sorted(positions.items(), key=lambda pair: pair[1], reverse=True):
            inject = entries[marker].get('inject')
            if isinstance(inject, str):
                items.insert(index + 1, {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text':
                             f'<hook_prompt hook_run_id="output-gate">{inject}</hook_prompt>'}]})

    def classify(self, body):
        """要求を check / review / compact / unchecked / pass に分ける。"""
        meta = self.meta()
        kind = meta.get('request_kind')
        text = body.get('text')
        if isinstance(text, dict) and text.get('format'):
            return 'pass', None, kind   # 出力の形式を指定した要求: 機械が読む
        if self.delegated(meta.get('session_id')):
            return 'pass', None, kind   # 委譲の子セッション: 親が出力を読む
        if kind == 'compaction' and not self.headers.get('x-openai-subagent'):
            return 'compact', None, kind
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
        self.client_call = False
        self.passed_items = []
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
            if is_client_call(item):
                self.client_call = True
            if etype == 'response.output_item.done' and isinstance(item, dict):
                self.passed_items.append(item)
            if kind == 'compaction' and etype == 'response.output_item.done' and isinstance(item, dict) \
                    and item.get('type') in COMPACTION_TYPES:
                compaction_items.append(item)
            if mode in ('pass', 'compact'):
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

    def wait(self, func, *args):
        """func を別のスレッドで動かし、終わるまで response.in_progress を流して待つ。"""
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        try:
            future = pool.submit(func, *args)
            while not future.done():
                concurrent.futures.wait([future], timeout=min(Settings.keepalive, 1.0))
                self.keepalive_if_due()
            return future.result()
        finally:
            pool.shutdown(wait=False, cancel_futures=True)

    def check_answer(self, body, held, bodies):
        """通常のターンの回答を検査し、流す本文の並びを返す。最終回答で未達があれば、案内への差し替えと
        差し戻しの状態を扱う。"""
        end_type, end = held[-1][0], held[-1][1] if isinstance(held[-1][1], dict) else {}
        response = end.get('response') if isinstance(end.get('response'), dict) else {}
        output = response.get('output') or []
        client_call = self.client_call or any(is_client_call(i) for i in output)
        incomplete = end_type == 'response.incomplete'
        reason = ((response.get('incomplete_details') or {}).get('reason') if incomplete else None)
        # 呼び出しが無くても、end_turn=false の完了と、Codex が同じターンで続ける打ち切りは最終回答ではない。
        final = not client_call and response.get('end_turn') is not False and reason not in CONTINUED_INCOMPLETE
        if not final:
            self.check_status = 'skipped'
            # 途中の応答は検査せずに流す (待たせないため)。表示した文章は最終回答の検査に「表示済み」として渡す。
            if self.turn_key is not None:
                try:
                    add_shown(self.turn_key[0], self.turn_key[1], '\n\n'.join(bodies))
                except OSError as error:
                    log(event='turn-store-failed', error=type(error).__name__)
            return list(bodies)
        if self.turn_key is None:
            result = run_check(checker_payload(body, bodies, final=final, continuation='none'), self.checks)
            self.check_status = result.get('status')
            self.result_record = engine_record(result)
            if result.get('status') == 'unchecked':
                return [UNAVAILABLE + bodies[0], *bodies[1:]]
            if result.get('findings'):
                corrected = result.get('corrected_bodies')
                shown = list(corrected) if strings(corrected, len(bodies)) else list(bodies)
                shown[0] = UNAVAILABLE + shown[0]
                return shown
            return result['bodies']
        sid, tid, turn = self.turn_key
        gate = read_json(gate_path(sid, tid))
        try:
            # 同じ応答のサーバー側で完結した呼び出し (Web 検索など) も、検査の前に証拠へ入れる。
            seen = [e[1].get('item') for e in held if isinstance(e[1], dict)
                    and e[0] == 'response.output_item.done'] + list(output) + list(self.passed_items)
            add_records(sid, tid, [i for i in seen if isinstance(i, dict) and not is_client_call(i)])
        except OSError as error:
            log(event='turn-store-failed', error=type(error).__name__)
        evidence, previous = turn_evidence(sid, tid)
        # Codex が同じ要求を送り直した回は、まだ直させていないので数えない。
        sent_back = int(gate.get('round') or 0) if gate is not None else 0
        withhold = final and not incomplete
        extra = {'final': final, 'round': sent_back,
                 'continuation': 'withhold' if withhold else 'none', 'evidence': evidence,
                 'previous_evidence': previous, 'turn_start_context': (turn or {}).get('start') or [],
                 'shown_text': '\n\n'.join((read_json(Settings.state_dir / 'turns' / sid / f'{tid}.json') or {})
                                           .get('shown') or [])}
        if sent_back >= 1:
            extra['previous_findings'] = gate.get('findings') or []
            extra['progress_state'] = gate.get('progress_state')
        payload = checker_payload(body, bodies, **extra)
        result = run_check(payload, self.checks)
        self.check_status = result.get('status')
        self.result_record = engine_record(result)
        texts = result.get('bodies')
        if result.get('status') == 'unchecked':
            texts = [UNAVAILABLE + bodies[0], *bodies[1:]]
        elif texts is not None and result.get('findings') and not result.get('stopped'):
            corrected = result.get('corrected_bodies')
            texts = list(corrected) if strings(corrected, len(bodies)) else list(bodies)
            texts[0] = UNAVAILABLE + texts[0]
        if texts is None:
            source = next(key[0] for key, value in collect_drafts(held).items() if value.strip())
            marker = 'msg_' + os.urandom(16).hex()
            original = '\n\n'.join(bodies)
            notices = notice_entries(gate) if gate is not None else {}
            notices[marker] = {'original': original, 'inject': result['agent_message'],
                               'source_id': source if isinstance(source, str) else None}
            state = {'phase': 'substituted', 'round': sent_back, 'findings': result.get('findings') or [],
                     'progress_state': result.get('progress_state'),
                     'agent_message': result['agent_message'], 'original': original,
                     'display': '\n\n'.join(result.get('corrected_bodies') or bodies), 'display_clean': True,
                     'notice_marker': marker, 'notices': notices,
                     'created': time.time(), **self.result_record}
            try:
                write_json(gate_path(sid, tid), state)
                self.silent_item = (source, marker)
                texts = [''] * len(bodies)
                log(event='substituted')
            except OSError as error:
                log(event='gate-state-failed', error=type(error).__name__)
                fallback = result.get('fallback_bodies')
                texts = list(fallback) if strings(fallback, len(bodies)) else [
                    UNAVAILABLE + bodies[0], *bodies[1:]]
        elif final and gate is not None:
            # 本文を表示した後は最後の原文と指摘を回収に
            # 使わないので消す。各回の案内を原文に戻す notices は、同じターンの以後の要求のために残す。
            state = dict(gate, phase='stopped' if result.get('stopped') else 'resolved', round=sent_back,
                         findings=result.get('findings') or [], progress_state=result.get('progress_state'),
                         notices=notice_entries(gate), **self.result_record)
            state.pop('original', None)
            state.pop('agent_message', None)
            try:
                write_json(gate_path(sid, tid), state)
            except OSError as error:
                log(event='gate-state-failed', error=type(error).__name__)
        return texts

    def release(self, held, body, mode, reason):
        """止めていたイベントを、検査した文字列で組み直して流す。"""
        drafts = collect_drafts(held)
        results, statuses = {}, []
        check_started = time.time()
        if mode == 'unchecked':
            results.update({key: (UNAVAILABLE if i == 0 else '') + draft
                            for i, (key, draft) in enumerate(drafts.items())})
        elif mode == 'check':
            # 空白だけのパートは規則に反しようがないので、検査処理に渡さずにそのまま流す。本文の要素が複数あっても
            # 検査処理は 1 回だけ呼び、1〜3 を本文全体で判定させる。
            results.update({key: draft for key, draft in drafts.items() if not draft.strip()})
            keys = [key for key, draft in drafts.items() if draft.strip()]
            if keys:
                try:
                    self.check_status = None
                    texts = self.wait(self.check_answer, body, held, [drafts[key] for key in keys])
                    statuses.append(self.check_status)
                except Exception:
                    texts = [UNAVAILABLE + drafts[keys[0]], *[drafts[key] for key in keys[1:]]]
                    statuses.append('unchecked')
                results.update(zip(keys, texts))
        else:
            pool = concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(drafts)))
            try:
                # 空白だけのパートは規則に反しようがないので、検査役を起動せずにそのまま流す。
                results.update({key: draft for key, draft in drafts.items() if not draft.strip()})
                futures = {key: pool.submit(check_review, body, draft, self.checks) for key, draft in drafts.items()
                           if draft.strip()}
                while not all(f.done() for f in futures.values()):
                    concurrent.futures.wait(futures.values(), timeout=min(Settings.keepalive, 1.0))
                    self.keepalive_if_due()
                for key, future in futures.items():
                    try:
                        results[key], status = future.result()
                    except Exception:
                        results[key], status = UNAVAILABLE + drafts[key], 'unchecked'
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
                if self.silent_item and etype == 'response.completed':
                    obj['response']['end_turn'] = False
                for position, item in enumerate((obj.get('response') or {}).get('output') or []):
                    if isinstance(item, dict) and item.get('type') == 'message':
                        replace_item_text(item, item_key_of(item, position), results)
                raw = encode_event(etype, obj)
            if self.silent_item and isinstance(obj, dict):
                source, marker = self.silent_item
                changed = False
                if key == source:
                    if isinstance(obj.get('item'), dict):
                        obj['item']['id'] = marker
                        changed = True
                    if etype.startswith(TEXT_EVENT_PREFIXES):
                        obj['item_id'] = marker
                        changed = True
                if etype in ('response.completed', 'response.incomplete'):
                    for position, item in enumerate((obj.get('response') or {}).get('output') or []):
                        if isinstance(item, dict) and item.get('type') == 'message' and item_key_of(item, position) == source:
                            item['id'] = marker
                            changed = True
                if changed:
                    raw = encode_event(etype, obj)
            self.send_chunk(self.stripped(etype, obj, raw))
        record = self.result_record or {}
        log(event='checked', mode=mode, items=len(results), check_dur=round(time.time() - check_started, 3),
            engine=record.get('engine'), engine_failures=record.get('engine_failures') or [],
            dropped=len(record.get('dropped') or []),
            dropped_reasons=[d.get('reason') for d in record.get('dropped') or [] if isinstance(d, dict)],
            recheck=record.get('recheck'),
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


SELF_TEST_UNMET = '確認済みです。'
SELF_TEST_CHECKER = '''import json, sys
p = json.load(sys.stdin)
b = [t.replace("効く", "速い") for t in p["bodies"]]
r = {"status": "checked", "bodies": b, "text": "\\n\\n".join(b), "findings": [], "agent_message": None}
if p.get("final") and p.get("continuation") == "withhold" and "確認済み" in b[0]:
    r.update(bodies=None, text=None, agent_message="self-test", fallback_bodies=b, fallback_text=b[0],
             findings=[{"kind": "unverified_claim", "source": "draft", "excerpt": "確認済み", "evidence": []}])
print(json.dumps(r))
'''


def self_test():
    """偽の上流と偽の検査処理で、要求の処理経路 (訂正版の組み直し、未達の回答の notice への差し替えと、続けた
    要求での原文への戻し) と WebSocket の拒否を確かめる。上流や認証情報は使わない。"""
    checker = SCRIPT.parent / 'output-gate-check.py'
    try:
        compile(checker.read_text(encoding='utf-8'), str(checker), 'exec')
    except (SyntaxError, OSError, ValueError) as error:
        return False, f'checker does not compile: {error}'

    def stream_of(text):
        item = {'id': 'msg_t', 'type': 'message', 'role': 'assistant', 'status': 'completed',
                'content': [{'type': 'output_text', 'text': text, 'annotations': []}]}
        events = [{'type': 'response.output_item.added', 'output_index': 0, 'item': dict(item, content=[])},
                  {'type': 'response.output_text.delta', 'item_id': 'msg_t', 'output_index': 0, 'content_index': 0,
                   'delta': text},
                  {'type': 'response.output_text.done', 'item_id': 'msg_t', 'output_index': 0, 'content_index': 0,
                   'text': text},
                  {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
                  {'type': 'response.completed', 'response': {'id': 'r', 'status': 'completed', 'output': [item]}}]
        return b''.join(encode_event(e['type'], e) for e in events)

    answers, received = [SELF_TEST_TEXT, SELF_TEST_UNMET, 'ok'], []

    class Fake(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *a):
            pass

        def do_POST(self):
            received.append(self.rfile.read(int(self.headers.get('Content-Length') or 0)))
            stream = stream_of(answers.pop(0) if answers else 'ok')
            self.send_response(200)
            self.send_header('Content-Length', str(len(stream)))
            self.end_headers()
            self.wfile.write(stream)

    def post(port, payload, meta):
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=30)
        conn.request('POST', PREFIX + '/responses', json.dumps(payload).encode(),
                     {'x-codex-turn-metadata': json.dumps(meta)})
        text = conn.getresponse().read().decode('utf-8')
        conn.close()
        return text

    saved = (Settings.upstream, Settings.check_cmd, Settings.state_dir)
    fake = Server(('127.0.0.1', 0), Fake)
    relay = Server(('127.0.0.1', 0), Handler)
    try:
        threading.Thread(target=fake.serve_forever, daemon=True).start()
        threading.Thread(target=relay.serve_forever, daemon=True).start()
        Settings.upstream = urllib.parse.urlsplit(f'http://127.0.0.1:{fake.server_port}{PREFIX}')
        Settings.check_cmd = [sys.executable, '-I', '-c', SELF_TEST_CHECKER]
        # 動いている中継の状態 (登録・差し戻し) に試験の値を書かない。
        Settings.state_dir = Path(tempfile.mkdtemp(prefix='output-gate-selftest-'))
        body = post(relay.server_port, {'input': []}, {'request_kind': 'turn'})
        if 'これは速い。' not in body or SELF_TEST_TEXT in body:
            return False, 'the answer was not rebuilt with the checked text'
        (Settings.state_dir / 'continue').mkdir(parents=True, exist_ok=True)
        (Settings.state_dir / 'continue' / 'self-test').write_text('', encoding='utf-8')
        meta = {'request_kind': 'turn', 'session_id': 'self-test', 'turn_id': 'turn-1'}
        request = {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': 'q'}]}
        body = post(relay.server_port, {'input': [request]}, meta)
        state = read_json(gate_path('self-test', 'turn-1')) or {}
        if SELF_TEST_UNMET in body or not state.get('notice_marker') or state['notice_marker'] not in body:
            return False, 'the unmet answer was not replaced with the notice'
        notice = {'id': state['notice_marker'], 'type': 'message', 'role': 'assistant',
                  'content': [{'type': 'output_text', 'text': ''}]}
        hook = {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': '<hook_prompt>x</hook_prompt>'}]}
        post(relay.server_port, {'input': [request, notice, hook]}, meta)
        sent = json.loads(received[-1].decode('utf-8') if zstd is None else zstd.decompress(received[-1]))
        if SELF_TEST_UNMET not in [input_text(i) for i in sent['input']]:
            return False, 'the notice was not restored to the original in the continued request'
        conn = http.client.HTTPConnection('127.0.0.1', relay.server_port, timeout=10)
        conn.request('GET', PREFIX + '/responses', headers={'Connection': 'Upgrade', 'Upgrade': 'websocket'})
        status = conn.getresponse().status
        conn.close()
        if status != 426:
            return False, f'websocket upgrade answered {status}'
        return True, 'ok (rewrite, notice, restore, websocket)'
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
