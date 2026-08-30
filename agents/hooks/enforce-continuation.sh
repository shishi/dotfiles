#!/usr/bin/env bash
# UserPromptSubmit — 未完了タスクを残して応答を打ち切らないよう毎ターン注入する。
set -u

read -r -d '' message <<'EOF'
[必要性ゲート — 毎ターン監査]
- 依頼の完了条件を、ユーザーが求めた観測可能な結果だけで定義せよ。候補作業ごとに、その結果へ直接もたらす実益または回避する具体的リスクを一つ示せなければ実行するな。
- test、検証、refactor、抽象化、guard、plan、Web 調査、subagent、独立レビュー、skill workflow は手段であり、それ自体やレビュー指摘を必要性の根拠にするな。
- まず最小の変更と、その結果を直接確認する最小の検証一つだけを行え。失敗、曖昧な結果、未確認の具体的リスクを観測した場合だけ次の作業を追加せよ。
- 完了条件と直接検証を満たしたら、改善候補を探さず終了せよ。自分で可能な作業はユーザーへ返さず、変更は今回の差分だけを commit し、明示なしに push するな。
- 停止してよいのは、不可逆な操作、権限または外部状態の変更、結果を大きく変える主観的選択にユーザー入力が必要な場合だけである。
EOF

jq -n --arg message "$message" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $message
  }
}'
