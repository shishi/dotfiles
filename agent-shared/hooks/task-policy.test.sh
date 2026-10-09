#!/usr/bin/env bash
# 作業規則の単独出力と、両エージェントの入力時 hook への登録を確認する。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/task-policy.XXXXXX")
trap 'rm -rf "$test_home"' EXIT

output=$(HOME="$test_home" bash "$HOOK_DIR/task-policy.sh" </dev/null)
printf '%s\n' "$output" | grep -q '^<task-policy>$'
printf '%s\n' "$output" | grep -q '問題をそらさない。論点を広げない。'
printf '%s\n' "$output" | grep -q '中断しない。人間に聞いて作業を返さない。'
printf '%s\n' "$output" | grep -q '全対象を調べきり'
echo 'ok: task policy is available without memory or prompt input'

for config in claude/settings.json codex/hooks.json; do
  jq -e '[.hooks.UserPromptSubmit[].hooks[] | select(.command == "bash ~/.agent-shared/hooks/task-policy.sh")] | length == 1' "$HOOK_DIR/../../$config" >/dev/null
  echo "ok: $config registers the task policy once for every input"
done
