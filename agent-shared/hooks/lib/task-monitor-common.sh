# 監視 hook (task-monitor-claude.sh / task-monitor-codex.sh) が source する共通処理。

# 確認の間隔 (分)。n 回目 (0 始まり) の確認までの待ち時間で、10・20・40 分の後は 40 分ごと。
# 60 分以下に保つのは、Codex で待機から戻ったエージェントが 1 時間のプロンプトキャッシュを使えるようにするため。
tm_interval() {
  case $1 in
    0) echo 10 ;;
    1) echo 20 ;;
    *) echo 40 ;;
  esac
}

# 1 分の秒数。テストで待ち時間を縮めるために上書きする。
TASK_MONITOR_MINUTE=${TASK_MONITOR_MINUTE:-60}

tm_state_dir() {
  local d="${TASK_MONITOR_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/task-monitor}/$1/$2"
  mkdir -p "$d" && printf '%s\n' "$d"
}

# 子エージェントの会話記録 (Claude の会話記録・Codex の rollout の JSONL) の末尾を、
# 操作・結果・本文を 1 行ずつにして返す: tm_excerpt <file> [bytes]
# シェルの出力は形式を問わずそのまま末尾を読む。出力の中身から会話記録かどうかを推測しない。
tm_excerpt() {
  local file=$1 bytes=${2:-3000}
  jq -R -r '
    def clip($n): tostring | gsub("\\s+"; " ") | .[0:$n];
    def text_of: if type == "array" then map(.text? // empty) | join(" ") else . end;
    fromjson? |
    if .type == "assistant" or .type == "user" then
      .message.content | if type == "array" then .[] else {type: "text", text: .} end |
      if .type == "tool_use" then "[tool] \(.name) \(.input | clip(200))"
      elif .type == "tool_result" then "[result] \(.content | text_of | clip(200))"
      elif .type == "text" and (.text | length) > 0 then "[text] \(.text | clip(300))"
      else empty end
    elif .type == "response_item" then
      .payload |
      if .type == "function_call" or .type == "custom_tool_call" or .type == "local_shell_call" then
        "[tool] \(.name // .type) \((.arguments // .input // .action // "") | clip(200))"
      elif .type == "function_call_output" or .type == "custom_tool_call_output" then
        "[result] \(.output | text_of | clip(200))"
      elif .type == "message" and .role == "assistant" then
        "[text] \(.content | text_of | clip(300))"
      else empty end
    else empty end
  ' "$file" | tail -c "$bytes"
}
