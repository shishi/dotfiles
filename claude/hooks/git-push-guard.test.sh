#!/usr/bin/env bash
# git-push-guard.sh の単体テスト。tool_input JSON を stdin 経由で渡し、
# deny (permissionDecision:"deny" 付き JSON 出力) / allow (無出力) を検証する。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/git-push-guard.sh"
PASS=0; FAIL=0

run_guard() { # $1=command
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK"
}

assert_denied() { # $1=desc $2=command
  out=$(run_guard "$2"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = "deny" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_allowed() { # $1=desc $2=command
  out=$(run_guard "$2"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_denied "force push denied" "git push --force origin main"
assert_denied "push to master denied" "git push origin master"
assert_allowed "normal push allowed" "git push origin main"
assert_allowed "unrelated command allowed" "echo hello"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
