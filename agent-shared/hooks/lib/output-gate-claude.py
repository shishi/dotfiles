#!/usr/bin/env python3
"""出力ゲートの Claude Code 側の代わりの処理: output-gate-claude.sh display|prompt から呼ぶ。

display (MessageDisplay hook):
  回答の行を、回答が終わるまで表示せずに貯める。最後の呼び出しで回答全体を共通の検査処理
  (output-gate-check.py) に渡し、訂正した文字列 (検査できなければ原文の先頭に理由) を表示する。
  MessageDisplay は表示だけを置き換えるため、会話記録と Claude の文脈には原文が残る。訂正したときは
  訂正版を記録し、次の UserPromptSubmit で Claude に伝える。
prompt (UserPromptSubmit hook):
  記録した訂正版があれば、追加の文脈として渡して消す。

mod が扱ったターンの回答 (mod が状態ディレクトリの印にターンの識別子を書く)、委譲の子セッション、
副エージェントの回答では検査しない。mod と二重に検査しないため、また機械が読む出力を書き換えないため。

環境変数:
  OUTPUT_GATE_CHECK_CMD  検査処理のコマンド (JSON 配列)。既定は同じ dotfiles の output-gate-check.py。
"""
import json
import os
from pathlib import Path
import re
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
SAFE_NAME = re.compile(r'[A-Za-z0-9._-]{1,128}')


def state_root():
    base = os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local' / 'state')
    return Path(base) / 'output-gate'


def safe(name):
    return isinstance(name, str) and SAFE_NAME.fullmatch(name) and name not in ('.', '..')


def emit(output):
    # ASCII だけで出す。-I では PYTHONUTF8 が効かず、Windows のパイプは ANSI コードページになるため。
    print(json.dumps(output))


def message_texts(transcript_path):
    """会話記録 (jsonl) から、利用者と Claude の発言の文字列を順に返す。ツールの結果は除く。"""
    texts = []
    try:
        lines = Path(transcript_path).read_text(encoding='utf-8').splitlines()
    except (OSError, TypeError, ValueError):
        return texts
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get('message') if isinstance(entry, dict) else None
        role = message.get('role') if isinstance(message, dict) else None
        if role not in ('user', 'assistant'):
            continue
        content = message.get('content')
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            text = ''.join(block.get('text') or '' for block in content
                           if isinstance(block, dict) and block.get('type') == 'text')
        else:
            text = ''
        if text.strip():
            texts.append({'role': role, 'text': text})
    return texts


def check(draft, transcript_path):
    said = message_texts(transcript_path)
    users = [m for m in said if m['role'] == 'user']
    payload = {'cli': 'claude', 'latest_user': users[-1]['text'] if users else '',
               'conversation': said[-RECENT_MESSAGES:], 'draft': draft, 'cyber_program': None,
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


def mod_handled(session_id, turn_id):
    """この回答のターンを mod が扱ったか。mod はモデルへの要求ごとに、印へ今のターンの識別子を書く。
    以前のターンの印は、mod の無い環境で同じセッションを再開した場合などに残るため、識別子で照合する。"""
    try:
        marked = (state_root() / 'claude-mod' / session_id).read_text(encoding='utf-8').strip()
    except (OSError, ValueError):
        return False
    return bool(marked) and marked == turn_id


def display(event, session_dir):
    message_id = event.get('message_id')
    if not safe(message_id):
        return
    held = session_dir / f'{message_id}.txt'
    session_dir.mkdir(parents=True, exist_ok=True)
    with open(held, 'a', encoding='utf-8', newline='') as f:
        f.write(event.get('delta') or '')
    if not event.get('final'):
        emit({'hookSpecificOutput': {'hookEventName': 'MessageDisplay', 'displayContent': ''}})
        return
    draft = held.read_text(encoding='utf-8')
    try:
        held.unlink(missing_ok=True)
    except OSError:
        pass   # 後始末に失敗しても表示は返す。残った貯め置きは古くなってから消す
    try:
        text, status = check(draft, event.get('transcript_path')) if draft.strip() else (draft, 'checked')
        if status == 'checked' and text != draft:
            with open(session_dir / 'corrections.txt', 'a', encoding='utf-8', newline='') as f:
                f.write(text + '\n\n')
    except Exception as error:  # 途中の行を出していないので、どんな失敗でも貯めた原文に理由を添えて出す
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
                for child in path.iterdir():
                    child.unlink(missing_ok=True)
                path.rmdir()
            else:
                path.unlink(missing_ok=True)
        except OSError:
            continue   # 使用中などで消せないものは次の機会に回す


def prompt(session_dir):
    clean_old_state(session_dir.name)
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
    if mod_handled(session_id, event.get('turn_id')):
        return
    session_dir = state_root() / 'claude-display' / session_id
    if mode == 'display':
        display(event, session_dir)
    elif mode == 'prompt':
        prompt(session_dir)


if __name__ == '__main__':
    main()
