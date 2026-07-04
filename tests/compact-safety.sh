#!/usr/bin/env bash
# compact 対策 3点セットのスモークテスト。
# 使い方: bash tests/compact-safety.sh
# COMPACT_STATE_DIR を一時ディレクトリへ向けるので本番 ~/.claude/compact-state は触らない。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$REPO/claude/hooks"
STATUSLINE="$REPO/claude/statusline.sh"
FAILURES=0
CURRENT=""
TMP=""

begin() {
  CURRENT="$1"
  TMP="$(mktemp -d)"
  export COMPACT_STATE_DIR="$TMP/state"
}

end() {
  rm -rf "$TMP"
}

pass() { echo "  ok: ${CURRENT}: $1"; }
fail() { echo "  NG: ${CURRENT}: $1"; FAILURES=$((FAILURES + 1)); }

check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

check_not() { # 成功したら NG
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

# ファイル名への CR 混入検査(spec 検証済みの事実 6 の回帰テスト)
no_cr_filenames() {
  [ -z "$(find "$COMPACT_STATE_DIR" -name "$(printf '*\r*')" 2>/dev/null)" ]
}

echo "# reminder hook"

begin "reminder/warn なし"
OUT=$(printf '{"session_id":"sid-1"}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
end

begin "reminder/warn あり"
mkdir -p "$COMPACT_STATE_DIR/warn"
printf '83\n' > "$COMPACT_STATE_DIR/warn/sid-1"
OUT=$(printf '{"session_id":"sid-1"}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "additionalContext を含む" grep -q "additionalContext" <<<"$OUT"
check "使用率 83% を含む" grep -q "83%" <<<"$OUT"
check "compact-prep 提案を含む" grep -q "compact-prep" <<<"$OUT"
check "warn 消滅" test ! -f "$COMPACT_STATE_DIR/warn/sid-1"
check "warned 作成(CR なしの名前で)" test -f "$COMPACT_STATE_DIR/warned/sid-1"
check "CR 混入ファイル名なし" no_cr_filenames
end

begin "reminder/session_id なし"
OUT=$(printf '{}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
end

echo ""
echo "結果: FAILURES=$FAILURES"
exit "$FAILURES"
