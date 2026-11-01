#!/usr/bin/env python3
"""判定役を締切付きで実行する: run-judge.py <秒> <作業ディレクトリ> <コマンド> [引数...]

標準入力を判定役へ渡し、判定役の標準出力をそのまま出す。終了コードは判定役のもの。
締切を過ぎたら 124、コマンドが見つからなければ 127 で終える。

締切で止めるときはプロセスツリーごと終了する。Windows では codex の shim が孫プロセスを
起動し、直下の子だけを止めても孫が標準出力を握ったまま残り、呼び出し側が戻らないため。
"""
import os
import shutil
import signal
import subprocess
import sys

seconds, cwd, *command = sys.argv[1:]
executable = shutil.which(command[0])
if executable is None:
    sys.exit(127)
process = subprocess.Popen([executable, *command[1:]], cwd=cwd, stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           start_new_session=os.name != "nt")
try:
    out, _ = process.communicate(sys.stdin.buffer.read(), timeout=float(seconds))
except subprocess.TimeoutExpired:
    # 後始末に失敗しても締切の扱い (124) は変えない。判定役のパイプはこのプロセスだけが持つので、
    # 取り残された子孫がいても呼び出し側はここで戻れる。
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        else:
            os.killpg(process.pid, signal.SIGKILL)
    except (OSError, subprocess.SubprocessError):
        pass
    sys.exit(124)
sys.stdout.buffer.write(out)
sys.exit(process.returncode)
