#!/usr/bin/env bash
# CLI metadata を private な実行単位JSONLへ保存する振る舞いを確認する。
set -eu
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export XDG_STATE_HOME="$fixture/state"
export RECORD_TEST_MKTEMP="$(command -v mktemp)"
mkdir "$fixture/bin"
# BSD mktemp randomizes trailing Xs; suffix text leaves a literal, repeated name.
cat > "$fixture/bin/mktemp" <<'SH'
#!/usr/bin/env bash
case "$1" in
  *X) exec "$RECORD_TEST_MKTEMP" "$@" ;;
  *) : > "$1"; printf '%s\n' "$1" ;;
esac
SH
chmod +x "$fixture/bin/mktemp"
export PATH="$fixture/bin:$PATH"
start=$(date +%s)
cat > "$fixture/codex.jsonl" <<'JSON'
{"type":"thread.started","thread_id":"private-thread"}
{"type":"item.completed","item":{"type":"agent_message","text":"PRIVATE_PROMPT_AND_RESPONSE"}}
{"type":"turn.completed","usage":{"input_tokens":120,"cached_input_tokens":90,"output_tokens":18}}
JSON
cat > "$fixture/claude.json" <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"PRIVATE_PROMPT_AND_RESPONSE","structured_output":{"status":"done"},"usage":{"input_tokens":11,"output_tokens":7,"cache_read_input_tokens":22,"cache_creation_input_tokens":3},"modelUsage":{"claude-actual":{"inputTokens":11,"outputTokens":7,"contextWindow":200000}},"total_cost_usd":0.04}
JSON
cat > "$fixture/claude-error.json" <<'JSON'
{"type":"result","subtype":"error_max_turns","is_error":true,"usage":{"input_tokens":120,"output_tokens":18}}
JSON
record() {
  bash "$REPO/agent-shared/bin/agent-run-record.sh" "$1" requested high explore "$start" "$2" "$3" "${4:-}"
}
codex_record=$(record codex 0 "$fixture/codex.jsonl" done)
claude_record=$(record claude 0 "$fixture/claude.json")
if [ "$codex_record" = "$claude_record" ]; then
  echo 'FAIL: separate runs reused one record under BSD mktemp semantics' >&2
  exit 1
fi
failed_usage_record=$(record claude 1 "$fixture/claude-error.json")
jq -e '.task_status == "error" and .usage == {input_tokens:120,output_tokens:18}' "$failed_usage_record" >/dev/null || {
  echo 'FAIL: failed Claude result lost actual usage' >&2
  exit 1
}
printf '%s\n' '{"type":"error","message":"PRIVATE_PROMPT_AND_RESPONSE"}' > "$fixture/recovered.jsonl"
cat "$fixture/codex.jsonl" >> "$fixture/recovered.jsonl"
cat "$fixture/codex.jsonl" > "$fixture/final-failure.jsonl"
printf '%s\n' '{"type":"turn.failed","error":{"message":"PRIVATE_PROMPT_AND_RESPONSE"}}' >> "$fixture/final-failure.jsonl"
recovered_record=$(record codex 0 "$fixture/recovered.jsonl" done)
final_failure_record=$(record codex 0 "$fixture/final-failure.jsonl" done)
jq -e '.task_status == "done"' "$recovered_record" >/dev/null || {
  echo 'FAIL: recovered Codex error overrode final completion' >&2
  exit 1
}
jq -e '.task_status == "error"' "$final_failure_record" >/dev/null
delayed_record=$(bash "$REPO/agent-shared/bin/agent-run-record.sh" codex requested high explore 100 0 "$fixture/codex.jsonl" done 111)
jq -e '.started_at == 100 and .finished_at == 111 and .duration_seconds == 11' "$delayed_record" >/dev/null
if bash "$REPO/agent-shared/bin/agent-run-record.sh" codex requested high explore 100 0 "$fixture/codex.jsonl" done 99 > "$fixture/invalid-end.out" 2> "$fixture/invalid-end.err"; then
  echo 'FAIL: finish before start accepted' >&2
  exit 1
fi
jq -e --argjson start "$start" '
  .provider == "codex" and .requested_model == "requested" and
  .actual_models == null and .effort == "high" and .role == "explore" and
  .started_at == $start and .finished_at >= $start and .duration_seconds >= 0 and
  .exit_code == 0 and .task_status == "done" and
  .usage == {input_tokens:120,cached_input_tokens:90,output_tokens:18} and .rate_limits == null
' "$codex_record" >/dev/null
jq -e '
  .provider == "claude" and .actual_models == ["claude-actual"] and
  .task_status == "done" and .usage.input_tokens == 11 and .usage.output_tokens == 7 and
  .usage.cache_read_input_tokens == 22 and .usage.cache_creation_input_tokens == 3 and
  (.usage | has("total_cost_usd") | not) and .rate_limits == null
' "$claude_record" >/dev/null
printf 'PRIVATE_PROMPT_AND_RESPONSE invalid JSON\n' > "$fixture/invalid"
printf '%s\n' '{"type":"result","subtype":"success","structured_output":{"status":"done"}}' > "$fixture/no-is-error"
: > "$fixture/empty"
invalid_record=$(record codex 1 "$fixture/invalid" done)
empty_record=$(record claude 0 "$fixture/empty")
missing_flag_record=$(record claude 0 "$fixture/no-is-error" done)
jq -e '.task_status == "error" and .usage == null and .actual_models == null and .exit_code == 1' "$invalid_record" >/dev/null
jq -e '.task_status == "unknown" and .usage == null and .actual_models == null' "$empty_record" >/dev/null
jq -e '.task_status == "unknown"' "$missing_flag_record" >/dev/null
python3 - "$XDG_STATE_HOME/agent-runs" "$codex_record" "$claude_record" "$invalid_record" "$empty_record" "$missing_flag_record" "$delayed_record" "$failed_usage_record" "$recovered_record" "$final_failure_record" <<'PY'
import json
import os
import pathlib
import stat
import sys
root = pathlib.Path(sys.argv[1])
assert stat.S_IMODE(root.stat().st_mode) == 0o700
assert len(list(root.glob('run-*'))) == 9
for name in sys.argv[2:]:
    path = pathlib.Path(name)
    assert path.is_absolute() and path.parent == root
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    lines = path.read_text().splitlines()
    assert len(lines) == 1
    value = json.loads(lines[0])
    assert set(value) == {'provider', 'requested_model', 'actual_models', 'effort', 'role',
                          'started_at', 'finished_at', 'duration_seconds', 'exit_code',
                          'task_status', 'usage', 'rate_limits', 'verification', 'adopted_findings', 'rework_count'}
    assert value['verification'] is None and value['adopted_findings'] is None
    assert 'PRIVATE_PROMPT_AND_RESPONSE' not in lines[0]
    assert 'private-thread' not in lines[0]
PY
printf 'PASS: both CLI usage, failed/empty results, private metadata-only records\n'
