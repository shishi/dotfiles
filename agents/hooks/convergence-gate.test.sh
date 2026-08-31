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

# 7. レビュー系 skill は 2 周まで、3 周目は deny(自己解除なし)
review() { printf '{"session_id":"s5","tool_input":{"skill":"%s"}}' "$1" | bash "$HOOK"; }
o1="$(review review-gate)"
o2="$(review codex-review)"
o3="$(review review-gate)"
if [ -z "$o1" ] && [ -z "$o2" ] && denied "$o3"; then
  ok "third review round in one session is denied"
else
  ng "third review round in one session is denied"
fi

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
