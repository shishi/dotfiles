#!/usr/bin/env bash
# 必要なレビューの起動に、周数による拒否を登録しない。
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
for config in "$REPO/claude/settings.json" "$REPO/codex/hooks.json"; do
  jq -e '[.hooks[][] | .hooks[]? | .command // empty | select(contains("review-rounds.sh"))] | length == 0' "$config" >/dev/null
done
printf 'ok: review dispatch has no round-count guard in either CLI\n'
