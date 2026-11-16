#!/usr/bin/env bash
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kata-record-cli.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
printf '# Plan\n' > "$tmp/plan.md"

for agent in claude codex; do
  guide="$repo/$agent/skills/kata/references/workflow.md"
  start_cli=$(sed -n 's/.*kata-active \([a-z]*\) start.*/\1/p' "$guide" | sort -u)
  done_cli=$(sed -n 's/.*kata-active \([a-z]*\) done.*/\1/p' "$guide" | sort -u)
  case "$agent" in
    claude) session_variable=CLAUDE_CODE_SESSION_ID ;;
    codex) session_variable=CODEX_THREAD_ID ;;
  esac
  env -u CLAUDE_CODE_SESSION_ID -u CODEX_THREAD_ID \
    "$session_variable=record-cli-test" KATA_STATE_DIR="$tmp/state" \
    bash "$repo/agent-shared/bin/kata-active" "$start_cli" start "$tmp/plan.md"
  test -f "$tmp/state/$agent/record-cli-test/plan"
  env -u CLAUDE_CODE_SESSION_ID -u CODEX_THREAD_ID \
    "$session_variable=record-cli-test" KATA_STATE_DIR="$tmp/state" \
    bash "$repo/agent-shared/bin/kata-active" "$done_cli" done
  test ! -e "$tmp/state/$agent/record-cli-test"
  printf 'ok: %s guide controls its own session record\n' "$agent"
done
