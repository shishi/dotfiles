"""parser_tools の導入 lock と失敗の記録を確かめる (parser-fallback.test.sh から呼ぶ)。

導入コマンドは実行しない。導入中かは OS の排他ロックで決まること、二重に起動しないこと、
導入本体が死ねばロックが外れること、どの終わり方でも失敗の印を残すことを見る。
"""

import os
import shlex
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ["XDG_STATE_HOME"] = tempfile.mkdtemp()
os.environ["AGENT_GUARD_SHFMT_INSTALL_CMD"] = "unused"

import parser_tools  # noqa: E402

failures = 0


def check(label, ok, detail=""):
    global failures
    if not ok:
        failures += 1
        print(f"NG: {label} {detail}")


# 導入本体の代わりに RUN_LOCK を持ち続けるプロセス
HOLDER = f"""
import sys, time
sys.path.insert(0, {HERE!r})
import parser_tools
handle = parser_tools._open_lock(parser_tools.RUN_LOCK)
print("held" if parser_tools._try_lock(handle) else "busy", flush=True)
time.sleep(float(sys.argv[1]))
"""


def holder(seconds, env=None):
    process = subprocess.Popen([sys.executable, "-c", HOLDER, str(seconds)], stdout=subprocess.PIPE,
                               env=env or os.environ.copy())
    return process, process.stdout.readline().decode().strip()


# 2 プロセスが同時に取り合っても、取れるのは 1 つだけ
first, first_state = holder(3)
second, second_state = holder(0)
second.wait()
check("同時に取り合うと 1 つだけが取れる", (first_state, second_state) == ("held", "busy"), (first_state, second_state))
check("持っているプロセスが生きている間は導入中", parser_tools._held_by_other(parser_tools.RUN_LOCK))

spawned = []
parser_tools._spawn_detached = lambda argv, log: spawned.append(argv)


def fresh_install_status():
    parser_tools._install_status.clear()  # 別の hook (プロセス) として確かめ直す
    return parser_tools.ensure_install()


status = fresh_install_status()
check("導入中なら起動しない", "導入中" in status and not spawned, status)

# 導入本体が死ねば OS がロックを外すので、次の hook は導入を始められる
first.kill()
first.wait()
check("持っていたプロセスが死ねばロックは外れる", not parser_tools._held_by_other(parser_tools.RUN_LOCK))
status = fresh_install_status()
check("死んだ後は導入を始め、回数を記録する", "開始" in status and len(spawned) == 1 and "1 回目" in status, status)
parser_tools.ensure_install()
check("1 回の hook の中では導入を何度も起動しない", len(spawned) == 1, spawned)

# 並列に 3 つの hook が導入を確かめても、導入を実行する子は 1 つだけ。
# hook は子を待たないので子が複数起動することはあるが、RUN_LOCK を取れなかった子は何もせず終わる
race_state = tempfile.mkdtemp()
ran_log = os.path.join(race_state, "ran.txt").replace("\\", "/")
stub = f"import time; open({ran_log!r}, 'a').write('ran\\n'); time.sleep(3)"
start_at = time.time() + 2
racer = f"""
import sys, time
sys.path.insert(0, {HERE!r})
import parser_tools
while time.time() < {start_at}:
    pass
print(parser_tools.ensure_install())
"""
# 導入コマンドの差し替えは shlex で分けるので、Windows のパスも / で渡す
install_cmd = " ".join(shlex.quote(part) for part in [sys.executable.replace("\\", "/"), "-c", stub])
# 子が shfmt を見つけて導入をやめないよう、PATH と既知の場所から外す
env = dict(os.environ, XDG_STATE_HOME=race_state, AGENT_GUARD_SHFMT_INSTALL_CMD=install_cmd,
           PATH=os.path.dirname(sys.executable), HOME=race_state, SCOOP=race_state)
racers = [subprocess.Popen([sys.executable, "-c", racer], env=env, stdout=subprocess.PIPE) for _ in range(3)]
outputs = [process.communicate()[0].decode("utf-8", "replace") for process in racers]
race_lock = os.path.join(race_state, "agent-guards", parser_tools.RUN_LOCK)
for _ in range(100):  # 子の導入 (スタブは 3 秒) が終わり、RUN_LOCK が空くまで待つ
    time.sleep(0.1)
    with open(race_lock, "a+b") as handle:
        if os.path.exists(ran_log) and parser_tools._try_lock(handle):
            break
ran_count = len(open(ran_log).read().split()) if os.path.exists(ran_log) else 0
check("並列の 3 プロセスでも導入を実行する子は 1 つ", ran_count == 1, (ran_count, outputs))

# 導入本体は例外で終わっても失敗の印を残し、ロックを外す
failed = parser_tools.state_path("shfmt-install.failed")
real_resolve = parser_tools.resolve


def missing(tool):
    raise parser_tools.ParserUnavailable(tool, "見つからない", missing=True)


parser_tools.resolve = missing


def boom(tool, failed_path):
    raise KeyboardInterrupt


parser_tools._run_installers = boom
try:
    parser_tools.run_install()
    check("例外は呼び出し元へ送り直す", False)
except KeyboardInterrupt:
    pass
check("例外で終わっても失敗の印を残す", os.path.exists(failed))
check("終わればロックを外す", not parser_tools._held_by_other(parser_tools.RUN_LOCK))
status = fresh_install_status()
check("失敗の後は待つ", "再試行しない" in status, status)

# 導入本体はロックを取った後に、失敗の印と導入済みかを確かめ直す
ran = []
parser_tools._run_installers = lambda tool, failed_path: ran.append(tool) or 0
parser_tools.run_install()
check("直前の失敗の印があれば導入しない", not ran, ran)
os.remove(failed)
parser_tools.resolve = real_resolve
parser_tools.run_install()
check("導入済みなら導入しない", not ran, ran)

# nix の結果は実行ファイルを持つ出力を選ぶ
with tempfile.TemporaryDirectory() as out_dir:
    man = os.path.join(out_dir, "man")
    binary = os.path.join(out_dir, "bin-out", "bin", "shfmt")
    os.makedirs(man)
    os.makedirs(os.path.dirname(binary))
    open(binary, "w").close()
    chosen = parser_tools._nix_binary(f"{os.path.join(out_dir, 'bin-out')}\n{man}\n", "shfmt")
    check("nix の出力から bin/shfmt を持つものを選ぶ", chosen == binary, chosen)

sys.exit(1 if failures else 0)
