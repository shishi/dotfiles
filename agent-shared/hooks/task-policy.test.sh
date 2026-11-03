#!/usr/bin/env bash
# 作業規則の単独出力と、両エージェントの入力時 hook への登録を確認する。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/task-policy.XXXXXX")
trap 'rm -rf "$test_home"' EXIT

# 規則の注入は一時停止中 (先頭の 3 行で exit する)。停止中は何も出さず、その 3 行を消せば規則を出せることを確かめる。
output=$(HOME="$test_home" bash "$HOOK_DIR/task-policy.sh" </dev/null)
[ -z "$output" ]
echo 'ok: the paused task policy injects nothing'
sed '/^# 一時停止中/,/^exit 0$/d' "$HOOK_DIR/task-policy.sh" >"$test_home/resumed.sh"
output=$(HOME="$test_home" bash "$test_home/resumed.sh" </dev/null)
printf '%s\n' "$output" | grep -q '^<task-policy>$'
printf '%s\n' "$output" | grep -q '^</task-policy>$'
echo 'ok: removing the pause lines brings the task policy back without memory or prompt input'

for config in claude/settings.json codex/hooks.json; do
  jq -e '[.hooks.UserPromptSubmit[].hooks[] | select(.command == "bash ~/.agent-shared/hooks/task-policy.sh")] | length == 1' "$HOOK_DIR/../../$config" >/dev/null
  echo "ok: $config registers the task policy once for every input"
done
