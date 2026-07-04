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

echo "# recovery hook"

begin "recovery/cleanup は注入せず marker を消す"
mkdir -p "$COMPACT_STATE_DIR/warn" "$COMPACT_STATE_DIR/warned"
printf '1\n' > "$COMPACT_STATE_DIR/warn/sid-2"
printf '1\n' > "$COMPACT_STATE_DIR/warned/sid-2"
OUT=$(printf '{"session_id":"sid-2"}' | bash "$HOOKS/session-start-compaction-recovery.sh" cleanup); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
check "warn 消滅" test ! -f "$COMPACT_STATE_DIR/warn/sid-2"
check "warned 消滅" test ! -f "$COMPACT_STATE_DIR/warned/sid-2"
end

begin "recovery/recover state なし"
OUT=$(printf '{"session_id":"sid-3"}' | bash "$HOOKS/session-start-compaction-recovery.sh" recover); RC=$?
check "exit 0" test "$RC" -eq 0
check "SessionStart として注入" grep -q '"hookEventName": "SessionStart"' <<<"$OUT"
check "サマリー仮説扱い指示" grep -q "仮説" <<<"$OUT"
check_not "state file には言及しない" grep -q "state file" <<<"$OUT"
end

begin "recovery/recover state あり"
mkdir -p "$COMPACT_STATE_DIR"
printf '# Compact Prep State\nPrepared: 2026-07-05T00:00:00+09:00\n' > "$COMPACT_STATE_DIR/sid-4.md"
OUT=$(printf '{"session_id":"sid-4"}' | bash "$HOOKS/session-start-compaction-recovery.sh" recover)
check "state file パスに言及" grep -q "sid-4.md" <<<"$OUT"
check "Prepared 鮮度確認指示" grep -q "Prepared" <<<"$OUT"
check "CR 混入ファイル名なし" no_cr_filenames
end

begin "recovery/TTL 30日"
mkdir -p "$COMPACT_STATE_DIR"
printf 'old\n' > "$COMPACT_STATE_DIR/old-sid.md"
touch -m -d "35 days ago" "$COMPACT_STATE_DIR/old-sid.md"
printf 'new\n' > "$COMPACT_STATE_DIR/new-sid.md"
printf '{"session_id":"sid-5"}' | bash "$HOOKS/session-start-compaction-recovery.sh" cleanup >/dev/null
check "35日前のファイルは消える" test ! -f "$COMPACT_STATE_DIR/old-sid.md"
check "新しいファイルは残る" test -f "$COMPACT_STATE_DIR/new-sid.md"
end

begin "recovery/session_id なし"
OUT=$(printf '{}' | bash "$HOOKS/session-start-compaction-recovery.sh" recover); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
end

echo "# statusline"

begin "statusline/used_percentage 85 で warn"
OUT=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-6","context_window":{"used_percentage":85.2}}' | bash "$STATUSLINE")
check "表示に 85% を含む" grep -q "85%" <<<"$OUT"
check "warn marker 作成" test -f "$COMPACT_STATE_DIR/warn/sid-6"
check "marker の中身が 85" grep -q "^85$" "$COMPACT_STATE_DIR/warn/sid-6"
check "CR 混入ファイル名なし" no_cr_filenames
end

begin "statusline/warned cooldown 中は warn を書かない"
mkdir -p "$COMPACT_STATE_DIR/warned"
printf '1\n' > "$COMPACT_STATE_DIR/warned/sid-7"
printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-7","context_window":{"used_percentage":90}}' | bash "$STATUSLINE" >/dev/null
check "warn を作らない" test ! -f "$COMPACT_STATE_DIR/warn/sid-7"
end

begin "statusline/50% は warn しない"
printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-8","context_window":{"used_percentage":50}}' | bash "$STATUSLINE" >/dev/null
check "warn を作らない" test ! -f "$COMPACT_STATE_DIR/warn/sid-8"
end

begin "statusline/fallback は分母 200000"
TRANSCRIPT="$TMP/transcript.jsonl"
printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":100000,"output_tokens":0,"cache_creation_input_tokens":30000,"cache_read_input_tokens":30000}}}' > "$TRANSCRIPT"
OUT=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-9","transcript_path":"'"$TRANSCRIPT"'"}' | bash "$STATUSLINE")
check "160K/200K = 80% を表示" grep -q "80%" <<<"$OUT"
check "80% なので warn marker 作成" test -f "$COMPACT_STATE_DIR/warn/sid-9"
end

echo "# final-review hardening"

begin "reminder/不正な session_id は拒否"
mkdir -p "$COMPACT_STATE_DIR/warn"
printf '83\n' > "$COMPACT_STATE_DIR/warn/evil"
OUT=$(printf '{"session_id":"../warn/evil"}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
check "marker は無傷" test -f "$COMPACT_STATE_DIR/warn/evil"
end

begin "recovery/不正な session_id は拒否"
OUTSIDE="$TMP/outside-victim"
printf 'x\n' > "$OUTSIDE"
OUT=$(printf '{"session_id":"../../outside-victim"}' | bash "$HOOKS/session-start-compaction-recovery.sh" cleanup); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
check "STATE_DIR 外のファイルが消えない" test -f "$OUTSIDE"
end

begin "reminder/warn+warned 併存時は再通知しない"
mkdir -p "$COMPACT_STATE_DIR/warn" "$COMPACT_STATE_DIR/warned"
printf '85\n' > "$COMPACT_STATE_DIR/warn/sid-r"
printf '1\n' > "$COMPACT_STATE_DIR/warned/sid-r"
OUT=$(printf '{"session_id":"sid-r"}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
check "warn は掃除される" test ! -f "$COMPACT_STATE_DIR/warn/sid-r"
end

begin "statusline/不正な session_id では marker を書かない"
printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"../evil","context_window":{"used_percentage":95}}' | bash "$STATUSLINE" >/dev/null 2>&1
check "STATE_DIR が作られない" test ! -e "$COMPACT_STATE_DIR"
end

begin "statusline/非数値 used_percentage は未取得扱い"
OUT=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-x","context_window":{"used_percentage":"abc"}}' | bash "$STATUSLINE" 2>"$TMP/stderr.txt")
check "stderr が空" test ! -s "$TMP/stderr.txt"
check "warn を作らない" test ! -f "$COMPACT_STATE_DIR/warn/sid-x"
check "プレースホルダ表示" grep -q "_%" <<<"$OUT"
end

echo ""
echo "結果: FAILURES=$FAILURES"
exit "$FAILURES"
