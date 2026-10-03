#!/usr/bin/env bash
# 同一コマンド反復の警告・宣言による警告抑制と、数量上限が無い契約を検証する。
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/convergence-gate.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/converge-gate.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export CONVERGE_GATE_STATE_DIR="$TMP/state"

run() { # $1=command $2=session
  printf '{"session_id":"%s","tool_input":{"command":"%s"}}' "$2" "$1" | bash "$HOOK"
}
codex_patch() { # $1=patch $2=session
  jq -n --arg command "$1" --arg session "$2" \
    '{hook_event_name:"PreToolUse",tool_name:"apply_patch",session_id:$session,tool_input:{command:$command}}' \
    | bash "$HOOK"
}
warned() {
  jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and
    (.additionalContext | type == "string" and length > 0) and
    (has("permissionDecision") | not)' >/dev/null 2>&1 <<<"$1"
}

# 1. 同一コマンド 2 回までは許可
o1="$(run 'npm test' s1)"
o2="$(run 'npm test' s1)"
if [ -z "$o1" ] && [ -z "$o2" ]; then
  ok "first two identical runs pass"
else
  ng "first two identical runs pass"
fi

# 2. 変更を挟まない 3 回目以降は有効な additionalContext を出して通す
o3="$(run 'npm test' s1)"
o4="$(run 'npm test' s1)"
if warned "$o3" && warned "$o4" && grep -q '3 回目' <<<"$o3" && grep -q '4 回目' <<<"$o4"; then
  ok "repeated runs warn without denying and keep counting"
else
  ng "repeated runs warn without denying and keep counting"
fi

# 3. proceed 宣言後は警告を抑制
bash "$HOOK" proceed 'npm test' 'timeout 値を 30s へ変えたので今回は完走するはず' >/dev/null || true
out="$(run 'npm test' s1)"
if [ -z "$out" ]; then
  ok "declared repeat suppresses warnings"
else
  ng "declared repeat suppresses warnings"
fi

# 4. Codex の直接 apply_patch がカウンタをリセットする
run 'npm run build' s2 >/dev/null
run 'npm run build' s2 >/dev/null
codex_patch $'*** Begin Patch\n*** Update File: src/a.ts\n-const a=1\n+const a=2\n*** End Patch' s2 >/dev/null
out="$(run 'npm run build' s2)"
if [ -z "$out" ]; then
  ok "mutation resets the repeat counter"
else
  ng "mutation resets the repeat counter"
fi

# 5. 別セッションのカウンタは独立
run 'ruby test' s3a >/dev/null
run 'ruby test' s3a >/dev/null
run 'ruby test' s3a >/dev/null
out="$(run 'ruby test' s3b)"
if [ -z "$out" ]; then
  ok "sessions are isolated"
else
  ng "sessions are isolated"
fi

# 6. 期限切れの proceed 宣言は無効
run 'cargo build' s4 >/dev/null
run 'cargo build' s4 >/dev/null
bash "$HOOK" proceed 'cargo build' 'lockfile を更新したので依存解決が変わる' >/dev/null || true
for f in "$CONVERGE_GATE_STATE_DIR"/ok.*; do
  [ -e "$f" ] || continue
  printf '%s\t%s\n' "$(( $(date +%s) - 601 ))" "stale" >"$f"
done
out="$(run 'cargo build' s4)"
if warned "$out"; then
  ok "expired declaration restores warnings"
else
  ng "expired declaration restores warnings"
fi

# 7. レビューは従来の 2 周上限を超えても許可する
review() { printf '{"session_id":"%s","tool_input":{"skill":"%s"}}' "$2" "$1" | bash "$HOOK"; }
o1="$(review review-gate s5a)"
o2="$(review codex-review s5b)"
o3="$(review review-gate s5c)"
if [ -z "$o1" ] && [ -z "$o2" ] && [ -z "$o3" ]; then
  ok "reviews beyond former limit pass across sessions"
else
  ng "reviews beyond former limit pass across sessions"
fi

# 8. 通常編集も直接 patch も従来の延長込み 20 回上限を超えて通る
edit() { printf '{"session_id":"s6","tool_input":{"file_path":"/x/app.ts"}}' | bash "$HOOK"; }
all_allowed=1
for i in {1..21}; do
  e="$(edit)"
  p="$(codex_patch $'*** Begin Patch\n*** Update File: src/repeated.ts\n-x\n+y\n*** End Patch' s6)"
  [ -z "$e" ] && [ -z "$p" ] || all_allowed=0
done
if [ "$all_allowed" = 1 ]; then
  ok "edits and direct patches beyond former limits pass"
else
  ng "edits and direct patches beyond former limits pass"
fi

# 9. 通常編集は全セッションの反復カウンタをリセットする
run 'go test' s7a >/dev/null
run 'go test' s7a >/dev/null
run 'go test' s7b >/dev/null
run 'go test' s7b >/dev/null
edit >/dev/null
o1="$(run 'go test' s7a)"
o2="$(run 'go test' s7b)"
if [ -z "$o1" ] && [ -z "$o2" ]; then
  ok "ordinary edit resets command counters across sessions"
else
  ng "ordinary edit resets command counters across sessions"
fi

# 10. UserPromptSubmit は反復カウンタと proceed 宣言をリセットする
run 'cargo build' s8 >/dev/null
run 'cargo build' s8 >/dev/null
bash "$HOOK" proceed 'cargo build' '外部の依存解決が進んだので新しい情報を確認する' >/dev/null || true
printf '{"session_id":"s8","hook_event_name":"UserPromptSubmit","prompt":"続けて"}' | bash "$HOOK" >/dev/null
o1="$(run 'cargo build' s8)"
o2="$(run 'cargo build' s8)"
o3="$(run 'cargo build' s8)"
if [ -z "$o1" ] && [ -z "$o2" ] && warned "$o3"; then
  ok "user prompt resets counters and warning suppression"
else
  ng "user prompt resets counters and warning suppression"
fi

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
