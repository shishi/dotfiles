#!/usr/bin/env bash

# Read JSON input from stdin
input=$(cat)

MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name' | tr -d '\r')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir' | tr -d '\r')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // empty' | tr -d '\r')
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty' | tr -d '\r')
USED_PCT_RAW=$(echo "$input" | jq -r '.context_window.used_percentage // empty' | tr -d '\r')

# Get git branch information
GIT_BRANCH=""
if git rev-parse &>/dev/null; then
  BRANCH=$(git branch --show-current)
  if [ -n "$BRANCH" ]; then
    GIT_BRANCH=" |  $BRANCH"
  else
    COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$COMMIT_HASH" ]; then
      GIT_BRANCH=" |  HEAD ($COMMIT_HASH)"
    fi
  fi
fi

# 表示用 token 数は従来どおり transcript の直近 usage から取得
total_tokens=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  total_tokens=$(tail -n 100 "$TRANSCRIPT_PATH" 2>/dev/null |
    jq -s 'map(select(.type == "assistant" and .message.usage)) |
    last |
    .message.usage |
    (.input_tokens // 0) +
    (.output_tokens // 0) +
    (.cache_creation_input_tokens // 0) +
  (.cache_read_input_tokens // 0)' 2>/dev/null | tr -d '\r')
  total_tokens=${total_tokens:-0}
fi

# 使用率: 公式 context_window.used_percentage 優先。
# 取れない場合は transcript 合計 / 200K(context の実サイズ)で fallback。
# 旧実装の分母 819200(1M の 80%)は実使用率の約 1/5 に過小表示するため廃止。
percentage=""
if [ -n "$USED_PCT_RAW" ]; then
  percentage=${USED_PCT_RAW%.*}
elif [ "$total_tokens" -gt 0 ] 2>/dev/null; then
  CONTEXT_WINDOW_SIZE=200000
  percentage=$((total_tokens * 100 / CONTEXT_WINDOW_SIZE))
fi

if [ -z "$percentage" ]; then
  TOKEN_COUNT="_ tkns. (_%)"
else
  if [ "$total_tokens" -ge 1000 ]; then
    thousands=$(echo "scale=1; $total_tokens/1000" | bc)
    token_display=$(printf "%.1fK" "$thousands")
  elif [ "$total_tokens" -gt 0 ]; then
    token_display="$total_tokens"
  else
    token_display="_"
  fi

  # Color coding for percentage
  if [ "$percentage" -ge 90 ]; then
    color="\033[31m" # Red
  elif [ "$percentage" -ge 70 ]; then
    color="\033[33m" # Yellow
  else
    color="\033[32m" # Green
  fi

  TOKEN_COUNT=$(echo -e "${token_display} tkns. (${color}${percentage}%\033[0m)")

  # 閾値超過で compact-prep 警告 marker を書く(cooldown 中でなければ)。
  # warn は reminder hook が消費し、warned は recovery hook が消す。
  COMPACT_WARN_THRESHOLD=80
  STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"
  if [ -n "$SESSION_ID" ] && [ "$percentage" -ge "$COMPACT_WARN_THRESHOLD" ] 2>/dev/null; then
    if [ ! -f "$STATE_DIR/warned/$SESSION_ID" ]; then
      mkdir -p "$STATE_DIR/warn" 2>/dev/null || true
      printf '%s\n' "$percentage" > "$STATE_DIR/warn/$SESSION_ID" 2>/dev/null || true
    fi
  fi
fi

echo "󰚩 ${MODEL_DISPLAY} |  ${CURRENT_DIR##*/}${GIT_BRANCH} |  ${TOKEN_COUNT}"
