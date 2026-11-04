"""hook の発火判定テスト。期待値と実際を突き合わせて PASS/FAIL を出す。

コマンド行に検証用の文字列を直書きすると hook 自身に引っかかるため、ケースはこのファイルに置く。
"""

import json
import os
import shutil
import subprocess
import sys

HOOKS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Windows の CreateProcess は PATH より System32 の bash.exe(WSL)を先に選ぶ。
# PATH でも System32 が Git Bash より前にある場合は WSL になるため、Windows では Git Bash から実行する。
BASH = shutil.which("bash") or "bash"
READBACK = os.path.join(HOOKS, "outward-write-readback.sh")

MULTILINE_PUSH = 'W="$TMPDIR/x"\nmkdir -p "$W"\ngit -C "$W" status --short\ngit -C "$W" push\n'
COMMIT_THEN_PUSH = "git commit -m \"$(cat <<'EOF'\nx\nEOF\n)\" && git push origin HEAD"
COMMIT_MENTIONS_PUSH = 'git commit -m "x\ngit push origin main"'

# (説明, hook, command, 発火してほしいか)
CASES = [
    ("readback: 出力に文字列があるだけ", READBACK, "grep -rn 'gh pr create' .", False),
    ("readback: 単一行の push", READBACK, "git push -u origin HEAD", True),
    ("readback: 複数行の末尾が push", READBACK, MULTILINE_PUSH, True),
    ("readback: push という語を含む別コマンド", READBACK, "echo 'git push origin master'", False),
    ("readback: 実際の gh pr edit", READBACK, "gh pr edit 21220 --body-file -", True),
    ("readback: 無関係コマンド", READBACK, "ls -la", False),
    ("readback: commit message のヒアドキュメントの後の push", READBACK, COMMIT_THEN_PUSH, True),
    ("readback: 複数行の引数の中の git push", READBACK, COMMIT_MENTIONS_PUSH, False),
    ("readback: commit message の本文の git push 行", READBACK,
     "git commit -F - <<'EOF'\nfix: x\ngit push origin main\nEOF", False),
    ("readback: python3 へ流すコードの中の git push", READBACK,
     "python3 <<'EOF'\nprint('git push')\nEOF", False),
]


def run(hook, command):
    payload = json.dumps({"tool_input": {"command": command},
                          "tool_response": {"stdout": "ok"}})
    return subprocess.run([BASH, hook], input=payload, capture_output=True,
                          text=True, timeout=60).stdout.strip()


def main():
    failed = 0
    for label, hook, command, should_fire in CASES:
        out = run(hook, command)
        fired = bool(out)
        ok = fired == should_fire
        failed += 0 if ok else 1
        detail = ""
        if fired:
            spec = json.loads(out)["hookSpecificOutput"]
            detail = spec.get("permissionDecision") or spec["additionalContext"][:45].replace("\n", " ")
        print(f"{'PASS' if ok else 'FAIL'}  {label}  (発火={fired}, 期待={should_fire}) {detail}")
    print(f"\n{len(CASES)} cases, {failed} failures")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
