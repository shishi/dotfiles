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

failures=0
# 期待と違っても止めずに全件を見るため、件名つきで記録する。4 番目以降は hook への引数 (--shell powershell 等)。
expect() {
  local want=$1 label=$2 command=$3 output got reason=""
  shift 3
  if [[ "${*: -1}" == reason=* ]]; then
    reason=${*: -1}
    reason=${reason#reason=}
    set -- "${@:1:$#-1}"
  fi
  output="$(hook_input "$command" | bash "$HOOK" "$@")"
  if [[ -n "$reason" ]] && ! jq -e --arg r "$reason" '.hookSpecificOutput.permissionDecisionReason | contains($r)' <<<"${output:-null}" >/dev/null; then
    echo "NG: $label (理由に「$reason」が無い) $output"
    failures=$((failures + 1))
  fi
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${output:-null}" >/dev/null; then
    got=deny
  else
    got=allow
  fi
  if [[ "$got" != "$want" ]]; then
    echo "NG: $label (期待=$want 実際=$got) $output"
    failures=$((failures + 1))
  fi
}

assert_denied 'adb emu kill'
assert_denied 'bash -c "adb reboot"'
assert_denied 'loginctl lock-session'
assert_denied 'nmcli networking off'

# 以前の判定が見つける形 (本文の行もコマンドとして読む)
expect deny 'sh へ流すヒアドキュメント' $'sudo sh <<\'EOF\'\nsystemctl stop NetworkManager\nEOF'
# 構文木の判定が見つける形 (以前の判定は対象なし)
expect deny 'コマンド置換の中' 'echo "$(adb emu kill)"'
expect deny '前置き: nix develop -c' 'nix develop --impure -c sudo systemctl stop sshd'
# 以前の判定が分割できなければ、構文木で対象が無くても止め、理由に閉じられない引用符の行と文字を書く
expect deny 'nix develop -c と Don\x27t' $'nix develop --impure -c sudo systemctl stop sshd\necho Don\'t' "reason=2 行目の ' を閉じられない"
expect deny 'cat へのヒアドキュメント本文の引用符' $'cat <<\'EOF\' > note.txt\ndon\'t stop\nEOF' "reason=2 行目の ' を閉じられない"
expect deny 'PowerShell: バッククォートで退避した引用符' 'Write-Output "a`"b"; adb devices' --shell powershell 'reason=1 行目の " を閉じられない'
expect deny '閉じない引用の後ろの # の行' $'cat <<\'EOF\' | bash\necho $\'it\\\'s\'\n# comment\ntailscale down\nEOF'
expect allow 'python3 へ流すコードの adb devices' $'python3 <<\'EOF\'\nimport subprocess; subprocess.run(["adb", "devices"])\nEOF'
# 以前の判定へ渡すコマンドは旧シェルと同じく NUL を除く
nul_output="$(printf '%s' '{"session_id":"test-session","tool_input":{"command":"cat <<\u0027EOF\u0027\ntail\u0000scale down\nEOF"}}' | bash "$HOOK")"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${nul_output:-null}" >/dev/null || { echo "NG: NUL を挟んだ本文の行 ($nul_output)"; failures=$((failures + 1)); }
[[ "$failures" -eq 0 ]]

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
