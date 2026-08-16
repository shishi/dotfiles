#!/usr/bin/env bash

# Read JSON input from stdin
input=$(cat)

MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name' | tr -d '\r')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir' | tr -d '\r')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // empty' | tr -d '\r')
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty' | tr -d '\r')
# path traversal 防止: 不正な session_id は marker 書き込みに使わない
[[ "$SESSION_ID" =~ ^[A-Za-z0-9._-]+$ ]] || SESSION_ID=""
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

# used_percentage が数値でない場合は未取得扱いにする
[[ "$percentage" =~ ^[0-9]+$ ]] || percentage=""

if [ -z "$percentage" ]; then
  TOKEN_COUNT="_ tkns. (_%)"
else
  if [ "$total_tokens" -ge 1000 ]; then
    token_display="$((total_tokens / 1000)).$(((total_tokens % 1000) / 100))K"
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
  # 閾値は実発火の観測で決める調整値。この環境は auto compact 無効なので、上限前に
  # 人へ渡すのはこの経路だけ。
  COMPACT_WARN_THRESHOLD=50
  STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"
  if [ -n "$SESSION_ID" ] && [ "$percentage" -ge "$COMPACT_WARN_THRESHOLD" ] 2>/dev/null; then
    if [ ! -f "$STATE_DIR/warned/$SESSION_ID" ]; then
      mkdir -p "$STATE_DIR/warn" 2>/dev/null || true
      printf '%s\n' "$percentage" > "$STATE_DIR/warn/$SESSION_ID" 2>/dev/null || true
    fi
  fi
fi

# 実 payload が渡す % は画面にしか出ないため、閾値を決める材料が残らない。毎回の値を
# ここに残す。% が空 (どちらの取得にも失敗) のケースも記録したいので if の外に置く。
if [ -n "$USED_PCT_RAW" ]; then
  pct_source=official        # 公式フィールド。現在の占有量
elif [ -n "$percentage" ]; then
  pct_source=calc            # transcript からの自前計算。累積であり占有量ではない
else
  pct_source=none            # どちらも取れず、表示は _%
fi
# 置き場が無いときは作らない。marker 側が「不正な session_id では STATE_DIR を
# 作らない」を保っているので、記録のために先に作るとその保証を壊す。
STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"
if [ -d "$STATE_DIR" ]; then
  printf '%s %s %s\n' "${percentage:-_}" "$pct_source" "${SESSION_ID:-no-sid}" \
    > "$STATE_DIR/last-percentage" 2>/dev/null || true
fi

echo "󰚩 ${MODEL_DISPLAY} |  ${CURRENT_DIR##*/}${GIT_BRANCH} |  ${TOKEN_COUNT}"
