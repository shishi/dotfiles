"""hook の発火判定テスト。期待値と実際を突き合わせて PASS/FAIL を出す。

コマンド行に検証用の文字列を直書きすると hook 自身に引っかかるため、ケースはこのファイルに置く。
"""

import json
import os
import subprocess
import sys

HOOKS = os.path.expanduser("~/.claude/hooks")
GUARD = os.path.join(HOOKS, "gh-body-file-guard.sh")
READBACK = os.path.join(HOOKS, "outward-write-readback.sh")

MULTILINE_PUSH = 'W="$TMPDIR/x"\nmkdir -p "$W"\ngit -C "$W" status --short\ngit -C "$W" push\n'
MULTILINE_GH = 'set -e\necho start\ngh pr create --title x --body-file /tmp/x.md\n'
HEREDOC_GH = "cat > f <<'EOF'\ngh pr create --body-file /tmp/x.md\nEOF\necho done"
HEREDOC_THEN_REAL = "cat > f <<'EOF'\nexample\nEOF\ngh pr edit 1 --body-file /tmp/x.md"

# (説明, hook, command, 発火してほしいか)
CASES = [
    ("実際の gh 起動でパス渡し", GUARD, "gh pr create --title x --body-file /tmp/x.md", True),
    ("stdin 指定", GUARD, "gh pr edit 1 --body-file -", False),
    ("printf の引数に文字列があるだけ",
     GUARD, "printf '%s' 'gh pr create --body-file /tmp/x.md' | bash hook.sh", False),
    ("ヒアドキュメント本文に出現", GUARD, HEREDOC_GH, False),
    ("ヒアドキュメントの後に実際の gh", GUARD, HEREDOC_THEN_REAL, True),
    ("複数行の 3 行目が実際の gh", GUARD, MULTILINE_GH, True),
    ("パイプの後段が実際の gh", GUARD, "echo hi | gh issue create --body-file /tmp/y.md", True),
    ("&& の後段が実際の gh", GUARD, "true && gh pr edit 1 --body-file /tmp/z.md", True),
    ("grep の検索語に出現", GUARD, "grep -rn 'gh pr create --body-file' .", False),
    ("gh だがパス渡しでない", GUARD, "gh pr view 1 --json body", False),

    ("readback: 出力に文字列があるだけ", READBACK, "grep -rn 'gh pr create' .", False),
    ("readback: 単一行の push", READBACK, "git push -u origin HEAD", True),
    ("readback: 複数行の末尾が push", READBACK, MULTILINE_PUSH, True),
    ("readback: push という語を含む別コマンド", READBACK, "echo 'git push origin master'", False),
    ("readback: 実際の gh pr edit", READBACK, "gh pr edit 21220 --body-file -", True),
    ("readback: 無関係コマンド", READBACK, "ls -la", False),
]


def run(hook, command):
    payload = json.dumps({"tool_input": {"command": command},
                          "tool_response": {"stdout": "ok"}})
    return subprocess.run(["bash", hook], input=payload, capture_output=True,
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
