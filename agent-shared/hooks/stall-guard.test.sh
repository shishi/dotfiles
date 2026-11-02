#!/usr/bin/env bash
# 偽の hook 入力 JSON を stall-guard.sh に流し、出力と台帳 (状態ディレクトリの JSONL) を確かめる。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/stall-guard.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/stall-guard-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
NOW=1793599980 # 分の境界
export STALL_GUARD_STATE_DIR="$work/state" STALL_GUARD_NOW=$NOW
unset AGENT_DELEGATED_SESSION CLAUDE_CODE_SESSION_ID STALL_GUARD_WATCH_STARTED STALL_GUARD_WATCH_PERIOD
D="$STALL_GUARD_STATE_DIR/claude/s1"

fail() { echo "not ok: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
reset() { rm -rf "$STALL_GUARD_STATE_DIR"; }
sg() { bash "$HOOK" "$@"; }
# hook <subcommand> <jq の式>: 式で作った入力を標準入力に流す。
hook() { local sub=$1; shift; jq -nc "$@" | bash "$HOOK" $sub; }
last() { tail -n 1 "$1" | tr -d '\r'; }
field() { jq -r "$1" <<<"$2" | tr -d '\r'; }
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
post() { jq -nc --arg t "$1" --argjson r "$2" '{session_id:"s1",hook_event_name:"PostToolUse",tool_name:$t,tool_input:{},tool_use_id:"tu1",tool_response:$r}'; }
record() { post "$1" "$2" | sg record; }
agent() { record Agent "{\"status\":\"async_launched\",\"agentId\":\"$1\",\"outputFile\":\"$work/$1.jsonl\"}"; }
shell() { record Bash "{\"backgroundTaskId\":\"$1\",\"backgroundEndsWithFinalResponse\":${2:-false}}"; }
seen() { mkdir -p "$D"; printf '{"at":%s,"running":%s}\n' "${2:-$NOW}" "$1" >>"$D/seen.jsonl"; }

# --- 入口・台帳・record・status・disable ---

reset; agent a1
l=$(last "$D/tasks.jsonl")
[ "$(field .id "$l")" = a1 ] && [ "$(field .kind "$l")" = subagent ] && [ "$(field .started "$l")" = "$NOW" ] || fail "record keeps an async Agent launch: $l"
ok "record keeps an async Agent launch"

reset; record Agent '{"status":"completed","agentId":"a2"}'
[ ! -e "$D" ] || fail "record ignores a foreground Agent"
ok "record ignores a foreground Agent"

reset; shell b1 true
l=$(last "$D/tasks.jsonl")
[ "$(field .kind "$l")" = shell ] && [ "$(field .ends_with_final "$l")" = true ] || fail "record keeps a background Bash: $l"
ok "record keeps a background Bash"

reset; shell b1; jq -nc '{session_id:"s1",hook_event_name:"PostToolUse",tool_name:"TaskStop",tool_input:{task_id:"b1"},tool_response:{}}' | sg record
l=$(last "$D/ended.jsonl")
[ "$(field .id "$l")" = b1 ] && [ "$(field .by "$l")" = TaskStop ] || fail "record keeps a TaskStop: $l"
ok "record keeps a TaskStop"

reset; agent a1; hook record '{session_id:"s1",hook_event_name:"SubagentStop",agent_id:"a1"}'
l=$(last "$D/ended.jsonl")
[ "$(field .id "$l")" = a1 ] && [ "$(field .by "$l")" = SubagentStop ] || fail "record keeps a SubagentStop: $l"
ok "record keeps a SubagentStop"

reset; record ScheduleWakeup '{"scheduledFor":1793612040000,"clampedDelaySeconds":1200,"wasClamped":false}'
l=$(last "$D/wakeups.jsonl")
[ "$(field .fire "$l")" = 1793612040 ] && [ "$(field .key "$l")" = tu1 ] && [ "$(field .source "$l")" = ScheduleWakeup ] || fail "record keeps a ScheduleWakeup: $l"
ok "record keeps a ScheduleWakeup"

reset; seen '["a1"]'; shell b1
record CronCreate "{\"id\":\"c1\",\"recurring\":true,\"durable\":false,\"nextFireAt\":$(((NOW + 600) * 1000))}"
l=$(last "$D/wakeups.jsonl")
[ "$(field .key "$l")" = c1 ] && [ "$(field .cron_id "$l")" = c1 ] && [ "$(field '.tasks_at_create|join(",")' "$l")" = a1,b1 ] && [ "$(field .recurring "$l")" = true ] \
  || fail "record keeps a CronCreate with the running tasks: $l"
ok "record keeps a CronCreate with the running tasks"

reset; agent a1; record ScheduleWakeup "{\"scheduledFor\":$(((NOW + 1200) * 1000))}"
l=$(last "$D/wakeups.jsonl")
[ "$(field '.tasks_at_create|join(",")' "$l")" = a1 ] && [ "$(field .key "$l")" = tu1 ] || fail "candidates without a seen come from tasks: $l"
ok "candidates without a seen come from tasks"

reset; record CronCreate "{\"id\":\"c1\",\"recurring\":true,\"nextFireAt\":$(((NOW + 600) * 1000))}"
printf '{"at":%s,"crons":[{"id":"c1","schedule":"*/5 * * * *","recurring":true}]}\n' "$NOW" >>"$D/crons.jsonl"
s=$(sg status --json --session s1)
[ "$(field '.wakeups[0].live' "$s")" = true ] || fail "live follows session_crons (live): $s"
printf '{"at":%s,"crons":[]}\n' "$NOW" >>"$D/crons.jsonl"
s=$(sg status --json --session s1)
[ "$(field '.wakeups[0].live' "$s")" = false ] || fail "live follows session_crons (gone): $s"
ok "live follows session_crons"

reset; jq -nc '{session_id:"s1",hook_event_name:"PermissionDenied",tool_name:"ScheduleWakeup",tool_input:{delaySeconds:1200},tool_use_id:"tu2",reason:"denied"}' | sg record --failed
l=$(last "$D/failed.jsonl")
[ "$(lines "$D/failed.jsonl")" = 1 ] && [ "$(field .event "$l")" = PermissionDenied ] && [ "$(field .tool "$l")" = ScheduleWakeup ] || fail "record --failed keeps a denied wakeup: $l"
ok "record --failed keeps a denied wakeup"

reset; jq -nc '{session_id:"s1",hook_event_name:"PostToolUseFailure",tool_name:"ScheduleWakeup",tool_input:{delaySeconds:1200},tool_use_id:"tu3",error:"x",is_interrupt:false,duration_ms:3}' | sg record --failed
l=$(last "$D/failed.jsonl")
[ "$(lines "$D/failed.jsonl")" = 1 ] && [ "$(field .event "$l")" = PostToolUseFailure ] || fail "record --failed keeps a failed wakeup: $l"
ok "record --failed keeps a failed wakeup"

reset; mkdir -p "$STALL_GUARD_STATE_DIR"
out=$(jq -nc '{session_id:"../../x",hook_event_name:"PostToolUse",tool_name:"Agent",tool_response:{status:"async_launched",agentId:"a1"}}' | sg record) || fail "unsafe session ids exit 0"
[ -z "$out" ] && [ ! -e "$work/x" ] && [ -z "$(ls -A "$STALL_GUARD_STATE_DIR")" ] || fail "unsafe session ids are not used as paths"
ok "unsafe session ids are not used as paths"

reset; out=$(printf 'not json' | sg record) || fail "unreadable input exits 0"
out2=$(printf 'not json' | sg stop-check) || fail "unreadable input exits 0 (stop-check)"
[ -z "$out$out2" ] || fail "unreadable input fails open: $out$out2"
ok "unreadable input fails open"

reset; agent a1; printf '{"id":"a2",\n' >>"$D/tasks.jsonl"; shell b1; seen '["a1","b1"]'
s=$(sg status --json --session s1 2>"$work/err")
[ "$(field .skipped_lines "$s")" = 1 ] && [ "$(field '.tasks|length' "$s")" = 2 ] && grep -q 1 "$work/err" || fail "corrupt line is skipped: $s"
ok "corrupt line is skipped"

reset; agent a1; printf '{"id":"a9","kind":"subagent","started":1}\r\n' >>"$D/tasks.jsonl"; seen '["a9"]'
s=$(sg status --json --session s1)
[ "$(field '.tasks[0].id' "$s")" = a9 ] && [ "$(field '.tasks[0].kind' "$s")" = subagent ] || fail "CR in ledger values is ignored: $s"
ok "CR in ledger values is ignored"

reset; record Agent '{"status":"completed","agentId":"a2"}'
[ "$(field .hooked "$(sg status --json --session s1)")" = true ] || fail "hooked marks the session"
[ "$(field .hooked "$(sg status --json --session s9)")" = false ] || fail "hooked is false for an unseen session"
ok "hooked marks the session"

reset; agent a1; sg disable; agent a2
[ "$(lines "$D/tasks.jsonl")" = 1 ] || fail "disabled is inert (record)"
ok "disabled is inert (record)"

reset; agent a1; shell b1; seen '["a1","b1"]'
[ "$(field '.tasks|length' "$(sg status --json --session s1)")" = 2 ] || fail "status --json lists running tasks"
ok "status --json lists running tasks"
