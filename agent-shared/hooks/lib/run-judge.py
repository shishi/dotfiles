#!/usr/bin/env python3
"""判定役を締切付きで実行する: run-judge.py [--keep-process-group] <秒> <作業ディレクトリ> <コマンド> [引数...]

標準入力を判定役へ渡し、判定役の標準出力をそのまま出す。終了コードは判定役のもの。
締切を過ぎたら 124、コマンドが見つからなければ 127 で終える。判定役のエラー出力は読み捨てる。

締切で止めるときはプロセスツリーごと終了する。Windows では CLI の shim が本体を孫プロセスとして
起動し、直下の子だけを止めても孫が標準出力を握ったまま残り、呼び出し側が戻らないため。
"""
import os
import shutil
import signal
import subprocess
import sys
import threading
import time

keep_process_group = sys.argv[1:2] == ["--keep-process-group"]
seconds, cwd, *command = sys.argv[2 if keep_process_group else 1:]
parent_pid = os.getppid()
executable = shutil.which(command[0])
if executable is None:
    sys.exit(127)
process = None


def stop_tree():
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        elif keep_process_group:
            process.kill()
        else:
            os.killpg(process.pid, signal.SIGKILL)
    except (OSError, subprocess.SubprocessError):
        pass


def stop_judge(signum, _frame):
    # 呼び出し側が止められたとき (POSIX の TERM・HUP) も、別グループの判定役を残さない。
    if process is not None:
        stop_tree()
    sys.exit(128 + signum)


if os.name != "nt":
    signal.signal(signal.SIGTERM, stop_judge)
    signal.signal(signal.SIGHUP, stop_judge)
process = subprocess.Popen([executable, *command[1:]], cwd=cwd, stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           start_new_session=os.name != "nt" and not keep_process_group)
output = []


def feed(data):
    try:
        process.stdin.write(data)
        process.stdin.close()
    except OSError:   # 判定役が入力を読まずに終わった
        pass


def collect():
    output.append(process.stdout.read())


def drain_errors():
    # 最後まで読み、判定役がエラー出力の書き込みで止まらないようにする。
    for _ in process.stderr:
        pass


given = sys.stdin.buffer.read()
threads = [threading.Thread(target=target, args=args, daemon=True)
           for target, args in ((feed, (given,)), (collect, ()), (drain_errors, ()))]
for thread in threads:
    thread.start()
deadline = time.monotonic() + float(seconds)
reader = threads[1]
# 標準出力が閉じ (判定役とその子孫が終わり)、判定役が終了するまで待つ。締切はその間に見る。
# 標準出力を先に閉じて動き続ける判定役もあるため、終了を待つ間も締切を見る。
while reader.is_alive() or process.poll() is None:
    if os.name != "nt" and os.getppid() != parent_pid:
        stop_tree()
        sys.exit(130)
    if time.monotonic() >= deadline:
        # 後始末に失敗しても締切の扱い (124) は変えない。判定役のパイプはこのプロセスだけが持つので、
        # 取り残された子孫がいても呼び出し側はここで戻れる。
        stop_tree()
        sys.exit(124)
    if reader.is_alive():
        reader.join(0.05)
    else:
        time.sleep(0.05)
sys.stdout.buffer.write(output[0])
sys.exit(process.returncode)
