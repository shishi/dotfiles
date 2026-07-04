#!/bin/bash
# UserPromptSubmit hook: statusline が書いた compact-warn marker を検出し、
# additionalContext で compact-prep 実行を促す(one-shot)。
#
# フロー:
#   statusline.sh が使用率 >= 80 で warn marker 書込
#   → 本 hook が検出 → warned marker 作成(先) → warn marker 削除 → additionalContext 注入
#   → recovery hook が compact/clear/startup 時に warned marker 削除(cooldown リセット)
#
# warned を warn より先に作るのは、並行して走る statusline が
# 「warn なし・warned なし」の瞬間を見て warn を再作成する再通知レースを塞ぐため。
#
# overhead: marker なしターンは test -f 1 回で即 exit
# fail-open (常に exit 0)

set -uo pipefail

STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
[[ -z "$SESSION_ID" ]] && exit 0

WARN_MARKER="$STATE_DIR/warn/$SESSION_ID"
[[ -f "$WARN_MARKER" ]] || exit 0

mkdir -p "$STATE_DIR/warned" 2>/dev/null || true
printf '%s\n' "$(date +%s)" > "$STATE_DIR/warned/$SESSION_ID" 2>/dev/null || true

CTX_PCT=$(tr -d '\r\n' < "$WARN_MARKER" 2>/dev/null)
CTX_PCT=${CTX_PCT:-"?"}
rm -f "$WARN_MARKER" 2>/dev/null || true

CTX="[COMPACT PREP REMINDER] context 使用率が ${CTX_PCT}% に達した。"
CTX+=$'\n'"- 作業区切りでユーザーに \`/compact-prep\` の実行を提案せよ。"
CTX+=$'\n'"- \`/compact-prep\` 実行後、ユーザーに \`/compact\` 実行を案内せよ。"
CTX+=$'\n'"- scope 縮小や別セッション化ではなく、圧縮前 state 保存で対処せよ。"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
