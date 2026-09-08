#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/control-loss-guard.sh"
STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$STATE_DIR"' EXIT

export CONTROL_LOSS_GUARD_STATE_DIR="$STATE_DIR"

hook_input() {
  jq -cn --arg command "$1" '{session_id:"test-session",tool_name:"Bash",tool_input:{command:$command}}'
}

prompt_input() {
  jq -cn --arg prompt "$1" '{session_id:"test-session",prompt:$prompt}'
}

assert_denied() {
  local output
  output="$(hook_input "$1" | bash "$HOOK")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$output" >/dev/null
}

assert_allowed() {
  local output
  output="$(hook_input "$1" | bash "$HOOK")"
  [[ -z "$output" ]]
}

assert_denied 'adb emu kill'
assert_denied 'bash -c "adb reboot"'
assert_denied 'loginctl lock-session'
assert_denied 'nmcli networking off'

prompt_input 'Androidエミュレーターを再起動して' | bash "$HOOK" --record-approval
assert_allowed 'adb emu kill'
assert_denied 'adb emu kill'

prompt_input '画面をロックして' | bash "$HOOK" --record-approval
assert_allowed 'loginctl lock-session'
assert_denied 'loginctl lock-session'

prompt_input 'ネットワークを切断して' | bash "$HOOK" --record-approval
assert_allowed 'nmcli networking off'
assert_denied 'nmcli networking off'

prompt_input 'Androidエミュレーターを再起動して' | bash "$HOOK" --record-approval
assert_denied 'loginctl lock-session'

prompt_input '作業を続けて' | bash "$HOOK" --record-approval
assert_denied 'adb emu kill'

assert_allowed 'adb shell getprop sys.boot_completed'
assert_allowed 'systemctl --user restart rnnoise-microphone.service'

echo 'control-loss-guard tests passed'
