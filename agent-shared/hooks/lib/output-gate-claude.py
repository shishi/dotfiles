#!/usr/bin/env python3
"""出力ゲートの Claude Code 側の代わりの処理: output-gate-claude.sh display|prompt から呼ぶ。

display (MessageDisplay hook):
  回答の行を、回答が終わるまで表示せずに貯める。最後の呼び出しで回答全体を共通の検査処理
  (output-gate-check.py) に渡し、訂正した文字列 (検査できなければ原文の先頭に理由) を表示する。
  MessageDisplay は表示だけを置き換えるため、会話記録と Claude の文脈には原文が残る。訂正したときは
  訂正版を記録し、次の UserPromptSubmit で Claude に伝える。
prompt (UserPromptSubmit hook):
  記録した訂正版があれば、追加の文脈として渡して消す。mod の印も消す。

mod が動いているセッション (mod が利用者の最新の入力より後に印を書いた)、委譲の子セッション、
副エージェントの回答では検査しない。mod と二重に検査しないため、また機械が読む出力を書き換えないため。
Claude Code 自身が作った回答 (API エラーの表示など) も、会話記録の行で見分けて検査しない。

環境変数:
  OUTPUT_GATE_CHECK_CMD  検査処理のコマンド (JSON 配列)。既定は同じ dotfiles の output-gate-check.py。
"""
from contextlib import contextmanager
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
# 検査処理の中の締切 (gitleaks 30 秒 + 検査役 45 秒) と後始末の時間より長くする。hook の時間制限はこれより長く設定する。
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


def message_texts(transcript_path):
    """会話記録から、利用者と Claude の直近 RECENT_MESSAGES 件の発言 (古い順) と、利用者の最新の発言を返す。
    ツールの結果は除く。検査役に渡すのはこの二つだけなので、両方がそろうところまで末尾から読む。"""
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
            if role not in ('user', 'assistant'):
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


def recorded_origin(transcript_path, draft):
    """今のターンで draft と同じ文字列の回答の行を探し、Claude Code 自身が作った行なら True、モデルの行なら
    False、見つからなければ None を返す。探すのは最新の利用者の入力より後だけにする (前のターンの同じ文字列の
    エラーで、今の回答を見逃さないため)。"""
    for line in lines_from_end(transcript_path, limit=TAIL_BYTES):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get('message') if isinstance(entry, dict) else None
        if not isinstance(message, dict):
            continue
        content = message.get('content')
        if entry.get('type') == 'user':
            if not (isinstance(content, list) and any(isinstance(block, dict) and block.get('type') == 'tool_result'
                                                      for block in content)):
                return None   # ツールの結果ではない利用者の行 = 今のターンの始まり
        elif entry.get('type') == 'assistant' and content_text(content).strip() == draft.strip():
            # Claude Code は自分で作った回答 (API エラーの表示など) を、isApiErrorMessage を付けるか、
            # モデル名を <synthetic> にして書く。
            return entry.get('isApiErrorMessage') is True or message.get('model') == '<synthetic>'
    return None


def written_by_claude_code(transcript_path, draft):
    """回答が、モデルではなく Claude Code 自身が作った文字列か。MessageDisplay の入力には出どころの欄が無いため、
    会話記録の行の欄で決める。行が見つからない・読めないときはモデルの回答として扱い、検査する。

    SDK 経由 (Desktop など) の Claude Code は、自分で作った回答の行を書き始めてから MessageDisplay を呼ぶ
    (書き終わりは待たない)。書き終わるのを短く待つ。モデルの回答の行は、応答が終わるまで書かれないことがある。"""
    if not isinstance(transcript_path, str) or not transcript_path:
        return False
    deadline = time.monotonic() + RECORD_WAIT
    while True:
        try:
            origin = recorded_origin(transcript_path, draft)
        except OSError:
            return False
        if origin is not None:
            return origin
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.05)


def check(draft, transcript_path):
    said, latest_user = message_texts(transcript_path)
    payload = {'cli': 'claude', 'latest_user': latest_user, 'conversation': said, 'draft': draft, 'cyber_program': None,
               'compacted_note': False}
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
        return out['text'], out['status']
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        reason = f'検査処理を実行できなかった ({type(error).__name__})'
        return UNCHECKED_PREFIX.format(reason) + draft, 'unchecked'


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
        elif not draft.strip() or written_by_claude_code(event.get('transcript_path'), draft):
            text = draft   # モデルの回答ではない (Claude Code のエラー表示など) ので、検査せずにそのまま見せる
        else:
            text, status = check(draft, event.get('transcript_path'))
            if status == 'checked' and text != draft:
                with open(session_dir / 'corrections.txt', 'a', encoding='utf-8', newline='') as f:
                    f.write(text + '\n\n')
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
    for path in leftovers:
        try:
            if path.stat().st_mtime < time.time() - 3600:
                shutil.rmtree(path) if path.is_dir() else path.unlink()
        except OSError:
            continue
    path = session_dir / 'corrections.txt'
    try:
        corrections = path.read_text(encoding='utf-8').strip()
    except OSError:
        return
    path.unlink(missing_ok=True)
    if corrections:
        emit({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext':
              '[出力ゲート] 直前の回答は、表示する前に応答の規則で次のとおり訂正して利用者に見せた。'
              '会話記録に残っている原文ではなく、この訂正版を自分の回答として扱うこと。\n\n' + corrections}})


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


if __name__ == '__main__':
    main()
