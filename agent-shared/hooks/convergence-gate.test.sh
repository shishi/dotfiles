#!/usr/bin/env bash
# 変更を挟まない同一コマンドの反復を deny し、proceed 宣言後だけ許可する契約を検証する。
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
denied() { grep -q '"permissionDecision": *"deny"' <<<"$1"; }

# 1. 同一コマンド 2 回までは許可
o1="$(run 'npm test' s1)"
o2="$(run 'npm test' s1)"
if [ -z "$o1" ] && [ -z "$o2" ]; then
  ok "first two identical runs pass"
else
  ng "first two identical runs pass"
fi

# 2. 変更を挟まない 3 回目は deny
out="$(run 'npm test' s1)"
if denied "$out"; then
  ok "third identical run without mutation is denied"
else
  ng "third identical run without mutation is denied"
fi

# 3. proceed 宣言後は許可
bash "$HOOK" proceed 'npm test' 'timeout 値を 30s へ変えたので今回は完走するはず' >/dev/null || true
out="$(run 'npm test' s1)"
if [ -z "$out" ]; then
  ok "declared repeat is allowed"
else
  ng "declared repeat is allowed"
fi

# 4. ファイル変更(apply_patch)がカウンタをリセットする
run 'npm test' s2 >/dev/null
run 'npm test' s2 >/dev/null
run 'apply_patch <<EOF\n*** Begin Patch\n*** Update File: src/a.ts\n-const a=1\n+const a=2\n*** End Patch\nEOF' s2 >/dev/null
out="$(run 'npm test' s2)"
if [ -z "$out" ]; then
  ok "mutation resets the repeat counter"
else
  ng "mutation resets the repeat counter"
fi

# 5. 別セッションのカウンタは独立
out="$(run 'npm test' s3)"
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
  printf '%s\t%s\n' "$(( $(date +%s) - 100000 ))" "stale" >"$f"
done
out="$(run 'cargo build' s4)"
if denied "$out"; then
  ok "expired declaration is invalid"
else
  ng "expired declaration is invalid"
fi

# 7. レビュー系 skill は 2 周まで、3 周目は deny(自己解除なし)。
#    予算は worktree 共有なので session が毎回違っても数える
review() { printf '{"session_id":"%s","tool_input":{"skill":"%s"}}' "$2" "$1" | bash "$HOOK"; }
o1="$(review review-gate s5a)"
o2="$(review codex-review s5b)"
o3="$(review review-gate s5c)"
if [ -z "$o1" ] && [ -z "$o2" ] && denied "$o3"; then
  ok "third review round is denied across sessions"
else
  ng "third review round is denied across sessions"
fi

# 8-11. 同一ファイル churn 予算(テストは free=2 に絞って検証)
export CONVERGE_GATE_CHURN_FREE=2
edit() { printf '{"session_id":"s6","tool_input":{"file_path":"/x/app.ts"}}' | bash "$HOOK"; }

# 8. free 枠(2 回)は許可、3 回目は deny(rework を案内)
e1="$(edit)"; e2="$(edit)"; e3="$(edit)"
if [ -z "$e1" ] && [ -z "$e2" ] && denied "$e3" && grep -q rework <<<"$e3"; then
  ok "edits beyond per-file budget are denied with rework guidance"
else
  ng "edits beyond per-file budget are denied with rework guidance"
fi

# 9. rework 宣言で +4 され、続きの編集が通る
bash "$HOOK" rework '/x/app.ts' '原因は import 順と判明、次で並びを修正する' >/dev/null || true
e="$(edit)"
if [ -z "$e" ]; then
  ok "rework declaration extends the per-file budget"
else
  ng "rework declaration extends the per-file budget"
fi

# 10. 2 回目の rework まで使い切ったら hard deny、3 回目の rework は拒否される
for i in 1 2 3; do edit >/dev/null; done   # 4..6 消費(allowed=6)
bash "$HOOK" rework '/x/app.ts' 'タイムアウト値が原因、次で閾値を直す' >/dev/null || true
for i in 1 2 3 4; do edit >/dev/null; done # 7..10 消費(allowed=10)
e="$(edit)"
r3=0; bash "$HOOK" rework '/x/app.ts' '三度目の正直で直るはずだから' >/dev/null 2>&1 || r3=$?
if denied "$e" && ! grep -q rework <<<"$e" && [ "$r3" != 0 ]; then
  ok "exhausted rework budget is a hard stop"
else
  ng "exhausted rework budget is a hard stop"
fi

# 11. UserPromptSubmit が予算をリセットする
printf '{"session_id":"s6","hook_event_name":"UserPromptSubmit","prompt":"続けて"}' | bash "$HOOK" >/dev/null
e="$(edit)"
if [ -z "$e" ]; then
  ok "user prompt resets budgets"
else
  ng "user prompt resets budgets"
fi
unset CONVERGE_GATE_CHURN_FREE

# 12. 前回レビュー以降に実装が進んでいれば新マイルストーンとして数え直す。
#     進んでいない再レビューは従来どおり止まる(テストでは閾値 3 に絞る)
export CONVERGE_GATE_MILESTONE_EDITS=3
review7() { printf '{"session_id":"s7","tool_input":{"skill":"review-gate"}}' | bash "$HOOK"; }
edit7() { printf '{"session_id":"s7","tool_input":{"file_path":"/x/m%s.ts"}}' "$1" | bash "$HOOK"; }
review7 >/dev/null
review7 >/dev/null
for i in 1 2 3; do edit7 "$i" >/dev/null; done
r3="$(review7)"
r4="$(review7)"
r5="$(review7)"
if [ -z "$r3" ] && [ -z "$r4" ] && denied "$r5"; then
  ok "sufficient new work resets review rounds, stalled re-review still stops"
else
  ng "sufficient new work resets review rounds, stalled re-review still stops"
fi
unset CONVERGE_GATE_MILESTONE_EDITS

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
