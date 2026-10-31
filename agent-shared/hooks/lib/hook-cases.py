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
GUARD = os.path.join(HOOKS, "gh-body-file-guard.sh")
READBACK = os.path.join(HOOKS, "outward-write-readback.sh")

MULTILINE_PUSH = 'W="$TMPDIR/x"\nmkdir -p "$W"\ngit -C "$W" status --short\ngit -C "$W" push\n'
MULTILINE_GH = 'set -e\necho start\ngh pr create --title x --body-file /tmp/x.md\n'
HEREDOC_GH = "cat > f <<'EOF'\ngh pr create --body-file /tmp/x.md\nEOF\necho done"
HEREDOC_THEN_REAL = "cat > f <<'EOF'\nexample\nEOF\ngh pr edit 1 --body-file /tmp/x.md"
CLAUDE_STYLE_BODY = "gh pr create --title t --body \"$(cat <<'EOF'\n- Rename \"user's id\"\nEOF\n)\""
COMMIT_HEREDOC = "git commit -m \"$(cat <<'EOF'\nit's fine\nEOF\n)\""
COMMIT_THEN_PUSH = "git commit -m \"$(cat <<'EOF'\nx\nEOF\n)\" && git push origin HEAD"
COMMIT_MENTIONS_PUSH = 'git commit -m "x\ngit push origin main"'
# Codex on Windows の既定シェル。hook 入力にシェルの種別は無いので引数で渡す。
PS = ("--shell", "powershell")

# (説明, hook, command, 発火してほしいか[, hook への引数])
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
    ("引用内の <<EOF の次の行", GUARD, 'echo "use <<EOF here"\ngh pr create --body-file /tmp/x.md', True),
    ("here-string の次の行", GUARD, "tr a-z A-Z <<<hello\ngh pr create --body-file /tmp/x.md", True),
    ("先頭行のコメントの次の行", GUARD, "# body\ngh pr create --body-file /tmp/x.md", True),
    ("bash へ流すヒアドキュメント", GUARD, "bash <<'EOF'\ngh pr create --body-file /tmp/x.md\nEOF", True),
    # 以前の判定は本文を除くので、シェルが本文をスクリプトとして読む形を見逃していた (構文木で読む)
    ("bash -s へ流すヒアドキュメント", GUARD, "bash -s <<'EOF'\ngh pr create --body-file /tmp/x.md\nEOF", True),
    ("bash /dev/stdin へ流すヒアドキュメント", GUARD,
     "bash /dev/stdin <<'EOF'\ngh pr create --body-file /tmp/x.md\nEOF", True),
    ("source /dev/stdin へ流すヒアドキュメント", GUARD,
     "source /dev/stdin <<'EOF'\ngh pr create --body-file /tmp/x.md\nEOF", True),
    ("cat からパイプで bash へ流す本文", GUARD, "cat <<'EOF' | bash\ngh pr create --body-file /tmp/x.md\nEOF", True),
    ("未引用のヒアドキュメントの $(...) は外側が実行する", GUARD,
     "bash <<EOF\n$(gh pr create --body-file /tmp/x.md)\nEOF", True),
    ("= で値を渡す形", GUARD, "gh pr create --body-file=/tmp/x.md", True),
    ("短縮形 -F", GUARD, "gh issue create -F /tmp/x.md", True),
    ("gh release の -F", GUARD, "gh release create v1 -F notes.md", True),
    ("env -S で分割した gh", GUARD, "env -S 'gh pr create --body-file /tmp/x.md'", True),
    ("sudo の後ろの gh", GUARD, "sudo gh pr create --body-file /tmp/x.md", True),
    ("Claude 標準の本文渡し", GUARD, CLAUDE_STYLE_BODY, False),
    ("書き換え先の --body-file - の本文のバッククォート", GUARD,
     "gh pr create --body-file - <<'EOF'\nUse `gh pr create --body-file x` instead\nEOF", False),
    # 以前の判定 (b337715) は連結した行に正規表現を当てるので、--body の文字列の中も対象になる
    ("--body の文字列の中の --body-file", GUARD, 'gh pr create --body "--body-file x.md"', True),
    # 以前の判定へ渡す検出結果は旧シェルの $(...) と同じく NUL を除く
    ("NUL を挟んだ --body-file", GUARD, 'gh pr create --body "x\ngh pr create --bo\x00dy-file x.md\n"', True),
    ("無関係コマンド", GUARD, "git status", False),
    ("commit message のヒアドキュメント", GUARD, COMMIT_HEREDOC, False),
    # 以前の判定が分割できなければ止める
    ("閉じない引用", GUARD, "echo 'unterminated", True),
    # 構文木の側は値を取るオプションの値をオプションとして見ない。gh pr list の --template は出力の書式
    ("gh pr list --template の書式", GUARD, "gh pr list --template='{{.title}}'", False),
    ("--body の値の中の --body-file=", GUARD, 'gh pr create --body "--body-file=x.md"', False),
    ("構文エラーの手前の行の gh", GUARD, "gh pr create --body-file /tmp/x.md\nif", True),
    ("PowerShell: Windows パスの本文ファイル", GUARD, "gh pr create --body-file C:\\tmp\\x.md", True, PS),
    ("PowerShell: stdin 指定", GUARD, "gh pr create --body-file -", False, PS),
    ("PowerShell: バッククォートで退避した引用符", GUARD, 'Write-Output "x`"y"; gh pr view 1', True, PS),

    ("readback: 出力に文字列があるだけ", READBACK, "grep -rn 'gh pr create' .", False),
    ("readback: 単一行の push", READBACK, "git push -u origin HEAD", True),
    ("readback: 複数行の末尾が push", READBACK, MULTILINE_PUSH, True),
    ("readback: push という語を含む別コマンド", READBACK, "echo 'git push origin master'", False),
    ("readback: 実際の gh pr edit", READBACK, "gh pr edit 21220 --body-file -", True),
    ("readback: 無関係コマンド", READBACK, "ls -la", False),
    ("readback: commit message のヒアドキュメントの後の push", READBACK, COMMIT_THEN_PUSH, True),
    ("readback: 複数行の引数の中の git push", READBACK, COMMIT_MENTIONS_PUSH, False),
    ("readback: bash へ流すヒアドキュメントの push", READBACK, "bash <<'EOF'\ngit push origin HEAD\nEOF", True),
    ("readback: PowerShell の push", READBACK, "git push origin HEAD", True, PS),
    ("readback: commit message の本文の git push 行", READBACK,
     "git commit -F - <<'EOF'\nfix: x\ngit push origin main\nEOF", False),
    ("readback: python3 へ流すコードの中の git push (事後の検出は止めない)", READBACK,
     "python3 <<'EOF'\nprint('git push')\nEOF", False),
    ("readback: 入れ子の構文エラー", READBACK, "bash -c 'echo gh; if'", False),
]


def run(hook, command, args=()):
    payload = json.dumps({"tool_input": {"command": command},
                          "tool_response": {"stdout": "ok"}})
    return subprocess.run([BASH, hook, *args], input=payload.encode("utf-8"), capture_output=True,
                          timeout=60).stdout.decode("utf-8").strip()


def main():
    failed = 0
    for label, hook, command, should_fire, *args in CASES:
        out = run(hook, command, *args)
        fired = bool(out)
        ok = fired == should_fire
        failed += 0 if ok else 1
        detail = ""
        if fired:
            spec = json.loads(out)["hookSpecificOutput"]
            detail = spec.get("permissionDecision") or spec["additionalContext"][:45].replace("\n", " ")
        print(f"{'PASS' if ok else 'FAIL'}  {label}  (発火={fired}, 期待={should_fire}) {detail}")
    # gh release の -F は --notes-file。理由文の表記が実際のオプションと一致すること
    reason = json.loads(run(GUARD, "gh release create v1 -F notes.md") or "{}").get(
        "hookSpecificOutput", {}).get("permissionDecisionReason", "")
    if "--notes-file notes.md" not in reason:
        failed += 1
        print(f"FAIL  gh release の -F の理由文  ({reason[:80]})")
    # 以前の判定が分割できないときは、ヒアドキュメントの本文を除く前の (元のコマンドの) 行番号と引用符を理由に書く
    unclosed = "cat > f <<'EOF'\nbody\nEOF\necho 'x"
    reason = json.loads(run(GUARD, unclosed) or "{}").get("hookSpecificOutput", {}).get("permissionDecisionReason", "")
    if "4 行目の ' を閉じられない" not in reason or "対になる書き方" not in reason:
        failed += 1
        print(f"FAIL  分割できないときの理由文  ({reason[:120]})")
    context = json.loads(run(READBACK, unclosed) or "{}").get("hookSpecificOutput", {}).get("additionalContext", "")
    if "4 行目の ' を閉じられない" not in context:
        failed += 1
        print(f"FAIL  readback の分割できないときの理由文  ({context[:120]})")
    print(f"\n{len(CASES)} cases, {failed} failures")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
