"""hook が使う構文解析器 (shfmt・PowerShell) の所在解決と、shfmt が無いときのバックグラウンド導入。

解決順: PATH → 以前の導入で記録したパス → 既知の場所 (scoop shims・nix profile・NixOS・homebrew 等)。
shfmt が見つからなければ導入をバックグラウンドで開始し、hook の応答は待たせない (呼び出し側は以前と同じ
近似の読みだけで判定し、ここで作る通知文をユーザーに見せる)。
PowerShell は導入しない。Windows には powershell.exe が常にあるため。それ以外の環境で PowerShell の本文
(入れ子の pwsh -c 等) があれば、構文木は最後まで読めなかったものとし、以前の判定に任せる。

導入の状態は ${XDG_STATE_HOME:-~/.local/state}/agent-guards/ に置く:
  shfmt-install.lock       導入本体が生きている間だけ OS の排他ロックを持つ (取れなければ導入中)
  shfmt-install.spawn.lock 導入本体を起動する hook が持つ OS の排他ロック (二重起動を防ぐ)
  shfmt-install.log        導入コマンドの出力
  shfmt-install.failed     失敗した時刻と理由 (FAILED_RETRY_SECONDS の間は再試行しない)
  shfmt-install.attempts   導入を始めた回数と最後の開始時刻 (成功で消す)
  shfmt-path               導入で得た実行ファイルのパス (nix build の結果など PATH に載らないもの)
  shfmt-nix                nix build の out-link (GC で消されないための root)

`python parser_tools.py install shfmt` が切り離して起動される導入本体。
導入コマンドは AGENT_GUARD_SHFMT_INSTALL_CMD で差し替えられる (テストのスタブ用)。
"""

import hashlib
import os
import shlex
import shutil
import subprocess
import sys
import time

TOOL = "shfmt"
LOCK_RETRY_SECONDS = 2
FAILED_RETRY_SECONDS = 3600
NOTICE_INTERVAL_SECONDS = 600
INSTALL_TIMEOUT_SECONDS = 1500


class ParserUnavailable(Exception):
    def __init__(self, tool, reason, missing=False):
        super().__init__(reason)
        self.tool = tool
        self.reason = reason
        self.missing = missing


def home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(home(), ".local", "state")
    return os.path.normpath(os.path.join(base, "agent-guards"))


def state_path(name):
    return os.path.join(state_dir(), name)


def _windows():
    return os.name == "nt"


# pwsh 7 を PATH と既知の場所の両方で先に探し、どちらにも無いときだけ Windows PowerShell 5.1 を使う
# (5.1 の構文解析器は && や三項演算子などの PowerShell 7 の構文を構文エラーにする)
NAMES = {"shfmt": ["shfmt"], "pwsh": ["pwsh", "powershell"]}


def _candidates(tool, name):
    user = os.environ.get("USER") or os.environ.get("USERNAME") or ""
    scoop = os.environ.get("SCOOP") or os.path.join(home(), "scoop")
    dirs = [
        os.path.join(scoop, "shims"),
        os.path.join(home(), ".nix-profile", "bin"),
        f"/etc/profiles/per-user/{user}/bin",
        "/run/current-system/sw/bin",
        "/nix/var/nix/profiles/default/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/home/linuxbrew/.linuxbrew/bin",
        os.path.join(home(), "go", "bin"),
    ]
    found = []
    if tool == TOOL:
        recorded = _read(state_path(f"{TOOL}-path"))
        if recorded:
            found.append(recorded)
    if name == "pwsh":
        found += [os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "PowerShell", "7", "pwsh.exe"),
                  "/opt/microsoft/powershell/7/pwsh", "/snap/bin/pwsh"]
    if name == "powershell":
        found.append(os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                                  "System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
    found += [os.path.join(directory, name + (".exe" if _windows() else "")) for directory in dirs]
    return found


_resolved = {}


def resolve(tool):
    if tool in _resolved:
        return _resolved[tool]
    for name in NAMES[tool]:
        for path in [shutil.which(name), *_candidates(tool, name)]:
            if path and os.path.isfile(path) and os.access(path, os.X_OK):
                _resolved[tool] = path
                return path
    label = "shfmt" if tool == TOOL else "PowerShell (pwsh / powershell.exe)"
    raise ParserUnavailable(tool, f"構文解析器の {label} が見つからない", missing=True)


# ---- shfmt の導入 ----

def _installers():
    override = os.environ.get("AGENT_GUARD_SHFMT_INSTALL_CMD")
    if override:
        return [("override", shlex.split(override))]
    found = []
    nix = shutil.which("nix") or next((p for p in ("/nix/var/nix/profiles/default/bin/nix",
                                                   "/run/current-system/sw/bin/nix") if os.path.exists(p)), None)
    if nix:
        found.append(("nix", [nix, "--extra-experimental-features", "nix-command flakes", "build",
                              "nixpkgs#shfmt", "--out-link", state_path(f"{TOOL}-nix"), "--print-out-paths"]))
    scoop = shutil.which("scoop")
    if _windows() and scoop:
        found.append(("scoop", [scoop, "install", "shfmt"]))
    brew = shutil.which("brew") or next((p for p in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew")
                                         if os.path.exists(p)), None)
    if brew:
        found.append(("brew", [brew, "install", "shfmt"]))
    return found


def _age(path):
    try:
        return time.time() - os.path.getmtime(path)
    except OSError:
        return None


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def _write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text + "\n")


SPAWN_LOCK = f"{TOOL}-install.spawn.lock"
RUN_LOCK = f"{TOOL}-install.lock"


def _open_lock(name):
    os.makedirs(state_dir(), exist_ok=True)
    return open(state_path(name), "a+b")


def _try_lock(handle):
    """OS の排他ロックを待たずに取る。取れれば True。ロックはファイルを閉じるかプロセスが終わると外れる。"""
    try:
        if _windows():
            import msvcrt

            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError:
        return False


def _held_by_other(name):
    """別のプロセスがロックを持っているか (導入中か)。"""
    with _open_lock(name) as handle:
        return not _try_lock(handle)


def _attempts():
    try:
        count, started = _read(state_path(f"{TOOL}-install.attempts")).split()
        return int(count), float(started)
    except ValueError:
        return 0, 0.0


def _failed_status(log):
    failed = state_path(f"{TOOL}-install.failed")
    age = _age(failed)
    if age is None or age >= FAILED_RETRY_SECONDS:
        return None
    count = _attempts()[0]
    tries = f"{count} 回試した。" if count else ""
    return (f"バックグラウンド導入に失敗した ({_read(failed) or '理由不明'})。{tries}"
            f"失敗から {FAILED_RETRY_SECONDS // 60} 分は再試行しない (ログ: {log})")


_install_status = []  # 1 回の hook (プロセス) で導入を何度も起動しないよう、最初の結果を使い回す


def ensure_install(tool=TOOL):
    if not _install_status:
        _install_status.append(_ensure_install())
    return _install_status[0]


def _ensure_install():
    """shfmt の導入の状態を一文で返す。導入中でも失敗直後でもなければ、ここでバックグラウンド導入を始める。

    導入本体は RUN_LOCK を生きている間だけ持つ。起動する hook は SPAWN_LOCK と RUN_LOCK を確かめるだけで、
    子を待たない。2 つの hook が同時に子を起動しても、RUN_LOCK を取れなかった子は何もせず終わる。
    子がすぐ失敗したときは、次の hook が失敗の印を見て理由を出す。
    """
    log = state_path(f"{TOOL}-install.log")
    failed_status = _failed_status(log)
    if failed_status:
        return failed_status
    try:
        spawn = _open_lock(SPAWN_LOCK)
    except OSError as error:
        return f"導入を開始できなかった (状態ディレクトリ {state_dir()} に書けない: {error})"
    with spawn:
        if not _try_lock(spawn) or _held_by_other(RUN_LOCK):
            return f"バックグラウンドで導入中 (ログ: {log})"
        count = _attempts()[0] + 1
        try:
            _write(state_path(f"{TOOL}-install.attempts"), f"{count} {time.time()}")
            _spawn_detached([sys.executable, os.path.abspath(__file__), "install", TOOL], log)
        except OSError as error:
            _write(state_path(f"{TOOL}-install.failed"), f"導入本体を起動できなかった: {error}")
            return f"導入を開始できなかった ({error})"
    return f"バックグラウンドで導入を開始した ({count} 回目。ログ: {log})"


def _spawn_detached(argv, log):
    """hook の終了や標準出力の close を待たせないよう、入出力を切り離して別セッションで起動する。"""
    with open(log, "ab") as output:
        options = dict(stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, close_fds=True)
        if _windows():
            create_no_window, new_group, breakaway = 0x08000000, 0x00000200, 0x01000000
            try:
                subprocess.Popen(argv, creationflags=create_no_window | new_group | breakaway, **options)
            except OSError:
                # hook を包む job が breakaway を許さない環境
                subprocess.Popen(argv, creationflags=create_no_window | new_group, **options)
        else:
            subprocess.Popen(argv, start_new_session=True, **options)


def run_install(tool=TOOL):
    # 出力先はログファイル。Windows の既定 (cp932) では書けない文字で落ちないようにする
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    failed = state_path(f"{TOOL}-install.failed")
    with _open_lock(RUN_LOCK) as lock:
        # hook が導入中かを確かめるために一瞬だけロックを取ることがあるので、取得は少しの間だけ再試行する
        until = time.monotonic() + LOCK_RETRY_SECONDS
        while not _try_lock(lock):
            if time.monotonic() >= until:
                print("別の導入が実行中のため終了する", flush=True)
                return 0
            time.sleep(0.05)
        # ロックを待つ間に別の導入が終わっていれば、その結果に従う
        if _failed_status(state_path(f"{TOOL}-install.log")):
            print("直前の導入が失敗しているため終了する", flush=True)
            return 0
        _resolved.pop(TOOL, None)
        try:
            print(f"{resolve(TOOL)} が見つかったため終了する", flush=True)
            return 0
        except ParserUnavailable:
            pass
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {TOOL} の導入を開始", flush=True)
        try:
            return _run_installers(TOOL, failed)
        except BaseException as error:
            # どの終わり方でも失敗の印を残す (印が無いと次の hook がすぐ再試行する)
            _write(failed, f"導入本体が異常終了した ({type(error).__name__}: {error})")
            raise


def _nix_binary(out, binary):
    for line in out.splitlines():
        candidate = os.path.join(line.strip(), "bin", binary)
        if line.strip() and os.path.isfile(candidate):
            return candidate
    return None


def _run_installers(tool, failed):
    installers = _installers()
    if not installers:
        _write(failed, "導入手段 (nix・scoop・brew) が見つからない。手動で導入すること")
        print("導入手段 (nix・scoop・brew) が見つからない", flush=True)
        return 1
    errors = []
    for name, argv in installers:
        print(f"$ {' '.join(argv)}", flush=True)
        try:
            proc = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                                  timeout=INSTALL_TIMEOUT_SECONDS)
        except (OSError, subprocess.TimeoutExpired) as error:
            errors.append(f"{name}: {error}")
            print(errors[-1], flush=True)
            continue
        out = proc.stdout.decode("utf-8", "replace")
        sys.stdout.write(out + proc.stderr.decode("utf-8", "replace"))
        if proc.returncode != 0:
            errors.append(f"{name}: 終了コード {proc.returncode}")
            continue
        if name == "nix":
            # --print-out-paths は複数の出力 (man 等) を返すことがある。実行ファイルを持つものを選ぶ
            binary = _nix_binary(out, TOOL)
            if binary:
                _write(state_path(f"{TOOL}-path"), binary)
        _resolved.pop(tool, None)
        try:
            resolve(tool)
        except ParserUnavailable:
            errors.append(f"{name}: 導入は成功したが実行ファイルが見つからない")
            continue
        for done in (failed, state_path(f"{TOOL}-install.attempts")):
            if os.path.exists(done):
                os.remove(done)
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 導入に成功", flush=True)
        return 0
    _write(failed, "; ".join(errors))
    return 1


# ---- 通知 ----

FALLBACK = "以前の判定 (b337715 と同じ) だけで判定した"


def unavailable_notice(error, consequence=FALLBACK):
    """解析器が使えないことの通知文。shfmt が無ければ導入の状態 (必要なら開始) を添える。"""
    status = ""
    if error.missing:
        status = ensure_install() if error.tool == TOOL else "PowerShell は自動導入しない"
    text = f"{error.reason}ため、{consequence}"
    return f"{text}。{status}" if status else text


def should_notify(notice):
    """同じ通知を毎回出さない。前回から NOTICE_INTERVAL_SECONDS 経つか、文面が変わったときだけ出す。"""
    key = hashlib.sha1(notice.encode("utf-8")).hexdigest()[:16]
    stamp = state_path(f"notice-{key}")
    age = _age(stamp)
    if age is not None and age < NOTICE_INTERVAL_SECONDS:
        return False
    try:
        os.makedirs(state_dir(), exist_ok=True)
        with open(stamp, "w", encoding="utf-8"):
            pass
    except OSError:
        pass
    return True


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "install" and sys.argv[2] == TOOL:
        sys.exit(run_install())
    sys.exit(2)
