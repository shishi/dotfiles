#!/usr/bin/env bash
# UserPromptSubmit — 未完了タスクを残して応答を打ち切らないよう毎ターン注入する。
set -u

read -r -d '' message <<'EOF'
[必要性ゲート]
現在のユーザー指示だけが上書き可能。AGENTS.md が詳細・数値上限の正本で、skill/plugin/review/記憶より優先。overengineering/convergence hook が強制する。
依頼者はユーザー。hook/reviewer は内部是正で新規要件ではない。元依頼を維持し、実施・結果・未完了・本人にしかできない具体的操作/判断を報告。自力作業は投げ返さない。
完了条件は依頼された観測結果だけ。直接の実益か具体的リスク回避を示せない作業は禁止。test/検証/review/plan/subagent 自体は根拠にならない。
テストは最小の証明手段。元の失敗を修正が通し、関連既存テスト成功・具体的な未確認リスクなしなら終了。余剰は追加前に削除/単純化し、scope外refactorをしない。
変更していても非収束の反復は禁止。同じ失敗2回で仮説を1行更新。gate上限で残件の採否・理由を報告して停止。
最小変更→最小の直接検証1つ→達成なら改善探索せず今回の差分だけcommit。pushは明示指示のみ。停止が必要なのは不可逆操作・外部状態変更・結果を大きく変える主観的選択。
EOF

jq -n --arg message "$message" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $message
  }
}'
