#!/usr/bin/env bash
# OS の再起動は、そのユーザーターンで明示された場合だけ一度許可する。
set -o pipefail

approval_ttl_seconds=600
approval_dir="${REBOOT_GUARD_STATE_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/reboot-guard-approvals-${UID:-user}}"
approval_path=""

approval_path_for_session() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ] || return 1
  approval_path="$approval_dir/$1"
}

prepare_approval_dir() {
  umask 077
  if [ ! -e "$approval_dir" ]; then
    mkdir -p "$approval_dir" 2>/dev/null || return 1
  fi
  [ -d "$approval_dir" ] && [ ! -L "$approval_dir" ] && [ -O "$approval_dir" ] || return 1
  chmod 700 "$approval_dir" 2>/dev/null || return 1
}

record_approval() {
  local input prompt session lower tmp now
  input=$(cat)
  prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
  session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
  approval_path_for_session "$session" || exit 0
  prepare_approval_dir || exit 0

  rm -f -- "$approval_path" 2>/dev/null || exit 0
  case "$prompt" in *$'\n'*|*$'\r'*) exit 0 ;; esac
  lower=$(printf '%s' "$prompt" | LC_ALL=C tr '[:upper:]' '[:lower:]') || exit 0
  case "$lower" in
    *しない*|*するな*|*禁止*|*勝手に*|*"don't"*|*"do not"*|*never*) exit 0 ;;
  esac

  if ! LC_ALL=C grep -Eq '^[[:space:]]*((この|対象の)?(os|pc|マシン|端末|ホスト|コンピュータ)(を|の)?[[:space:]]*)?再起動(を)?[[:space:]]*(して|してください|してくれ|しろ|せよ)[[:space:]。！!]*$|^[[:space:]]*(please[[:space:]]+)?reboot([[:space:]]+(the[[:space:]]+)?(os|system|machine|host|computer|pc))?[[:space:].!]*$' <<<"$lower"; then
    exit 0
  fi

  now=$(date +%s) || exit 0
  tmp=$(mktemp "$approval_dir/.approval.XXXXXX") || exit 0
  if ! printf '%s\n' "$now" >"$tmp" || ! chmod 600 "$tmp" || ! mv -f -- "$tmp" "$approval_path"; then
    rm -f -- "$tmp" 2>/dev/null || true
  fi
  exit 0
}

if [ "${1:-}" = "--record-approval" ]; then
  [ "$#" -eq 1 ] || exit 0
  record_approval
fi

# 止めた理由に、どこから何として読んだか (本文・行ごとの読み・bash としての読み) と解析器の通知を添える
reason_suffix() {
  [ -n "${explanation:-}" ] && printf ' (根拠: %s)' "$explanation"
  [ -n "$notice" ] && printf ' (%s)' "$notice"
  return 0
}

deny() {
  jq -n --arg r "OSの再起動は、現在のユーザーターンで明示された場合だけ実行できます$(reason_suffix)" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# 判定できない呼び出しも止めるが、再起動と判定したわけではないことと、何が判定できなかったかを理由に書く。
undecidable() {
  jq -n --arg why "$1$(reason_suffix)" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("OSの再起動を含むか判定できず止めた: " + $why)}}'
  exit 0
}

# 対象外のコマンドは通す。解析器が無く簡易判定に戻したときだけ、その旨をユーザーに知らせる。
allow() {
  if [ "$notify" = 1 ] && [ -n "$notice" ]; then
    jq -n --arg m "[reboot-guard] $notice" '{systemMessage:$m}'
  fi
  exit 0
}

input=$(cat)
notice=""

py_bin=$(command -v python3 || command -v python) || py_bin=""
[ -n "$py_bin" ] || undecidable "python が見つからず解析できない。コマンドの書き換えでは直らない。python3 を PATH に入れること"

# 構文は本物の解析器 (shfmt / PowerShell の Parser) に任せる (lib/shell_commands.py)。
# ここでは実行される単純コマンドへ規則を当てるだけ。引数 --shell powershell は Codex on Windows 用。
result=$(printf '%s' "$input" | "$py_bin" -c '
import sys
sys.path[:] = [sys.argv.pop(1), *(p for p in sys.path if p)]  # 作業ディレクトリ ("") を外し、同名のモジュールを読まない
from shell_commands import executable, guard_main

def classify(commands):
    for tokens in commands:
        name = executable(tokens[0])
        arguments = [argument.lower() for argument in tokens[1:]]
        if name in {"reboot", "restart-computer"}:
            return "reboot"
        if name in {"systemctl", "loginctl"} and any(argument in {"reboot", "soft-reboot"} for argument in arguments):
            return "reboot"
        # Git Bash では /r がパスに変換されるのを避けて //r と書く
        options = [argument[1:] if argument.startswith("//") else argument for argument in arguments]
        if name == "shutdown" and any(option in {"-r", "/r", "--reboot"} for option in options):
            return "reboot"
    return ""

guard_main(classify, sys.argv[1:], head="reboot")
' "$(dirname "${BASH_SOURCE[0]}")/lib" "$@")
status=$?
if [ "$status" -ne 0 ] && ! "$py_bin" -c '' >/dev/null 2>&1; then
  undecidable "python を起動できない ($py_bin。Microsoft Store の別名など) ため解析できない。コマンドの書き換えでは直らない。起動できる python3 を PATH に入れること"
fi
[ "$status" -eq 0 ] || undecidable "判定処理 (hooks/lib/shell_commands.py) が異常終了した (終了コード $status)。hook 自身の不具合で、コマンドの書き換えでは直らない"
{ IFS= read -r verdict; IFS= read -r detail; IFS= read -r notice; IFS= read -r notify; IFS= read -r explanation; } <<<"$result"
case "$verdict" in
  none) allow ;;
  match) ;;
  undecidable) undecidable "$detail" ;;
  *) undecidable "判定処理の出力 ($verdict) を読めなかった。hook 自身の不具合で、コマンドの書き換えでは直らない" ;;
esac

consume_approval() {
  local consumed epoch now age valid=1
  approval_path_for_session "$session" || return 1
  prepare_approval_dir || return 1
  [ -f "$approval_path" ] && [ ! -L "$approval_path" ] && [ -O "$approval_path" ] || return 1

  consumed="$approval_path.consume.$$"
  rm -f -- "$consumed" 2>/dev/null || return 1
  mv -- "$approval_path" "$consumed" 2>/dev/null || return 1
  if [ "$(wc -l <"$consumed" | tr -d ' ')" = 1 ] && IFS= read -r epoch <"$consumed"; then
    case "$epoch" in
      ""|*[!0-9]*) ;;
      *)
        now=$(date +%s) || now=0
        age=$((now - epoch))
        if [ "$age" -ge 0 ] && [ "$age" -le "$approval_ttl_seconds" ]; then
          valid=0
        fi
        ;;
    esac
  fi
  rm -f -- "$consumed" || return 1
  return "$valid"
}

# jq の起動は Windows で 1 回約 70ms かかるため、承認の照合が要るときだけ読む。
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session=""
consume_approval || deny
exit 0
