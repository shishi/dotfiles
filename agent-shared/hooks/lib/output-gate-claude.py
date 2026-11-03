#!/usr/bin/env python3
"""出力ゲートの Claude Code 側の代わりの処理: output-gate-claude.sh display|prompt|stop から呼ぶ。

display (MessageDisplay hook):
  回答 (API の応答 1 つ) の行を、回答が終わるまで表示せずに貯める。最後の呼び出しで回答全体を共通の検査処理
  (output-gate-check.py) に渡し、訂正した文字列 (検査できなければ原文の先頭に理由) を表示する。
  会話記録の同じ応答の行の stop_reason が end_turn・stop_sequence の応答 (行が見つからない応答を含む) だけを
  最終回答とし、会話記録から組み立てた証拠と一緒に未達を判定させる。それ以外の応答は応答の規則だけを検査し、
  表示した文字列をターンの表示済みの文章として記録する。未達があれば未達を明記した版を表示し、エージェントへの
  指摘をセッションと回答の SHA-256 の組で保存する (Stop hook が差し戻す)。
  MessageDisplay は表示だけを置き換えるため、会話記録と Claude の文脈には原文が残る。訂正したときは
  訂正版を記録し、次の UserPromptSubmit で Claude に伝える。
prompt (UserPromptSubmit hook):
  記録した訂正版があれば、追加の文脈として渡して消す。mod の印も消す。
stop (Stop hook):
  last_assistant_message の組に指摘があり、まだ差し戻していなければ、block して同じセッションで直させる。
  検査中なら結果を待つ。1 つの組で差し戻すのは 1 回だけ。

mod が動いているセッション (mod が利用者の最新の入力より後に印を書いた)、委譲の子セッション、
副エージェントの回答では検査しない。mod と二重に検査しないため、また機械が読む出力を書き換えないため。
Claude Code 自身が作った回答 (API エラーの表示など) も、会話記録の行で見分けて検査しない。

環境変数:
  OUTPUT_GATE_CHECK_CMD  検査処理のコマンド (JSON 配列)。既定は同じ dotfiles の output-gate-check.py。
"""
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

HOOKS_DIR = Path(__file__).resolve().parent.parent
CHECK_SCRIPT = HOOKS_DIR.parent / 'bin' / 'output-gate-check.py'
UNCHECKED_PREFIX = '[出力ゲート: 検査できませんでした — {}]\n\n'
# 検査処理の全体の締切 (gitleaks を含めて既定 45 秒) と後始末 (最大 30 秒) より長くする。hook の時間制限はこれより長く設定する。
CHECK_TIMEOUT = 90
RECENT_MESSAGES = 10
# これより古いセッションの印と貯め置きは、利用者の入力のときに消す (日)。
OLD_STATE_DAYS = 7
# 会話記録を末尾から読むときの一回の大きさ (バイト。回答の出どころはこの範囲だけで探す) と、
# 回答の行が書かれるのを待つ上限 (秒)。
TAIL_BYTES = 1 << 20
RECORD_WAIT = 0.3
# 回答の最後の呼び出しが、並んで動く前の呼び出しの断片を待つ上限 (秒) と、別の呼び出しが決めた扱いを読むまで待つ上限 (秒)。
PARTS_WAIT = 2.0
DECIDE_WAIT = 0.5
# 回答ごとの錠を待つ上限 (秒) と、残った錠を捨てるまでの時間 (秒)。錠の中の処理はファイルの読み書きだけ。
LOCK_WAIT = 3.0
LOCK_STALE = 10.0
SAFE_NAME = re.compile(r'[A-Za-z0-9._-]{1,128}')
# 証拠を組み立てるために会話記録を末尾から読む上限 (バイト)。今のターンの始まりがこれより前なら、その範囲を
# 取得できなかった印にする。
READ_LIMIT = 32 << 20
# 前のターンの証拠を渡す範囲 (ターン数と、ターンの始まりからの秒数)。
PREVIOUS_TURNS = 10
PREVIOUS_SECONDS = 24 * 3600
FINAL_STOP_REASONS = ('end_turn', 'stop_sequence')
# Stop hook が「検査中」の印を見て結果を待つ上限 (秒)。settings.json の Stop hook の時間制限 (120 秒) より短くする。
STOP_WAIT = 100
# Stop hook が、印も結果も無いときに MessageDisplay hook が印を書くのを待つ上限 (秒)。どちらが先に動くかは
# 確かめていないため。
STOP_APPEAR_WAIT = 1.5
# これより古い「検査中」の印は、時間制限で止められた MessageDisplay hook の残りとして待たない (秒)。
CHECKING_STALE = CHECK_TIMEOUT + 30
# 表示済みの文章・直させた回数・組の結果を、利用者の入力のときに消すまでの時間 (秒)。
TURN_STATE_SECONDS = 24 * 3600
TRANSCRIPT_NOTE = ('Rebuilt from the Claude Code transcript (tool_use and toolUseResult); its shape differs from the '
                   'text the model received.')
NO_RESULT_NOTE = 'The transcript has no result for this call.'
GAP_NOTE = ("The transcript could not be read back to the user's latest input; calls made before the read range "
            'are missing.')


def state_root():
    base = os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local' / 'state')
    return Path(base) / 'output-gate'


def safe(name):
    return isinstance(name, str) and SAFE_NAME.fullmatch(name) and name not in ('.', '..')


def emit(output):
    # ASCII だけで出す。-I では PYTHONUTF8 が効かず、Windows のパイプは ANSI コードページになるため。
    print(json.dumps(output))


def content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return ''.join(block.get('text') or '' for block in content
                       if isinstance(block, dict) and block.get('type') == 'text')
    return ''


def lines_from_end(transcript_path, limit=None):
    """会話記録 (jsonl) の行を、新しい順に返す。会話記録は数百 MB になるため、末尾から必要な分だけ読む。
    limit を渡すと、末尾からおよそその大きさまでの行だけを返す。"""
    with Path(transcript_path).open('rb') as f:
        position = end = f.seek(0, os.SEEK_END)
        rest = b''
        while position > 0:
            size = min(TAIL_BYTES, position)
            position -= size
            f.seek(position)
            lines = (f.read(size) + rest).split(b'\n')
            rest = lines[0]   # 先頭の行は、次に読む前の部分とつなぐまで欠けているかもしれない
            yield from reversed(lines[1:])
            if limit is not None and end - position >= limit:
                return
        yield rest


def has_tool_result(content):
    return isinstance(content, list) and any(isinstance(block, dict) and block.get('type') == 'tool_result'
                                             for block in content)


def is_user_input(entry, content):
    """会話記録の user の行が利用者の入力か。ツールの結果、Claude Code が足す行 (Stop hook の指摘などの isMeta、
    compaction の要約)、利用者以外が出どころの行 (タスクの通知など) は入力ではない。"""
    if has_tool_result(content) or entry.get('isMeta') or entry.get('isCompactSummary'):
        return False
    origin = entry.get('origin')
    return not (isinstance(origin, dict) and origin.get('kind') not in (None, 'human'))


def message_texts(transcript_path):
    """会話記録から、利用者と Claude の直近 RECENT_MESSAGES 件の発言 (古い順) と、利用者の最新の発言を返す。
    ツールの結果と利用者の入力ではない行は除く。両方がそろうところまで末尾から読む。"""
    recent = []
    latest_user = None
    try:
        for line in lines_from_end(transcript_path):
            if len(recent) >= RECENT_MESSAGES and latest_user is not None:
                break
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            message = entry.get('message') if isinstance(entry, dict) else None
            role = message.get('role') if isinstance(message, dict) else None
            if role not in ('user', 'assistant') or role == 'user' and not is_user_input(entry, message.get('content')):
                continue
            text = content_text(message.get('content'))
            if not text.strip():
                continue
            if len(recent) < RECENT_MESSAGES:
                recent.append({'role': role, 'text': text})
            if role == 'user' and latest_user is None:
                latest_user = text
    except (OSError, TypeError, ValueError):
        pass   # 読めた分だけを渡す
    return recent[::-1], latest_user or ''


def squash(text):
    return re.sub(r'\s+', '', text)


def recorded_response(transcript_path, draft):
    """今のターンで draft と同じ文字列の応答 (同じ message.id の行の本文をつないだもの。空白の違いは見ない) を
    探し、(Claude Code 自身が作った応答か, stop_reason) を返す。見つからなければ None。探すのは最新の利用者の
    入力より後だけにする (前のターンの同じ文字列のエラーで、今の回答を見逃さないため)。"""
    want, current, texts, found = squash(draft), None, [], None
    for line in lines_from_end(transcript_path, limit=TAIL_BYTES):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get('message') if isinstance(entry, dict) else None
        if not isinstance(message, dict):
            continue
        if entry.get('type') == 'user':
            if is_user_input(entry, message.get('content')):
                break   # 今のターンの始まり
            continue
        if entry.get('type') != 'assistant':
            continue
        key = message.get('id') or object()   # id の無い行は、その行だけで 1 つの応答
        if key != current:
            if current is not None and squash(''.join(reversed(texts))) == want:
                return found
            # Claude Code は自分で作った回答 (API エラーの表示など) を、isApiErrorMessage を付けるか、
            # モデル名を <synthetic> にして書く。
            current, texts = key, []
            found = (entry.get('isApiErrorMessage') is True or message.get('model') == '<synthetic>',
                     message.get('stop_reason'))
        texts.append(content_text(message.get('content')))
    if current is not None and squash(''.join(reversed(texts))) == want:
        return found
    return None


def response_kind(transcript_path, draft):
    """回答が Claude Code 自身が作った文字列か (MessageDisplay の入力には出どころの欄が無い) と、会話記録の同じ
    応答の stop_reason を返す。行が見つからない・読めないときは (False, None) で、モデルの最終回答として検査する。

    SDK 経由 (Desktop など) の Claude Code は、自分で作った回答の行を書き始めてから MessageDisplay を呼ぶ
    (書き終わりは待たない)。書き終わるのを短く待つ。モデルの回答の行は、応答が終わるまで書かれないことがある。"""
    if not isinstance(transcript_path, str) or not transcript_path:
        return False, None
    deadline = time.monotonic() + RECORD_WAIT
    while True:
        try:
            found = recorded_response(transcript_path, draft)
        except OSError:
            return False, None
        if found is not None:
            return found
        if time.monotonic() >= deadline:
            return False, None
        time.sleep(0.05)


def evidence_item(call, found):
    """tool_use のブロックと、その結果 (tool_result のブロックと行の toolUseResult) から証拠の項目を作る。"""
    item = {'id': call['id'], 'tool': call.get('name') if isinstance(call.get('name'), str) else None}
    tool_input = call.get('input')
    if isinstance(tool_input, dict) and isinstance(tool_input.get('command'), str):
        item['command'] = tool_input['command']
    elif isinstance(tool_input, (dict, list, str)):
        item['input'] = tool_input
    if found is None:
        item.update(output=None, note=NO_RESULT_NOTE)
        return item
    block, record = found
    if record is None:
        output = content_text(block.get('content'))
    elif isinstance(record, str):
        output = record   # 失敗した Bash は 'Error: Exit code <n>' で始まる文字列
    elif isinstance(record, dict) and ('stdout' in record or 'stderr' in record):
        output = str(record.get('stdout') or '') + (f"\n[stderr]\n{record['stderr']}" if record.get('stderr') else '')
    else:
        output = json.dumps(record, ensure_ascii=False)
    item.update(output=output, note=TRANSCRIPT_NOTE)
    if block.get('is_error') is True or isinstance(record, str) and record.startswith('Error') or \
            isinstance(record, dict) and record.get('interrupted') is True:
        item['failed'] = True
    exit_code = re.match(r'Error: Exit code (\d+)', record) if isinstance(record, str) else None
    if exit_code:
        item['exit_code'] = int(exit_code.group(1))
    return item


def turn_key(entry, text):
    uuid = entry.get('uuid')
    if safe(uuid):
        return uuid
    return 'u-' + hashlib.sha256(f"{entry.get('timestamp')}\n{text}".encode('utf-8')).hexdigest()[:32]


def older_than(timestamp, seconds):
    try:
        when = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        return (datetime.now(timezone.utc) - when).total_seconds() > seconds
    except (AttributeError, TypeError, ValueError):
        return False


def read_turns(transcript_path, fallback_turn, max_turns=PREVIOUS_TURNS + 1):
    """会話記録を末尾から READ_LIMIT バイトまで読み、今のターン (利用者の最新の入力より後) と前のターンの
    ツールの呼び出しと結果から証拠を組み立てる。今のターンの始まりまで遡れなければ、証拠の先頭に取得できなかった
    範囲の印を置き、ターンの鍵には fallback_turn を使う。遡れなかった前のターンは含めない。"""
    turns, calls, results, answers, used, seen = [], [], {}, [], 0, set()
    try:
        for line in lines_from_end(transcript_path):
            used += len(line) + 1
            if used > READ_LIMIT:
                break
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            message = entry.get('message') if isinstance(entry, dict) else None
            if not isinstance(message, dict) or entry.get('isSidechain'):
                continue
            content = message.get('content')
            if entry.get('type') == 'assistant':
                # 末尾から読むので、行の中のブロックも逆順に溜め、ターンを閉じるときに戻す。
                for block in reversed(content if isinstance(content, list) else []):
                    if isinstance(block, dict) and block.get('type') == 'tool_use' and \
                            isinstance(block.get('id'), str) and block['id'] not in seen:
                        seen.add(block['id'])
                        calls.append(block)
                text, key = content_text(content), message.get('id')
                if text.strip():
                    if answers and key and answers[-1][0] == key:
                        answers[-1] = (key, text + answers[-1][1])
                    else:
                        answers.append((key, text))
            elif entry.get('type') == 'user':
                if has_tool_result(content):
                    for block in content:
                        if isinstance(block, dict) and block.get('type') == 'tool_result':
                            results.setdefault(block.get('tool_use_id'), (block, entry.get('toolUseResult')))
                elif is_user_input(entry, content):
                    text = content_text(content)
                    turns.append({'key': turn_key(entry, text), 'time': entry.get('timestamp'), 'user': text,
                                  'items': [evidence_item(c, results.get(c['id'])) for c in reversed(calls)],
                                  'answers': [t for _, t in reversed(answers)]})
                    calls, results, answers = [], {}, []
                    if len(turns) >= max_turns or len(turns) > 1 and older_than(turns[-1]['time'], PREVIOUS_SECONDS):
                        break
    except (OSError, TypeError, ValueError):
        pass   # 読めた範囲で組み立てる。今のターンの始まりまで読めていなければ印を付ける
    if not turns:
        items = [{'id': 'transcript-gap', 'unavailable': True, 'note': GAP_NOTE}]
        items += [evidence_item(c, results.get(c['id'])) for c in reversed(calls)]
        return {'key': fallback_turn, 'evidence': items, 'previous_evidence': [], 'turn_start_context': []}
    current, previous = turns[0], turns[1:]
    context = [{'role': 'user', 'text': current['user']}]
    if previous:   # 最新の入力の直前の 1 往復 (前の入力と、それへの回答)
        context = [{'role': 'user', 'text': previous[0]['user']},
                   *({'role': 'assistant', 'text': t} for t in previous[0]['answers'][-RECENT_MESSAGES:]), *context]
    return {'key': current['key'], 'evidence': current['items'], 'turn_start_context': context,
            'previous_evidence': [{'turn_id': t['key'], 'time': t['time'], 'items': t['items']} for t in previous
                                  if t['items'] and not older_than(t['time'], PREVIOUS_SECONDS)]}


def run_check(payload):
    """検査処理を起動して結果を返す。実行できなければ、原文の先頭に理由を添えた unchecked の結果を作る。"""
    command = json.loads(os.environ['OUTPUT_GATE_CHECK_CMD']) if os.environ.get('OUTPUT_GATE_CHECK_CMD') \
        else [sys.executable, '-I', str(CHECK_SCRIPT)]
    try:
        result = subprocess.run(command, input=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=CHECK_TIMEOUT)
        out = json.loads(result.stdout.decode('utf-8'))
        if result.returncode != 0 or not isinstance(out, dict) or not isinstance(out.get('text'), str) or \
                out.get('status') not in ('checked', 'unchecked') or \
                (out['status'] == 'unchecked' and not (isinstance(out.get('reason'), str) and out['reason'].strip())):
            raise ValueError('unexpected result')
        return out
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        reason = f'検査処理を実行できなかった ({type(error).__name__})'
        return {'status': 'unchecked', 'text': UNCHECKED_PREFIX.format(reason) + payload['draft'], 'reason': reason}


def pair_name(message):
    """Stop hook と組を引き合う鍵。回答の文字列から空白を除いた SHA-256 (会話記録の応答の照合と同じ規則)。"""
    return hashlib.sha256(squash(message).encode('utf-8')).hexdigest()


def latest_input_key(transcript_path):
    """会話記録の最新の利用者の入力の行から、ターンの鍵を作る。見つからなければ None。"""
    try:
        for line in lines_from_end(transcript_path):
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            message = entry.get('message') if isinstance(entry, dict) else None
            if isinstance(message, dict) and entry.get('type') == 'user' and \
                    is_user_input(entry, message.get('content')):
                return turn_key(entry, content_text(message.get('content')))
    except (OSError, TypeError, ValueError):
        pass
    return None


def append_log(path, record):
    try:
        with open(path, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'time': time.time(), **record}, ensure_ascii=False) + '\n')
    except OSError:
        pass


def write_json(path, value):
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
    os.replace(tmp, path)   # Stop hook が書きかけを読まないよう、置き換えで書く


def check(draft, event, session_dir, stop_reason):
    """回答を検査し、(表示する文字列, 検査の状態, 適用した置き換えの数, 表示に添えた未達の段落) を返す。最終回答では未達を判定させ、
    指摘を Stop hook へ渡す。直させた回数は Stop hook が block した時点で進める (途中の応答を最終回答と取り違えても
    回数を使い切らないため)。"""
    transcript_path = event.get('transcript_path')
    said, latest_user = message_texts(transcript_path)
    final = stop_reason in FINAL_STOP_REASONS or stop_reason is None
    turn = read_turns(transcript_path, None, PREVIOUS_TURNS + 1 if final else 1)
    if turn['key'] is None:   # 証拠は遡り切れなくても、ターンの鍵は最新の利用者の入力の行から作る
        turn['key'] = latest_input_key(transcript_path) or \
            ('t-' + event['turn_id'] if safe(event.get('turn_id')) else 'unknown-turn')
    shown_path = session_dir / f"{turn['key']}.shown"
    pair = pair_name(draft)
    payload = {'origin': 'claude', 'draft': draft, 'latest_user': latest_user, 'recent_messages': said,
               'final': final, 'cyber_program': None, 'round': 0}
    if final:
        try:
            record = json.loads((session_dir / f"{turn['key']}.round.json").read_text(encoding='utf-8'))
        except (OSError, ValueError):
            record = None
        try:
            shown_text = shown_path.read_text(encoding='utf-8').strip()
        except OSError:
            shown_text = ''
        payload.update(continuation='display', evidence=turn['evidence'], shown_text=shown_text,
                       previous_evidence=turn['previous_evidence'], turn_start_context=turn['turn_start_context'])
        if isinstance(record, dict) and record.get('round') == 1:   # Stop hook で差し戻した後の再検査
            payload.update(round=1, previous_findings=record.get('findings') or [])
    result = run_check(payload)
    text = result['text']
    engine = {key: result.get(key) for key in ('engine', 'engine_failures', 'dropped')}
    append_log(session_dir / 'check.log', {'pair': pair, 'turn': turn['key'], 'final': final, 'round': payload['round'],
                                           'status': result['status'], 'reason': result.get('reason'),
                                           'findings': len(result.get('findings') or []), **engine})
    if not final:
        try:   # 表示した文字列を、このターンの最終回答の検査に表示済みの文章として渡す
            with open(shown_path, 'a', encoding='utf-8', newline='') as f:
                f.write(text + '\n\n')
        except OSError:
            pass
    else:
        # 未達の無い結果・検査できなかった結果も、このターンのこの回答の結果として保存する。Stop hook は、前に同じ
        # 文字列の回答で残った結果ではなく、この結果を読む。
        findings = (result.get('findings') or []) if result['status'] == 'checked' else []
        message = result.get('agent_message') if findings and payload['round'] == 0 else None
        try:
            if message:
                (session_dir / f'{pair}.blocked').unlink(missing_ok=True)   # 前に同じ文字列で差し戻した印
            write_json(session_dir / f'{pair}.result', {'round': payload['round'], 'turn': turn['key'],
                                                        'status': result['status'], 'agent_message': message,
                                                        'findings': findings, **engine})
        except OSError:
            if message:
                # 指摘を Stop hook へ渡せないので直させない。原文に理由と未達の項目を添えた版を表示する。
                text = result.get('fallback_text') or text
    unmet = result.get('unmet_text') if isinstance(result.get('unmet_text'), str) else None
    return text, result['status'], result.get('applied') or 0, unmet


def mod_marker(session_id):
    """mod が動いたセッションの印。mod はモデルへの要求ごとに書き、利用者の入力のたびに prompt が消す。
    そのため、印があれば、mod は最新の入力の後のターンで動いている。印の中身 (mod のターンの識別子) は
    MessageDisplay の turn_id と別に作られる値なので、照合には使わない。"""
    return state_root() / 'claude-mod' / session_id


@contextmanager
def message_lock(path, wait=LOCK_WAIT):
    """同じ回答の呼び出しの間で、扱いの読み書き・断片の書き込み・組み立てを一つずつ行うための錠。
    Claude Code が止めた hook が残した錠は、LOCK_STALE 秒たったら捨てる。"""
    deadline = time.monotonic() + wait
    while True:
        try:
            os.close(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL))
            break
        except FileExistsError:
            try:
                if time.time() - path.stat().st_mtime > LOCK_STALE:
                    path.unlink(missing_ok=True)
                    continue
            except OSError:
                pass
            if time.monotonic() >= deadline:
                raise TimeoutError('回答の錠を取れなかった')
            time.sleep(0.01)
    try:
        yield
    finally:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass   # 残った錠は LOCK_STALE 秒で捨てられる


def decide(how, mod_runs):
    """回答を mod に任せる ('mod') か、この hook が貯めて検査する ('hold') かを、回答の最初に動いた呼び出しが
    決めて how に書く。錠の中で呼ぶ。シェルの早い経路は錠を取らずに 'mod' を作るため、作れなければ読む。
    最後の呼び出しが組み立てた後は 'done <組み立てに使った index>' になる。"""
    try:
        fd = os.open(how, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    except FileExistsError:
        deadline = time.monotonic() + DECIDE_WAIT
        while True:   # シェルが作った直後で、中身をまだ書いていないことがある
            value = how.read_text(encoding='utf-8').strip()
            if value or time.monotonic() >= deadline:
                return value or 'hold'
            time.sleep(0.02)
    value = 'mod' if mod_runs else 'hold'
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(value)
    return value


def assembled(how):
    """'done <index,...>' から、組み立てに使った index の集合を返す。"""
    _, _, used = how.partition(' ')
    return {int(i) for i in used.split(',') if i.isdigit()}


def present_parts(parts):
    found = {}
    for part in parts.glob('*.part'):
        if part.stem.isdigit() and part.is_file():
            found[int(part.stem)] = part.read_text(encoding='utf-8')
    return found


def gather(parts, how, lock, last):
    """index 0 から last までの断片が揃うまで (上限 PARTS_WAIT 秒) 待ち、錠の中で、手元の断片と組み立てに使う
    index を決めて how に書く。揃わなければ手元の断片だけを使い、揃わなかったことを返す。"""
    deadline = time.monotonic() + PARTS_WAIT
    while True:
        with message_lock(lock):
            found = present_parts(parts)
            complete = all(i in found for i in range(last + 1))
            if complete or time.monotonic() >= deadline:
                how.write_text('done ' + ','.join(str(i) for i in sorted(found)), encoding='utf-8')
                return ''.join(found[i] for i in sorted(found)), complete
        time.sleep(0.05)


def display(event, session_dir, mod_runs):
    message_id = event.get('message_id')
    if not safe(message_id):
        return
    delta = event.get('delta') or ''
    final = bool(event.get('final'))
    # 対話 CLI は回答 (API の応答 1 つ) の行を index 0 からの連番で渡し、最後の呼び出し (final) は 1 回だけで
    # index が最大になる。同じ回答の呼び出しを最大 3 件並べて動かし、final の後に同じ回答で呼ぶことはない。
    # SDK 経由は index 0 の final 1 回だけ (Claude Code 2.1.302 のソースで確認)。index が欠ければ 0 として扱う。
    index = event.get('index')
    if not isinstance(index, int) or isinstance(index, bool) or index < 0:
        index = 0
    how_path = session_dir / f'{message_id}.how'
    lock = session_dir / f'{message_id}.lock'
    parts = session_dir / message_id
    failure = None
    try:
        session_dir.mkdir(parents=True, exist_ok=True)
        # mod に任せるかは回答の最初に動いた呼び出しで決め、その回答の間は変えない。ターン中に送られた入力の
        # UserPromptSubmit が表示の途中で印を消しても、後半だけを貯めて検査しないため。扱いを読むことと
        # 断片を書くことを錠の中で行い、最後の呼び出しが組み立てた後に、組み立てに入らない断片を書かない。
        with message_lock(lock):
            how = decide(how_path, mod_runs)
            if how == 'hold':
                parts.mkdir(exist_ok=True)
                (parts / f'{index}.part').write_text(delta, encoding='utf-8', newline='')
    except OSError as error:
        if not final:
            return   # Claude Code はこの行をそのまま表示する。最後の呼び出しは、欠けた行として理由を添える
        how, failure = 'hold', error
    if how == 'mod':
        return
    if how.startswith('done'):
        # 最後の呼び出しが待ち切れずに組み立てた後で動いた呼び出し。組み立てに入っていない行は隠したままに
        # せず、そのまま見せる。
        shown = '' if index in assembled(how) else delta
        emit({'hookSpecificOutput': {'hookEventName': 'MessageDisplay', 'displayContent': shown}})
        return
    if not final:
        emit({'hookSpecificOutput': {'hookEventName': 'MessageDisplay', 'displayContent': ''}})
        return
    draft, gathered = delta, False
    try:
        if failure is not None:
            raise failure
        draft, complete = gather(parts, how_path, lock, index)
        gathered = True
        shutil.rmtree(parts, ignore_errors=True)   # 消せなければ古くなってから消す
        if not complete:
            # 原文を欠けたまま検査・表示しない。手元の原文全体に理由を添えて見せる。
            text = UNCHECKED_PREFIX.format('回答の一部の行が届かなかった') + draft
        elif not draft.strip():
            text = draft
        else:
            # 検査中の印。Stop hook はこれを見て結果を待つ。会話記録の行を待つ前に書き、Stop hook が先に動いても
            # 結果を待てるようにする。前に同じ文字列の回答で残した結果は、この回答の結果として読ませないよう消す。
            checking = session_dir / f'{pair_name(draft)}.checking'
            try:
                checking.write_text('', encoding='utf-8')
                (session_dir / f'{pair_name(draft)}.result').unlink(missing_ok=True)
            except OSError:
                pass
            try:
                synthetic, stop_reason = response_kind(event.get('transcript_path'), draft)
                if synthetic:   # モデルの回答ではない (Claude Code のエラー表示など) ので、検査せずに見せる
                    text, status, applied, unmet = draft, None, 0, None
                else:
                    text, status, applied, unmet = check(draft, event, session_dir, stop_reason)
            finally:
                try:
                    checking.unlink(missing_ok=True)
                except OSError:
                    pass
            if status == 'checked' and applied and text != draft:
                with open(session_dir / 'corrections.txt', 'a', encoding='utf-8', newline='') as f:
                    f.write(text + '\n\n')
            if status == 'checked' and unmet:   # 検査処理が表示に添えた未達の段落 (unmet_text)
                with open(session_dir / 'unmet.txt', 'a', encoding='utf-8', newline='') as f:
                    f.write(unmet + '\n\n')
    except Exception as error:  # 途中の行を出していないので、どんな失敗でも手元の原文に理由を添えて出す
        if not gathered:
            # 手元の行を集めて、表示に使う index を done として書く。後から動く前の index の呼び出しが、入っていない
            # 行をそのまま見せるようにするため。集めることと書くことは同じ錠の中で行い、その間に書かれた行を
            # 落とさない。錠を取れないときだけ、錠なしでできる限り行う。
            def settle():
                found = {index: delta}
                try:
                    found = {**present_parts(parts), index: delta}
                except (OSError, ValueError):
                    pass
                try:
                    how_path.write_text('done ' + ','.join(str(i) for i in sorted(found)), encoding='utf-8')
                except OSError:
                    pass
                return ''.join(found[i] for i in sorted(found))
            try:
                with message_lock(lock, wait=0.2):
                    draft = settle()
            except OSError:
                draft = settle()
        text = UNCHECKED_PREFIX.format(f'出力ゲートの処理が失敗した ({type(error).__name__})') + draft
    emit({'hookSpecificOutput': {'hookEventName': 'MessageDisplay', 'displayContent': text}})


def clean_old_state(current):
    """終わったセッションの印と、途中で止まった回答の貯め置きを消す。セッションの終わりを知る手段が
    無いため、利用者の入力のたびに、一定の日数より古いものだけを消す。"""
    limit = time.time() - OLD_STATE_DAYS * 86400
    for path in [*(state_root() / 'claude-mod').glob('*'), *(state_root() / 'claude-display').glob('*')]:
        if path.name == current:
            continue   # 今のセッションは、長く間を空けて再開した場合も残す (まだ渡していない訂正版があり得る)
        try:
            if path.stat().st_mtime >= limit:
                continue
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink(missing_ok=True)
        except OSError:
            continue   # 使用中などで消せないものは次の機会に回す


def prompt(session_dir):
    clean_old_state(session_dir.name)
    # 回答ごとの扱い (<message_id>.how) は最後の呼び出しの後も残す (並んで動いた前の呼び出しが後から読むことが
    # ある)。途中で止まった回答の断片・残った錠と合わせ、表示が終わって十分たったものを消す。
    leftovers = [*session_dir.glob('*.how'), *session_dir.glob('*.lock'), *session_dir.glob('*.tmp'),
                 *(p for p in session_dir.glob('*') if p.is_dir())]
    # ターンの表示済みの文章・直させた回数と、Stop hook と引き合う組は、長いターンの間も残す。
    turn_state = [*session_dir.glob('*.shown'), *session_dir.glob('*.round.json'), *session_dir.glob('*.result'),
                  *session_dir.glob('*.checking'), *session_dir.glob('*.blocked')]
    for path, age in [*((p, 3600) for p in leftovers), *((p, TURN_STATE_SECONDS) for p in turn_state)]:
        try:
            if path.stat().st_mtime < time.time() - age:
                shutil.rmtree(path) if path.is_dir() else path.unlink()
        except OSError:
            continue
    told = []
    for name, lead in (('corrections.txt', '[出力ゲート] 直前の回答は、表示する前に応答の規則で次のとおり訂正して'
                        '利用者に見せた。会話記録に残っている原文ではなく、この訂正版を自分の回答として扱うこと。'),
                       ('unmet.txt', '[出力ゲート] 直前の回答には、利用者に見せた未達の項目として次の文を添えて表示した。'
                        '利用者はこの項目を見ている。')):
        path = session_dir / name
        try:
            text = path.read_text(encoding='utf-8').strip()
            path.unlink(missing_ok=True)
        except OSError:
            continue
        if text:
            told.append(lead + '\n\n' + text)
    if told:
        emit({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': '\n\n'.join(told)}})


def stop_log(session_dir, pair, outcome, result=None):
    """Stop hook の判断を残す (実機で、組を引けたか・待ち切れたか・どの検査役の結果かを確かめるため)。"""
    record = {'pair': pair, 'outcome': outcome}
    if isinstance(result, dict):
        record.update({key: result.get(key) for key in ('turn', 'round', 'engine', 'engine_failures', 'dropped')})
    append_log(session_dir / 'stop.log', record)


def from_another_turn(result_path, current):
    """保存された結果が、今のターン (current) とは別のターンのものか。読めない結果は、読めないものとして後で扱う。"""
    try:
        result = json.loads(result_path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return False
    return isinstance(result, dict) and (not safe(result.get('turn')) or current is not None and result['turn'] != current)


def stop(event, session_dir):
    """Stop hook: 回答の組に指摘があり、まだ差し戻していなければ block する。stop_hook_active では決めない
    (別の Stop hook が先に block すると true になるが、出力ゲートの差し戻しはまだ行われていないため)。
    block する前に、組に block した印を書き、ターンの直させた回数を 1 にする。"""
    message = event.get('last_assistant_message')
    if not isinstance(message, str) or not message.strip():
        return
    pair = pair_name(message)
    result_path, checking = session_dir / f'{pair}.result', session_dir / f'{pair}.checking'
    current = latest_input_key(event.get('transcript_path')) if event.get('transcript_path') else None
    start = time.monotonic()
    while True:   # この回答の検査が終わる (検査中の印が消える) まで、残っている結果を読まない
        try:
            checking_now = time.time() - checking.stat().st_mtime < CHECKING_STALE
        except OSError:
            checking_now = False
        if not checking_now:
            # 前のターンの同じ本文の結果は「結果なし」として、今回の検査の印か結果が出るのを待つ。
            if result_path.exists() and not from_another_turn(result_path, current):
                break
            if time.monotonic() - start >= STOP_APPEAR_WAIT:   # MessageDisplay hook より先に動いた場合に備えた待ち
                stop_log(session_dir, pair, 'no result for this answer')
                return
        elif time.monotonic() - start >= STOP_WAIT:
            stop_log(session_dir, pair, 'the check did not finish in time')
            return
        time.sleep(0.1)
    try:
        result = json.loads(result_path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        stop_log(session_dir, pair, 'unreadable result')
        return
    if not isinstance(result, dict) or not isinstance(result.get('agent_message'), str) or not result['agent_message']:
        return   # 指摘の無い結果 (直させた後の再検査など)
    try:   # 作れた 1 回だけが block する
        os.close(os.open(session_dir / f'{pair}.blocked', os.O_WRONLY | os.O_CREAT | os.O_EXCL))
    except FileExistsError:
        return
    except OSError:
        stop_log(session_dir, pair, 'cannot write the blocked marker', result)
        return
    try:
        write_json(session_dir / f"{result['turn']}.round.json", {'round': 1, 'findings': result.get('findings') or []})
    except OSError:
        # 回数を残せないまま差し戻すと、次の回答をまた差し戻しうる。差し戻さずに終える。
        stop_log(session_dir, pair, 'cannot write the round', result)
        return
    stop_log(session_dir, pair, 'blocked', result)
    emit({'decision': 'block', 'reason': result['agent_message']})


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ''
    try:
        # -I では PYTHONUTF8 が効かず、Windows では標準入力が ANSI コードページで読まれるため、UTF-8 として復号する。
        event = json.loads(sys.stdin.buffer.read().decode('utf-8'))
    except ValueError:
        return
    session_id = event.get('session_id') if isinstance(event, dict) else None
    if not (state_root() / 'claude-enabled').exists():
        return   # このマシンでは出力ゲートを使っていない (output-gate-claude.sh enable で有効にする)
    if not safe(session_id) or os.environ.get('AGENT_DELEGATED_SESSION') == '1' or event.get('agent_id'):
        return
    session_dir = state_root() / 'claude-display' / session_id
    if mode == 'display':
        display(event, session_dir, mod_runs=mod_marker(session_id).exists())
    elif mode == 'prompt':
        # 以前 mod が動いたセッションを mod の無い環境で再開した場合に、古い印で検査を飛ばさないために消す。
        # mod が動いていれば、このあとのモデルへの要求で書き直す。
        try:
            mod_marker(session_id).unlink(missing_ok=True)
        except OSError:
            pass   # 消せなければ印が残り、mod の無い環境ではこのセッションを検査しない (次の入力で消し直す)
        prompt(session_dir)
    elif mode == 'stop' and not mod_marker(session_id).exists():
        stop(event, session_dir)   # mod が動いているセッションは、mod がツールへの差し替えで直させる


if __name__ == '__main__':
    main()
