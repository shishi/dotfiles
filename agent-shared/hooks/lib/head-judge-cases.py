"""head_judge.py に凍結した以前の判定が、b337715 の本文から 1 文字も変わっていないことを確かめる。

本文の SHA-256 を照合する。b337715 を取得できる clone なら、git show の本文 (python -c の引数・ファイル全文) とも
直接照合する。
"""

import hashlib
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import head_judge  # noqa: E402

EXPECTED = {
    "HEAD_REBOOT": "7a46dcf1cea898566642d8d9fb0495bfe67b2292eb0f2e731ab5c401dec2a7b2",
    "HEAD_CONTROL_LOSS": "ec79cbc60a3c09103250e4d19f1e23c9619b9e4be9c2a146b174928d237b3dfa",
    "HEAD_GH_OFFENDER": "3c7f963f0aee20afe08f997b5344d1326db354594719fd78ea62f8c842b22c47",
    "HEAD_DETECT_INVOCATION": "b9dcb6f6f835b86c361348e26ad88854e7aada4509e18793a8055b0528013848",
}
# (定数名, b337715 のファイル, python -c の引数の直前の行の一部。None ならファイル全文)
ORIGINS = [
    ("HEAD_REBOOT", "reboot-guard.sh", "printf '%s' \"$command\" | \"$py_bin\" -c '"),
    ("HEAD_CONTROL_LOSS", "control-loss-guard.sh", "risk_kind=$(printf '%s' \"$command\" | \"$py_bin\" -c '"),
    ("HEAD_GH_OFFENDER", "gh-body-file-guard.sh", "offender=$(printf '%s' \"$calls\" | \"$py_bin\" -c '"),
    ("HEAD_DETECT_INVOCATION", "lib/detect-invocation.py", None),
]

failures = 0
for name, expected in EXPECTED.items():
    actual = hashlib.sha256(getattr(head_judge, name).encode("utf-8")).hexdigest()
    if actual != expected:
        failures += 1
        print(f"NG: {name} の本文が凍結した版と違う ({actual})")

repo = os.path.dirname(os.path.abspath(__file__))
for name, path, opener in ORIGINS:
    shown = subprocess.run(["git", "-C", repo, "show", f"b337715:agent-shared/hooks/{path}"], capture_output=True)
    if shown.returncode != 0:
        print(f"skip: b337715 を取得できないため {path} とは直接照合しない")
        continue
    text = shown.stdout.decode("utf-8")
    if opener is not None:
        start = text.index("\n", text.index(opener)) + 1
        text = text[start:text.index("\n'", start) + 1]
    if text != getattr(head_judge, name):
        failures += 1
        print(f"NG: {name} が b337715 の {path} と 1 文字以上違う")
# 以前の判定へ渡す入力の符号化: 以前の python -c は jq の UTF-8 のバイト列をこの環境の既定の符号化で読んでいた。
# §=1 reboot は cp932 で読むと前置代入 (ﾂｧ=1) として剥がされて止まり、UTF-8 で読むと剥がされずに通る。
# 同じ環境 (PYTHONUTF8=0 / 1) で、凍結した判定が以前の python -c と同じ結果になることを確かめる。
SAMPLE = "§=1 reboot"
for utf8 in ("0", "1"):
    env = dict(os.environ, PYTHONUTF8=utf8)
    original = subprocess.run([sys.executable, "-c", head_judge.HEAD_REBOOT], input=SAMPLE.encode("utf-8"),
                              env=env, capture_output=True).returncode
    frozen = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); import head_judge; "
                             "print(head_judge.reboot(sys.argv[2])[0])", repo, SAMPLE],
                            env=env, capture_output=True).stdout.decode().strip()
    expected = {0: "match", 1: "none"}.get(original, "undecidable")
    if frozen != expected:
        failures += 1
        print(f"NG: PYTHONUTF8={utf8} で凍結した判定 ({frozen}) が以前の python -c ({expected}) と違う")
print(f"head-judge: {len(EXPECTED)} 件, {failures} failures")
sys.exit(1 if failures else 0)
