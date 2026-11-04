#!/usr/bin/env python3
"""判定役を締切付きで実行する: run-judge.py <秒> <作業ディレクトリ> <コマンド> [引数...]

標準入力を判定役へ渡し、判定役の標準出力をそのまま出す。終了コードは判定役のもの。
締切を過ぎたら 124、コマンドが見つからなければ 127、判定役の認証が通らなければ 77、
判定役が失敗し、そのエラー出力が利用枠切れを報告していれば 75 で終える。

認証の失敗は、判定役 (codex) 自身のエラー出力が HTTP 401 を AUTH_FAILURES 回報告したことで判断する。
ログインが無効でも codex は 401 を受けながら 15 秒ほど再試行してから終わるため (実測)、待たずに止める。
codex は ChatGPT のログインで 401 を受けると、ログイン情報の読み直しとトークンの更新を 1 回ずつ試してから
失敗にする。最初の接続は 2 本並ぶことがあり (実測)、立ち直る場合でも 401 は 3 回まで出うるため、4 回目で止める。
codex exec は渡された入力をエラー出力にそのまま書き出す (実測)。入力 (会話や草稿) にある行は数えない。
利用枠切れは、判定役が 0 以外で終わり、エラー出力 (入力の行を除く) に LIMIT_ERROR の行があったことで判断する。
呼び出し側 (出力ゲートの検査処理) は、理由を利用枠切れとして記録し、別の系統の判定役へ移る。

締切や認証の失敗で止めるときはプロセスツリーごと終了する。Windows では codex の shim が孫プロセスを
起動し、直下の子だけを止めても孫が標準出力を握ったまま残り、呼び出し側が戻らないため。
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

AUTH_FAILED = 77
AUTH_FAILURES = 4
# codex のエラー行: "<時刻> ERROR codex_api::…: … HTTP error: 401 Unauthorized, url: …" と
# "ERROR: unexpected status 401 Unauthorized: …"。
AUTH_ERROR = re.compile(rb'\bERROR\b.*\b(?:HTTP error: |unexpected status )401\b')
LIMIT_REACHED = 75
# codex の利用枠切れの行: "ERROR: You've hit your usage limit. …"。
LIMIT_ERROR = re.compile(rb'\bERROR\b.*\b(?:usage limit|rate limit|429)\b', re.I)

seconds, cwd, *command = sys.argv[1:]
executable = shutil.which(command[0])
if executable is None:
    sys.exit(127)
process = None


def stop_tree():
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        else:
            os.killpg(process.pid, signal.SIGKILL)
    except (OSError, subprocess.SubprocessError):
        pass


def stop_judge(signum, _frame):
    # 呼び出し側が止められたとき (POSIX の TERM・HUP) も、別グループの判定役を残さない。
    if process is not None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except OSError:
            pass
    sys.exit(128 + signum)


if os.name != "nt":
    signal.signal(signal.SIGTERM, stop_judge)
    signal.signal(signal.SIGHUP, stop_judge)
process = subprocess.Popen([executable, *command[1:]], cwd=cwd, stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           start_new_session=os.name != "nt")
auth_failed = threading.Event()
limit_reached = threading.Event()
output = []


def feed(data):
    try:
        process.stdin.write(data)
        process.stdin.close()
    except OSError:   # 判定役が入力を読まずに終わった
        pass


def collect():
    output.append(process.stdout.read())


def watch_errors(given):
    # 認証の失敗が分かるまでは最後まで読み、判定役がエラー出力の書き込みで止まらないようにする。
    echoed = set(given.splitlines())
    failures = 0
    for line in process.stderr:
        if LIMIT_ERROR.search(line) and line.splitlines()[0] not in echoed:
            limit_reached.set()
        if AUTH_ERROR.search(line) and line.splitlines()[0] not in echoed:
            failures += 1
            if failures >= AUTH_FAILURES:
                auth_failed.set()
                return


given = sys.stdin.buffer.read()
threads = [threading.Thread(target=target, args=args, daemon=True)
           for target, args in ((feed, (given,)), (collect, ()), (watch_errors, (given,)))]
for thread in threads:
    thread.start()
deadline = time.monotonic() + float(seconds)
reader = threads[1]
# 標準出力が閉じ (判定役とその子孫が終わり)、判定役が終了するまで待つ。締切と認証の失敗はその間に見る。
# 標準出力を先に閉じて動き続ける判定役もあるため、終了を待つ間も締切を見る。
while reader.is_alive() or process.poll() is None:
    if auth_failed.is_set():
        stop_tree()
        sys.exit(AUTH_FAILED)
    if time.monotonic() >= deadline:
        # 後始末に失敗しても締切の扱い (124) は変えない。判定役のパイプはこのプロセスだけが持つので、
        # 取り残された子孫がいても呼び出し側はここで戻れる。
        stop_tree()
        sys.exit(124)
    if reader.is_alive():
        reader.join(0.05)
    else:
        time.sleep(0.05)
if auth_failed.is_set() and process.returncode != 0:
    sys.exit(AUTH_FAILED)
if process.returncode != 0:
    threads[2].join(1)   # エラー出力の最後の行まで読んでから利用枠切れを判断する
    if limit_reached.is_set():
        sys.exit(LIMIT_REACHED)
sys.stdout.buffer.write(output[0])
sys.exit(process.returncode)
