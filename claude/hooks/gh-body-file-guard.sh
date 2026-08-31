#!/bin/bash
# PreToolUse (Bash) hook: gh の本文をパス渡しするのを禁止し、stdin に強制する。
#
# 背景: sandbox の有無で $TMPDIR が別ディレクトリになるため、sandbox 内で書いた本文ファイルを
# sandbox 外の gh から読むとパスが解決されない。同名の残骸ファイルが存在すると gh はエラーを出さず
# 別内容の本文で PR を作成する (実例: PR #21220 に無関係な PR の本文が入った)。
# ヒアドキュメントを stdin に流せば中間ファイルが無くなり、この乖離は原理的に起きない。
#
# 対象はコマンド位置に現れた gh の呼び出しのみ (detect-invocation.py)。
# 解析できないコマンドは保守的に deny する。誤って block されても書き換えれば回復できるが、
# 別内容を投稿してしまう事故は投稿後に気づけないため。

input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# python の bin 名は環境で変わる(python3 / python)。能力で解決する
py_bin=$(command -v python3 || command -v python) || py_bin=""

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

[ -n "$py_bin" ] || exit 0
calls=$(printf '%s' "$input" | "$py_bin" "$HOME/.agent-shared/hooks/lib/detect-invocation.py" gh 2>/dev/null)
[ -z "$calls" ] && exit 0

if [ "$calls" = "EPARSE" ]; then
  deny "コマンドを解析できなかった (クォートが閉じていない可能性)。gh の呼び出しを含むため保守的に停止する。コマンドを整理して再実行すること。"
fi

offender=$(printf '%s' "$calls" | "$py_bin" -c '
import re, sys

for line in sys.stdin:
    if not re.match(r"\Agh\s+(pr|issue|release)\b", line.strip()):
        continue
    for opt in ("--body-file", "--notes-file", "--template"):
        m = re.search(re.escape(opt) + r"\s+(\S+)", line)
        if m and m.group(1) != "-":
            print(f"{opt} {m.group(1)}")
            sys.exit(0)
')

if [ -n "$offender" ]; then
  deny "gh に本文をパスで渡さないこと ($offender)。sandbox の有無で \$TMPDIR が変わり、別ディレクトリの残骸ファイルが読まれても gh はエラーにならない (PR #21220 で無関係な本文が投稿された)。ヒアドキュメントを stdin (- 指定) に流し込む形へ書き換えて再実行すること。"
fi

exit 0
