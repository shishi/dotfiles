#!/bin/bash
# PreToolUse (Bash) hook: gh の本文をパス渡しするのを禁止し、stdin に強制する。
#
# 背景: agent の sandbox 内外で $TMPDIR が別ディレクトリになるため、sandbox 内で書いた本文ファイルを
# sandbox 外の gh から読むとパスが解決されないことがある。同名の残骸ファイルが存在すると gh は
# エラーを出さず別内容の本文で PR を作成する (実例: PR #21220 に無関係な本文が入った)。
# ヒアドキュメントを stdin に流せば中間ファイルが無くなり、この乖離は原理的に起きない。
#
# 対象は実際に実行される gh の呼び出しのみ。構文は本物の解析器 (shfmt / PowerShell の Parser) に任せる
# (lib/shell_commands.py)。引数 --shell powershell は Codex on Windows 用。
# 判定できないコマンドは理由を示して deny する。誤って block されても書き換えれば回復できるが、
# 別内容を投稿してしまう事故は投稿後に気づけないため。

input=$(cat)
notice=""

deny() {
  local reason=$1
  [ -n "${explanation:-}" ] && reason="$reason (根拠: $explanation)"
  [ -n "$notice" ] && reason="$reason ($notice)"
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

undecidable() {
  deny "gh に本文をパスで渡しているか判定できず止めた: $1"
}

# 対象外のコマンドは通す。解析器が無く簡易判定に戻したときだけ、その旨をユーザーに知らせる。
allow() {
  if [ "$notify" = 1 ] && [ -n "$notice" ]; then
    jq -n --arg m "[gh-body-file-guard] $notice" '{systemMessage:$m}'
  fi
  exit 0
}

# python の bin 名は環境で変わる(python3 / python)。能力で解決する
py_bin=$(command -v python3 || command -v python) || py_bin=""

# python が使えないときは以前と同じく止めないが、判定していないことを知らせる (同じ通知は 10 分に 1 回)
pass_unjudged() {
  local stamp="${XDG_STATE_HOME:-$HOME/.local/state}/agent-guards/notice-no-python-gh-body-file-guard"
  if [ -z "$(find "$stamp" -mmin -10 2>/dev/null)" ] && mkdir -p "${stamp%/*}" 2>/dev/null && : >"$stamp"; then
    jq -n --arg m "[gh-body-file-guard] $1ため、gh に本文をパスで渡しているかを判定せずに通した。起動できる python3 を PATH に入れること" '{systemMessage:$m}'
  fi
  exit 0
}
[ -n "$py_bin" ] || pass_unjudged "python が見つからない"

result=$(printf '%s' "$input" | "$py_bin" -c '
import sys
sys.path[:] = [sys.argv.pop(1), *(p for p in sys.path if p)]  # 作業ディレクトリ ("") を外し、同名のモジュールを読まない
from shell_commands import executable, guard_main

# 構文木の側は以前の判定の規則 (pr・issue・release の --body-file / --notes-file / --template) を語の列に当てる。
# 以前の判定が見逃す = の形と -F も見る。値を取るオプションの値 (--body "--body-file x" 等) はオプションとして見ず、
# --template は gh pr create のときだけ本文のファイルとして見る (issue create はテンプレート名、pr list は出力の書式)。
VALUE_OPTIONS = {"--body", "-b", "--title", "-t", "--json", "--jq", "-q", "--repo", "-R", "--base", "-B",
                 "--head", "-H", "--label", "-l", "--assignee", "-a", "--reviewer", "-r", "--milestone", "-m",
                 "--project", "-p"}

def classify(commands):
    for tokens in commands:
        if executable(tokens[0]) != "gh" or tokens[1:2] not in (["pr"], ["issue"], ["release"]):
            continue
        create = tokens[2:3] == ["create"]
        index = 2
        while index < len(tokens):
            token = tokens[index]
            if token in VALUE_OPTIONS:
                index += 2
                continue
            option, joined, value = token.partition("=")
            if option == "-F":
                # gh release の -F は --notes-file、pr / issue の -F は --body-file
                option = "--notes-file" if tokens[1] == "release" else "--body-file"
            # --template がファイルを指すのは gh pr create だけ (issue create はテンプレート名)
            if option in {"--body-file", "--notes-file"} or (option == "--template" and create and tokens[1] == "pr"):
                if not joined:
                    value = tokens[index + 1] if index + 1 < len(tokens) else ""
                if value and value != "-":
                    return f"{option} {value}"
            index += 1
    return ""

guard_main(classify, sys.argv[1:], head="gh")
' "$(dirname "${BASH_SOURCE[0]}")/lib" "$@")
status=$?
if [ "$status" -ne 0 ] && ! "$py_bin" -c '' >/dev/null 2>&1; then
  pass_unjudged "python を起動できない ($py_bin。Microsoft Store の別名など)"
fi
[ "$status" -eq 0 ] || undecidable "判定処理 (hooks/lib/shell_commands.py) が異常終了した (終了コード $status)。hook 自身の不具合で、コマンドの書き換えでは直らない"
{ IFS= read -r verdict; IFS= read -r offender; IFS= read -r notice; IFS= read -r notify; IFS= read -r explanation; } <<<"$result"
case "$verdict" in
  none) allow ;;
  match) ;;
  undecidable) undecidable "$offender" ;;
  *) undecidable "判定処理の出力 ($verdict) を読めなかった。hook 自身の不具合で、コマンドの書き換えでは直らない" ;;
esac

deny "gh に本文をパスで渡さないこと ($offender)。sandbox の有無で \$TMPDIR が変わり、別ディレクトリの残骸ファイルが読まれても gh はエラーにならない (PR #21220 で無関係な本文が投稿された)。本文は --body \"\$(cat <<'EOF' … EOF)\" のように引数で渡すか (本文に \" が無いとき)、ヒアドキュメントを stdin (- 指定) に流し込む形へ書き換えて再実行すること (本文に対にならない ' があると後者は再起動・操作不能化のガードが止める)。"
