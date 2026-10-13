#!/usr/bin/env bash
# CLI の実行結果から必要なmetadataだけを private state へ記録する。
set -eu
if [ "$#" -lt 7 ] || [ "$#" -gt 9 ]; then
  echo 'usage: agent-run-record.sh PROVIDER MODEL EFFORT ROLE START_EPOCH EXIT_CODE RESULT_FILE [TASK_STATUS [FINISH_EPOCH]]' >&2
  exit 2
fi
provider=$1 model=$2 effort=$3 role=$4 started=$5 exit_code=$6 result=$7 status=${8:-}
case "$provider" in codex|claude) ;; *) echo 'invalid provider' >&2; exit 2 ;; esac
case "$role" in explore|chore|implement|correctness|adversarial|spec-scope) ;; *) echo 'invalid role' >&2; exit 2 ;; esac
case "$status" in ''|done|partial|blocked|unknown|error) ;; *) echo 'invalid task status' >&2; exit 2 ;; esac
finished=${9:-$(date +%s)}
case "$started:$exit_code:$finished" in *[!0-9:]*|:*|*::*|*:) echo 'invalid timestamp or exit code' >&2; exit 2 ;; esac
if [ "$finished" -lt "$started" ]; then
  echo 'finish timestamp precedes start' >&2
  exit 2
fi
[ -f "$result" ] || { echo 'result file missing' >&2; exit 2; }
umask 077
state="${XDG_STATE_HOME:-$HOME/.local/state}/agent-runs"
mkdir -p "$state"
chmod 700 "$state"
state=$(cd "$state" && pwd -P)
record=$(mktemp "$state/run-XXXXXXXX")
trap 'rm -f "$record"' EXIT
jq -cn --rawfile raw "$result" --arg provider "$provider" --arg model "$model" \
  --arg effort "$effort" --arg role "$role" --arg status "$status" \
  --argjson started "$started" --argjson finished "$finished" --argjson exit_code "$exit_code" '
  def token_usage:
    if type != "object" then null else
      with_entries(select(.key | IN("input_tokens", "output_tokens", "cached_input_tokens",
        "cache_read_input_tokens", "cache_creation_input_tokens"))) |
      with_entries(select(.value | type == "number")) |
      if length == 0 then null else . end
    end;
  (try (if $provider == "codex" then
    $raw | split("\n") | map(select(test("\\S")) | fromjson)
    else [$raw | fromjson] end) catch null) as $events |
  (if $events | type == "array" then $events | map(select(type == "object")) else [] end) as $objects |
  (if $provider == "codex" then [$objects[] | select(.type == "turn.completed")]
    else [$objects[] | select(.type == "result" and .subtype == "success" and .is_error == false)] end) as $completed |
  ([$objects[] | select(.type == "turn.completed" or .type == "turn.failed")][-1]) as $terminal |
  (if $provider == "codex" then
    $terminal.type == "turn.failed" or
      ($terminal == null and ([$objects[] | select(.type == "error")] | length > 0))
    else ([$objects[] | select(.type == "result" and
      (.is_error == true or .subtype != "success"))] | length > 0) end) as $failed |
  (if $provider == "claude" then
    [$objects[] | .modelUsage? | select(type == "object") | keys[]]
    else [$objects[] | select(.type == "thread.started" or .type == "turn.started") |
      .model? | select(type == "string")] end | unique | if length == 0 then null else . end) as $models |
  ([$objects[] | select(if $provider == "claude" then .type == "result"
      else .type == "turn.completed" or .type == "turn.failed" end) |
      .usage | token_usage | select(. != null)] |
    if length == 0 then null else reduce .[] as $usage ({};
      reduce ($usage | to_entries[]) as $entry (.; .[$entry.key] = ((.[$entry.key] // 0) + $entry.value))) end) as $usage |
  (if $exit_code != 0 or $failed then "error"
    elif $completed | length == 0 then "unknown"
    elif $status != "" then $status
    elif $provider == "claude" then
      ($completed[-1].structured_output.status // "unknown") |
      if IN("done", "partial", "blocked") then . else "unknown" end
    else "unknown" end) as $task_status |
  {provider:$provider, requested_model:$model, actual_models:$models, effort:$effort,
   role:$role, started_at:$started, finished_at:$finished,
   duration_seconds:($finished - $started), exit_code:$exit_code,
   task_status:$task_status, usage:$usage, rate_limits:null,
   verification:null, adopted_findings:null, rework_count:null}
' > "$record"
chmod 600 "$record"
trap - EXIT
printf '%s\n' "$record"
