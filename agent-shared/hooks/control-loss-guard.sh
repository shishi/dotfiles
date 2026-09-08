#!/usr/bin/env bash
# ユーザー操作なしでは元の操作可能状態へ戻せない状態変更を、明示許可なしでは通さない。
set -o pipefail

approval_ttl_seconds=600
approval_dir="${CONTROL_LOSS_GUARD_STATE_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/control-loss-guard-approvals-${UID:-user}}"
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
  local input prompt session lower kind tmp now
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

  kind=""
  if LC_ALL=C grep -Eq '^[[:space:]]*((android[[:space:]]*)?エミュレーター)(を)?[[:space:]]*(再起動|終了|停止)(を)?[[:space:]]*(して|してください|してくれ|しろ|せよ)[[:space:]。！!]*$|^[[:space:]]*(please[[:space:]]+)?(restart|stop|shut[[:space:]]+down)([[:space:]]+the)?[[:space:]]+(android[[:space:]]+)?emulator[[:space:].!]*$' <<<"$lower"; then
    kind="emulator"
  elif LC_ALL=C grep -Eq '^[[:space:]]*(画面|セッション|デスクトップ|display-manager|sddm|gdm|lightdm|rustdesk|ssh)(を)?[[:space:]]*(ロック|終了|停止|再起動|ログアウト)(を)?[[:space:]]*(して|してください|してくれ|しろ|せよ)[[:space:]。！!]*$|^[[:space:]]*(please[[:space:]]+)?(lock([[:space:]]+the)?[[:space:]]+screen|log[[:space:]]+out|terminate([[:space:]]+the)?[[:space:]]+session)[[:space:].!]*$' <<<"$lower"; then
    kind="session"
  elif LC_ALL=C grep -Eq '^[[:space:]]*(ネットワーク|通信|接続|networkmanager|tailscale)(を)?[[:space:]]*(切断|終了|停止|無効化)(を)?[[:space:]]*(して|してください|してくれ|しろ|せよ)[[:space:]。！!]*$|^[[:space:]]*(please[[:space:]]+)?(disconnect|disable|stop)([[:space:]]+the)?[[:space:]]+(network|connection|networkmanager|tailscale)[[:space:].!]*$' <<<"$lower"; then
    kind="network"
  fi
  [ -n "$kind" ] || exit 0

  now=$(date +%s) || exit 0
  tmp=$(mktemp "$approval_dir/.approval.XXXXXX") || exit 0
  if ! printf '%s %s\n' "$kind" "$now" >"$tmp" || ! chmod 600 "$tmp" || ! mv -f -- "$tmp" "$approval_path"; then
    rm -f -- "$tmp" 2>/dev/null || true
  fi
  exit 0
}

if [ "${1:-}" = "--record-approval" ]; then
  [ "$#" -eq 1 ] || exit 0
  record_approval
fi

deny() {
  jq -n --arg kind "${risk_kind:-不明}" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("この操作(" + $kind + ")はユーザー操作なしで元の操作可能状態へ戻せないため、現在のユーザーターンで対象が明示された場合だけ実行できます")}}'
  exit 0
}

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$command" ] || exit 0

py_bin=$(command -v python3 || command -v python) || py_bin=""
[ -n "$py_bin" ] || deny

risk_kind=$(printf '%s' "$command" | "$py_bin" -c '
import os
import shlex
import sys

src = sys.stdin.read()
separators = {";", "|", "||", "&", "&&", "(", ")"}

def executable(token):
    return os.path.basename(token.replace("\\", "/")).removesuffix(".exe").lower()

def strip_assignments(tokens):
    while tokens and "=" in tokens[0] and tokens[0].split("=", 1)[0].replace("_", "").isalnum():
        tokens = tokens[1:]
    return tokens

def unwrap(tokens):
    tokens = strip_assignments(tokens)
    while tokens:
        name = executable(tokens[0])
        if name in {"sudo", "doas"}:
            value_options = {"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt"}
            index = 1
            while index < len(tokens):
                option = tokens[index]
                if option == "--":
                    index += 1
                    break
                if option in value_options:
                    index += 2
                    continue
                if option.startswith("-"):
                    index += 1
                    continue
                break
            tokens = strip_assignments(tokens[index:])
            continue
        if name == "env":
            index = 1
            while index < len(tokens) and (tokens[index].startswith("-") or "=" in tokens[index]):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        if name in {"command", "nohup"}:
            index = 1
            while index < len(tokens) and tokens[index].startswith("-"):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        break
    return tokens

def classify(command, depth=0):
    if depth > 3:
        return "unknown"
    lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars="();|&")
    lexer.whitespace_split = True
    segments, current = [], []
    for token in list(lexer):
        if token in separators:
            if current:
                segments.append(current)
                current = []
        else:
            current.append(token)
    if current:
        segments.append(current)

    for segment in segments:
        segment = unwrap(segment)
        if not segment:
            continue
        name = executable(segment[0])
        args = [arg.lower() for arg in segment[1:]]
        if name == "adb" and ("reboot" in args or args[:2] == ["emu", "kill"]):
            return "emulator"
        if name == "loginctl" and any(arg in {"lock-session", "terminate-session", "terminate-user"} for arg in args):
            return "session"
        if name == "systemctl":
            actions = {"stop", "restart", "try-restart", "isolate"}
            session_units = {"display-manager", "sddm", "gdm", "lightdm", "rustdesk", "sshd"}
            network_units = {"networkmanager", "tailscaled"}
            units = {arg.removesuffix(".service") for arg in args}
            if actions.intersection(args) and session_units.intersection(units):
                return "session"
            if actions.intersection(args) and network_units.intersection(units):
                return "network"
        if name == "nmcli" and (args[:2] == ["networking", "off"] or args[:3] == ["radio", "all", "off"]):
            return "network"
        if name == "tailscale" and args[:1] == ["down"]:
            return "network"
        if name == "ip" and "link" in args and "down" in args:
            return "network"
        if name in {"bash", "sh", "zsh"}:
            for index, option in enumerate(segment[1:], start=1):
                if option.startswith("-") and "c" in option[1:] and index + 1 < len(segment):
                    nested = classify(segment[index + 1], depth + 1)
                    if nested:
                        return nested
                    break
    return ""

try:
    kind = classify(src)
except ValueError:
    sys.exit(2)
if kind:
    print(kind)
    sys.exit(0)
sys.exit(1)
')
status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) risk_kind="解析不能"; deny ;;
esac

consume_approval() {
  local consumed stored_kind epoch now age valid=1
  approval_path_for_session "$session" || return 1
  prepare_approval_dir || return 1
  [ -f "$approval_path" ] && [ ! -L "$approval_path" ] && [ -O "$approval_path" ] || return 1

  consumed="$approval_path.consume.$$"
  rm -f -- "$consumed" 2>/dev/null || return 1
  mv -- "$approval_path" "$consumed" 2>/dev/null || return 1
  if [ "$(wc -l <"$consumed" | tr -d ' ')" = 1 ] && IFS=' ' read -r stored_kind epoch <"$consumed"; then
    case "$epoch" in
      ""|*[!0-9]*) ;;
      *)
        now=$(date +%s) || now=0
        age=$((now - epoch))
        if [ "$stored_kind" = "$risk_kind" ] && [ "$age" -ge 0 ] && [ "$age" -le "$approval_ttl_seconds" ]; then
          valid=0
        fi
        ;;
    esac
  fi
  rm -f -- "$consumed" || return 1
  return "$valid"
}

consume_approval || deny
exit 0
