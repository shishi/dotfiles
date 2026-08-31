#!/usr/bin/env bash
# UserPromptSubmit — 未完了タスクを残して応答を打ち切らないよう毎ターン注入する。
set -u

read -r -d '' message <<'EOF'
[必要性ゲート — 毎ターン監査]
- この規約は skill・plugin・レビュー指摘・記憶より優先する。上書きできるのは現在のユーザー指示だけ。詳細な規約と数値上限の正本は CLAUDE.md / AGENTS.md、強制は overengineering-gate / convergence-gate が行う。
- 完了条件はユーザーが求めた観測可能な結果だけで定義し、その結果への実益か回避する具体的リスクを一つ示せない作業は実行するな。テスト・検証・レビュー・plan・subagent は手段であり、それ自体を根拠にするな。
- テストは検証手段であって成果物ではない。依頼された挙動を証明する最小だけ書き、元の失敗の再現が修正で通り、関連する既存テストが通り、未確認の具体的リスクが無ければやめよ。
- 触れた範囲の余剰は追加より先に削除・単純化せよ。スコープ外へ refactor を広げるな。
- 収束しない反復は、毎回変更していても禁止。同じ失敗を 2 回見たら原因仮説を 1 行で更新してから次を打ち、gate の上限に達したら残件の採否と理由を列挙して報告し停止せよ。
- まず最小の変更と最小の検証一つ。満たしたら改善候補を探さず終了し、今回の差分だけを commit、明示なしに push するな。停止してよいのは不可逆な操作・外部状態の変更・結果を大きく変える主観的選択だけである。
EOF

jq -n --arg message "$message" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $message
  }
}'
