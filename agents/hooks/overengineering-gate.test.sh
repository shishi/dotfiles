#!/usr/bin/env bash
# テスト追加を deny し、justify 宣言後だけ許可する契約を検証する。
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/overengineering-gate.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/overeng-gate.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export OVERENG_GATE_STATE_DIR="$TMP/state"

payload() { # $1=tool_input JSON
  printf '{"tool_input":%s}' "$1"
}
denied() { grep -q '"permissionDecision": *"deny"' <<<"$1"; }

# 1. 新規テストファイルの Write は deny
out="$(payload "{\"file_path\":\"$TMP/foo.test.ts\",\"content\":\"x\"}" | bash "$HOOK")"
if denied "$out"; then
  ok "new test file write is denied"
else
  ng "new test file write is denied"
fi

# 2. justify 後の同じ Write は許可
bash "$HOOK" justify "$TMP/foo.test.ts" "依頼された挙動Xの証明に必要" >/dev/null || true
out="$(payload "{\"file_path\":\"$TMP/foo.test.ts\",\"content\":\"x\"}" | bash "$HOOK")"
if [ -z "$out" ]; then
  ok "justified write is allowed"
else
  ng "justified write is allowed"
fi

# 3. テストと無関係な Write は素通り
out="$(payload "{\"file_path\":\"$TMP/main.ts\",\"content\":\"export const a = 1\"}" | bash "$HOOK")"
if [ -z "$out" ]; then
  ok "non-test write passes"
else
  ng "non-test write passes"
fi

# 4. 既存ソースへテストマーカーを増やす Edit は deny
printf 'const a = 1\n' >"$TMP/lib.ts"
out="$(payload "{\"file_path\":\"$TMP/lib.ts\",\"old_string\":\"const a = 1\",\"new_string\":\"it('adds', () => {})\"}" | bash "$HOOK")"
if denied "$out"; then
  ok "edit that adds a test marker is denied"
else
  ng "edit that adds a test marker is denied"
fi

# 4b. ruby ソースへ行頭 RSpec ブロックを増やす Edit は deny
printf 'class A\nend\n' >"$TMP/a.rb"
out="$(payload "{\"file_path\":\"$TMP/a.rb\",\"old_string\":\"class A\",\"new_string\":\"it 'works' do\"}" | bash "$HOOK")"
if denied "$out"; then
  ok "edit that adds an rspec block is denied"
else
  ng "edit that adds an rspec block is denied"
fi

# 5. マーカー数が増えない既存テストの Edit は素通り(削除・修正を妨げない)
printf '%s\n' "it('a', () => {})" "it('b', () => {})" >"$TMP/bar.test.ts"
out="$(payload "{\"file_path\":\"$TMP/bar.test.ts\",\"old_string\":\"it('a', () => {})\",\"new_string\":\"it('a2', () => {})\"}" | bash "$HOOK")"
if [ -z "$out" ]; then
  ok "editing existing tests without adding markers passes"
else
  ng "editing existing tests without adding markers passes"
fi

# 6. apply_patch の Add File でテストファイルを作るコマンドは deny、justify 後は許可
patch_cmd='apply_patch <<EOF\n*** Begin Patch\n*** Add File: src/util_test.py\n+def test_x():\n+    pass\n*** End Patch\nEOF'
out="$(payload "{\"command\":\"$patch_cmd\"}" | bash "$HOOK")"
if denied "$out"; then
  ok "apply_patch adding a test file is denied"
else
  ng "apply_patch adding a test file is denied"
fi
bash "$HOOK" justify "src/util_test.py" "依頼された挙動Yの証明に必要" >/dev/null || true
out="$(payload "{\"command\":\"$patch_cmd\"}" | bash "$HOOK")"
if [ -z "$out" ]; then
  ok "justified apply_patch is allowed"
else
  ng "justified apply_patch is allowed"
fi

# 7. 期限切れの宣言は無効
mkdir -p "$OVERENG_GATE_STATE_DIR"
for f in "$OVERENG_GATE_STATE_DIR"/*; do
  printf '%s\t%s\n' "$(( $(date +%s) - 100000 ))" "stale" >"$f"
done
out="$(payload "{\"file_path\":\"$TMP/foo.test.ts\",\"content\":\"x\"}" | bash "$HOOK")"
if denied "$out"; then
  ok "expired justification is invalid"
else
  ng "expired justification is invalid"
fi

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
