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
deleted="$(payload "{\"file_path\":\"$TMP/bar.test.ts\",\"old_string\":\"it('b', () => {})\",\"new_string\":\"\"}" | bash "$HOOK")"
if [ -z "$out" ] && [ -z "$deleted" ]; then
  ok "corrections and deletions of existing tests pass"
else
  ng "corrections and deletions of existing tests pass"
fi

# 6. Codex の直接 apply_patch でテストファイルを作るコマンドは deny、justify 後は許可
patch_cmd=$'*** Begin Patch\n*** Add File: src/util_test.py\n+def test_x():\n+    pass\n*** End Patch'
out="$(jq -n --arg command "$patch_cmd" \
  '{tool_name:"apply_patch",tool_input:{command:$command}}' | bash "$HOOK")"
if denied "$out"; then
  ok "apply_patch adding a test file is denied"
else
  ng "apply_patch adding a test file is denied"
fi
bash "$HOOK" justify "src/util_test.py" "依頼された挙動Yの証明に必要" >/dev/null || true
out="$(jq -n --arg command "$patch_cmd" \
  '{tool_name:"apply_patch",tool_input:{command:$command}}' | bash "$HOOK")"
if [ -z "$out" ]; then
  ok "justified apply_patch is allowed"
else
  ng "justified apply_patch is allowed"
fi

# 7. 期限切れの宣言は無効
mkdir -p "$OVERENG_GATE_STATE_DIR"
for f in "$OVERENG_GATE_STATE_DIR"/*; do
  printf '%s\t%s\n' "$(( $(date +%s) - 901 ))" "stale" >"$f"
done
out="$(payload "{\"file_path\":\"$TMP/foo.test.ts\",\"content\":\"x\"}" | bash "$HOOK")"
if denied "$out"; then
  ok "expired justification is invalid"
else
  ng "expired justification is invalid"
fi

# 8. 正当化された追加は従来の 5 ファイル上限を超えても許可する
export OVERENG_GATE_STATE_DIR="$TMP/state-files"
all_allowed=1
for i in 1 2 3 4 5 6; do
  bash "$HOOK" justify "$TMP/b$i.test.ts" "依頼された挙動$i の証明に必要" >/dev/null || true
  out="$(printf '{"session_id":"s%s","tool_input":{"file_path":"%s","content":"x"}}' "$i" "$TMP/b$i.test.ts" | bash "$HOOK")"
  [ -z "$out" ] || all_allowed=0
done
if [ "$all_allowed" = 1 ]; then
  ok "justified test files beyond former limit pass across sessions"
else
  ng "justified test files beyond former limit pass across sessions"
fi

# 9. 正当化された追加は従来の累計 20 ブロック上限を超えても許可する
export OVERENG_GATE_STATE_DIR="$TMP/state-cases"
bash "$HOOK" justify "$TMP/c.test.ts" "依頼された挙動Zの証明に必要" >/dev/null || true
content=""
for i in {1..21}; do content+="it('case$i', () => {})"$'\n'; done
o1="$(jq -n --arg path "$TMP/c.test.ts" --arg content "$content" \
  '{tool_input:{file_path:$path,content:$content}}' | bash "$HOOK")"
o2="$(jq -n --arg path "$TMP/c.test.ts" \
  '{tool_input:{file_path:$path,old_string:"x",new_string:"it(\"next\", () => {})"}}' | bash "$HOOK")"
if [ -z "$o1" ] && [ -z "$o2" ]; then
  ok "justified test cases beyond former cumulative limit pass"
else
  ng "justified test cases beyond former cumulative limit pass"
fi

# 10. 理由は 10 文字以上必要
status=0
bash "$HOOK" justify "$TMP/short.test.ts" 'short' >/dev/null 2>&1 || status=$?
out="$(payload "{\"file_path\":\"$TMP/short.test.ts\",\"content\":\"x\"}" | bash "$HOOK")"
if [ "$status" = 2 ] && denied "$out"; then
  ok "short justification remains refused"
else
  ng "short justification remains refused"
fi

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
