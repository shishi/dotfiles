#!/usr/bin/env bash
# PreToolUse (AskUserQuestion) — 質問する瞬間に「まず試したか」を差し込む。
#
# 規則の本文は agent-memory の autonomous-execution-preference にあるが、
# 索引しか注入されないため質問を組み立てる瞬間には効かない。block はしない
# (正当な質問は通す。判断材料を出すだけ)。
set -o pipefail

read -r -d '' msg <<'EOF'
[autonomy] 聞く前に: それは試せば答えが出ることではないか?
- 試して分かるなら聞かずに試す。失敗は戻せる (git / 一時ディレクトリ / plugin の uninstall)
- 「実装はできるが影響範囲が広い」「前例がない」「失敗するかもしれない」は聞く理由にならない
- 質問してよいのは、権限が足りない / GUI しか手段がない / 視覚・主観の判定が必要 / 破壊的で承認が要る / 検証しても優劣が決まらない好みの問題、のいずれか
- 該当しないなら質問を取り下げ、検証して結果を持って報告する
EOF

jq -n --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $m
  }
}'
