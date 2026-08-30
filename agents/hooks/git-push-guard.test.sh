#!/usr/bin/env bash
# 保護 branch の破壊防止と明示承認の主要契約だけを検証する。
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/git-push-guard.sh"
PASS=0
FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/git-push-guard.XXXXXX")" || exit 1
APPROVAL_DIR="$TMP/approvals"
mkdir "$APPROVAL_DIR"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

run_guard() {
  jq -n --arg command "$1" --arg session "${2:-none}" \
    '{tool_input:{command:$command},session_id:$session}' \
    | GIT_PUSH_GUARD_APPROVAL_DIR="$APPROVAL_DIR" bash "$HOOK"
}

expect_decision() {
  local description="$1" expected="$2" command="$3" session="${4:-none}" out decision
  out="$(run_guard "$command" "$session")"
  decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
  if [ "$decision" = "$expected" ]; then ok "$description"; else ng "$description"; fi
}

expect_allowed() {
  local description="$1" command="$2" session="${3:-none}" out
  out="$(run_guard "$command" "$session")"
  if [ -z "$out" ]; then ok "$description"; else ng "$description"; fi
}

record_approval() {
  jq -n --arg prompt "$1" --arg session "$2" '{prompt:$prompt,session_id:$session}' \
    | GIT_PUSH_GUARD_APPROVAL_DIR="$APPROVAL_DIR" bash "$HOOK" --record-approval
}

expect_decision "force push to main is denied" deny "git push --force origin main"
expect_decision "leading plus force refspec to main is denied" deny "git push origin +main"
expect_decision "deleting master is denied" deny "git push origin --delete master"
expect_decision "normal push to main asks" ask "git push origin main"
expect_allowed "feature force push is outside the protected boundary" \
  "git push --force origin feature/test"
expect_allowed "unrelated command is allowed" "git status"
expect_allowed "quoted push text is not executed" \
  "git commit -m 'never git push --force origin main'"

record_approval "mainにpushして" approved-main
expect_allowed "explicit user instruction authorizes one normal main push" \
  "git push origin main" approved-main

record_approval "mainにpushして" force-main
expect_decision "normal approval never authorizes a force push" deny \
  "git push --force origin main" force-main

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
