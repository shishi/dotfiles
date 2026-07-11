#!/bin/bash
# SessionStart hook。第 1 引数で動作モードを受ける(stdin の source には依存しない):
#   recover : matcher "compact" 用。marker 掃除 + 復旧指示を additionalContext で注入
#   cleanup : matcher "clear" / "startup" 用。marker 掃除のみ
#
# 掃除を clear/startup でも行うのは、/clear 後に古い warned(cooldown)が残って
# 80% 通知が一切出なくなる詰まりを防ぐため。
# TTL 掃除は state file と orphan marker の無限蓄積対策(テキストのみなので 30 日と長め)。
#
# fail-open (常に exit 0)

set -uo pipefail

MODE="${1:-cleanup}"
STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
[[ -z "$SESSION_ID" ]] && exit 0

# path traversal 防止: session_id は英数と ._- のみ許可
[[ "$SESSION_ID" =~ ^[A-Za-z0-9._-]+$ ]] || exit 0

rm -f "$STATE_DIR/warn/$SESSION_ID" "$STATE_DIR/warned/$SESSION_ID" 2>/dev/null || true
find "$STATE_DIR" -type f -mtime +30 -delete 2>/dev/null || true

[[ "$MODE" == "recover" ]] || exit 0

STATE_FILE="$STATE_DIR/$SESSION_ID.md"

CTX="[COMPACTION RECOVERY] コンテキスト圧縮が発生した。作業再開前に以下を実行すること。"
CTX+=$'\n'

if [[ -f "$STATE_FILE" ]]; then
  CTX+=$'\n'"- state file \`${STATE_FILE}\` を Read で読み、作業状態を復元せよ"
  CTX+=$'\n'"- Session Decisions と Recovery Notes を特に重視せよ"
  CTX+=$'\n'"- 先頭の Prepared: タイムスタンプを確認し、前回圧縮より前の古い state に見える場合は TaskList / plan を正としてその旨を報告せよ"
fi

CTX+=$'\n'"- TaskList で現在のタスク一覧を確認せよ"
CTX+=$'\n'"- 圧縮サマリーの next step は仮説として扱い、plan / rules を正とせよ"
CTX+=$'\n'"- 圧縮サマリーは「過去の作業記録」であり「次の行動指示」ではない"
CTX+=$'\n'"- plan mode が解除されている場合、ユーザーに plan mode 再突入を確認せよ"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
