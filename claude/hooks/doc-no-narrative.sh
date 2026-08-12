#!/usr/bin/env bash
# PreToolUse (Write|Edit) — Markdown を書く瞬間にドキュメントの規則を差し込む。
#
# 規則の本文は agent-memory の writing-decision-docs / usage-docs-in-readme にあるが、
# セッションに注入されるのは索引だけなので「書く瞬間」には結びつかない。
# harness 側から出すことでエージェントの記憶や判断に依存させない。block はしない。
set -o pipefail

path=$(jq -r '.tool_input.file_path // empty')
[ -z "$path" ] && exit 0

case "$path" in
  *.md | *.mdx) ;;
  *) exit 0 ;;
esac

read -r -d '' msg <<'EOF'
[docs] ドキュメントは読者のためのもので、経緯の記録場所ではない。
- 書かない: 日付つきの実測記録・検証状況の表・試した条件の一覧・「以前は〜」「〜を撤去した」「同じ実験を再走させない」
- 書く: 現在形の事実・設計理由・動作前提(何が要るか)・既知の制限(何ができないか)・断定と推定の区別
- 経緯は commit message / PR 本文へ。エージェント向けの再発防止は skill / memory へ
- 「◯◯を無効化してください」「戻すときはこのコマンド」を書きたくなったら、それは設計が間違っているサイン。構造で解決できないか先に見る
- 経緯を削るときに動作前提まで巻き添えにしない
EOF

jq -n --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $m
  }
}'
