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
expect_decision "normal push to main requires an explicit instruction" deny "git push origin main"
expect_decision "feature push requires an explicit instruction" deny "git push origin feature/test"
expect_decision "feature force push requires an explicit instruction" deny \
  "git push --force origin feature/test"
expect_decision "tag push requires an explicit instruction" deny "git push --tags origin"

record_approval "pushして" approved-feature
expect_allowed "explicit push instruction authorizes one feature push" \
  "git push origin feature/test" approved-feature
expect_decision "push approval is consumed" deny "git push origin feature/test" approved-feature

record_approval "pushするな" forbidden-feature
expect_decision "a prohibition never authorizes a feature push" deny \
  "git push origin feature/test" forbidden-feature

record_approval "pushしても" incomplete-feature
expect_decision "an incomplete conditional is not push authorization" deny \
  "git push origin feature/test" incomplete-feature
record_approval "mainにpushしても" incomplete-main
expect_decision "an incomplete targeted conditional is not push authorization" deny \
  "git push origin main" incomplete-main

record_approval "mainにpushして" main-only
expect_decision "main approval does not authorize a feature push" deny \
  "git push origin feature/test" main-only
expect_decision "main approval does not authorize a mixed push" deny \
  "git push origin main feature/test" main-only

record_approval "mainとmasterにpushして" protected-only
expect_decision "protected branch approval does not authorize wildcard branches" deny \
  "git push origin 'refs/heads/*:refs/heads/*'" protected-only
expect_decision "protected branch approval does not authorize all branches" deny \
  "git push --all origin" protected-only

record_approval "pushして" explicit-main
expect_allowed "general push instruction authorizes a normal main push" \
  "git push origin main" explicit-main
record_approval "pushして" explicit-all
expect_allowed "general push instruction authorizes all branches" \
  "git push --all origin" explicit-all

expect_allowed "read-only Git operations stay allowed" "git status --short"

record_approval "mainにpushして" approved-main
expect_allowed "explicit user instruction authorizes one normal main push" \
  "git push origin main" approved-main

record_approval "mainにpushして" force-main
expect_decision "normal approval never authorizes a force push" deny \
  "git push --force origin main" force-main

record_approval "pushして" force-feature
expect_decision "normal approval never authorizes a feature force push" deny \
  "git push --force origin feature/test" force-feature

record_approval "pushして" force-tags
expect_decision "normal approval never authorizes a tag force push" deny \
  "git push --force --tags origin" force-tags

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
