#!/usr/bin/env bash
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

for message in 'すべて完了した' '一部が失敗したので残りは次回'; do
  output=$(jq -n --arg message "$message" '{hook_event_name:"Stop",stop_hook_active:false,last_assistant_message:$message}' | bash "$HOOK_DIR/task-completion.sh")
  printf '%s\n' "$output" | jq -e '.decision == "block" and (.reason | type == "string" and length > 0)' >/dev/null
done
echo 'ok: first Stop requests a completion audit regardless of final-answer wording'

output=$(printf '%s\n' '{"hook_event_name":"Stop","stop_hook_active":true}' | bash "$HOOK_DIR/task-completion.sh")
printf '%s\n' "$output" | jq -e '. == {}' >/dev/null
echo 'ok: the audit continuation does not recursively launch another audit'

for payload in '{}' '{"hook_event_name":"Stop","stop_hook_active":"false"}' '{"hook_event_name":"UserPromptSubmit","stop_hook_active":false}' 'invalid'; do
  if printf '%s\n' "$payload" | bash "$HOOK_DIR/task-completion.sh" >/dev/null 2>&1; then
    echo 'not ok: malformed or unrelated event accepted' >&2
    exit 1
  fi
done
echo 'ok: malformed and unrelated events are reported as errors'

for config in claude/settings.json codex/hooks.json; do
  jq -e '[.hooks.Stop[].hooks[] | select(.command == "bash ~/.agent-shared/hooks/task-completion.sh" and .type == "command" and (.async != true))] | length == 1' "$HOOK_DIR/../../$config" >/dev/null
  echo "ok: $config registers one synchronous Stop check"
done
