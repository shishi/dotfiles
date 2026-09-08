#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/reboot-guard.sh"
STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$STATE_DIR"' EXIT

export REBOOT_GUARD_STATE_DIR="$STATE_DIR"

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

assert_denied 'sudo -n systemctl reboot --no-block'
assert_denied 'sudo -u root systemctl reboot'
assert_denied 'sudo env systemctl reboot'
assert_denied 'bash -c "systemctl reboot"'

prompt_input 'OSを再起動して' | bash "$HOOK" --record-approval
assert_allowed 'sudo -n systemctl reboot --no-block'
assert_denied 'sudo -n systemctl reboot --no-block'

prompt_input 'OSを再起動して' | bash "$HOOK" --record-approval
hook_input 'sudo -n systemctl reboot --no-block' | bash "$HOOK" >"$STATE_DIR/parallel-1" &
pid1=$!
hook_input 'sudo -n systemctl reboot --no-block' | bash "$HOOK" >"$STATE_DIR/parallel-2" &
pid2=$!
wait "$pid1"
wait "$pid2"
allowed=0
denied=0
for output in "$STATE_DIR/parallel-1" "$STATE_DIR/parallel-2"; do
  if [[ ! -s "$output" ]]; then
    allowed=$((allowed + 1))
  elif jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$output" >/dev/null; then
    denied=$((denied + 1))
  fi
done
[[ "$allowed" -eq 1 && "$denied" -eq 1 ]]

prompt_input 'OSを再起動して' | bash "$HOOK" --record-approval
prompt_input '作業を続けて' | bash "$HOOK" --record-approval
assert_denied 'sudo -n systemctl reboot --no-block'

prompt_input '再起動後も設定が残るか確認して' | bash "$HOOK" --record-approval
assert_denied 'sudo -n systemctl reboot --no-block'

prompt_input '再起動するな' | bash "$HOOK" --record-approval
assert_denied 'sudo -n systemctl reboot --no-block'

assert_allowed 'git status --short'

echo 'reboot-guard tests passed'
