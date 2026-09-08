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

deny() {
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"OSの再起動は、現在のユーザーターンで明示された場合だけ実行できます"}}'
  exit 0
}

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$command" ] || exit 0

py_bin=$(command -v python3 || command -v python) || py_bin=""
[ -n "$py_bin" ] || deny

printf '%s' "$command" | "$py_bin" -c '
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
        command_name = executable(tokens[0])
        if command_name in {"sudo", "doas"}:
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
        if command_name == "env":
            index = 1
            while index < len(tokens) and (tokens[index].startswith("-") or "=" in tokens[index]):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        if command_name in {"command", "nohup"}:
            index = 1
            while index < len(tokens) and tokens[index].startswith("-"):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        break
    return tokens

def contains_reboot(command, depth=0):
    if depth > 3:
        return True
    nested = command.replace("\n", " ; ")
    lexer = shlex.shlex(nested, posix=True, punctuation_chars="();|&")
    lexer.whitespace_split = True
    nested_tokens = list(lexer)
    nested_segments = []
    current = []
    for token in nested_tokens:
        if token in separators:
            if current:
                nested_segments.append(current)
                current = []
        else:
            current.append(token)
    if current:
        nested_segments.append(current)

    for segment in nested_segments:
        segment = unwrap(segment)
        if not segment:
            continue
        command_name = executable(segment[0])
        arguments = [argument.lower() for argument in segment[1:]]
        if command_name in {"reboot", "restart-computer"}:
            return True
        if command_name in {"systemctl", "loginctl"} and any(argument in {"reboot", "soft-reboot"} for argument in arguments):
            return True
        if command_name == "shutdown" and any(argument in {"-r", "/r", "--reboot"} for argument in arguments):
            return True
        if command_name in {"bash", "sh", "zsh"}:
            for index, option in enumerate(segment[1:], start=1):
                if option.startswith("-") and "c" in option[1:] and index + 1 < len(segment):
                    if contains_reboot(segment[index + 1], depth + 1):
                        return True
                    break
    return False

try:
    if contains_reboot(src):
        sys.exit(0)
except ValueError:
    sys.exit(2)
sys.exit(1)
'
status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) deny ;;
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

consume_approval || deny
exit 0
