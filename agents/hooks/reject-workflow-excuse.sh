#!/usr/bin/env bash
# Stop hook: do not let workflow instructions become an excuse for leaving an
# explicitly requested, in-scope action undone.
set -u

hook_input=$(cat)

if [ "$(printf '%s' "$hook_input" | jq -r '.stop_hook_active // false')" = true ]; then
  printf '{}\n'
  exit 0
fi

message=$(printf '%s' "$hook_input" | jq -r '.last_assistant_message // ""')

if printf '%s' "$message" | grep -Eiq 'HERDR_ENV|skill|workflow|会話上未確認|明示されていな|許可されていな|安全規約|実行環境制約' &&
   printf '%s' "$message" | grep -Eq 'できな|実行しな|実行していな|停止|止め|未完了|残って|ブロック'; then
  jq -n '{
    decision: "block",
    reason: "workflow や skill は手段であり、ユーザーが明示した可逆・スコープ内の操作を残す理由にはならない。system/developer policy による実際の禁止または観測済みの外部エラーがない限り、最小の操作を今実行し、結果を確認してから回答せよ。"
  }'
else
  printf '{}\n'
fi
