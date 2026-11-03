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

# --- stop-check: 終了の関所・残った予約・歯止め ---

# bt id:type ...: running の background_tasks を作る。
bt() { local a out=; for a in "$@"; do out+="${out:+,}{\"id\":\"${a%%:*}\",\"type\":\"${a#*:}\",\"status\":\"running\",\"description\":\"d\"}"; done; echo "[$out]"; }
# stop <background_tasks> [session_crons] [prompt_id] [stop_hook_active]
stop() {
  jq -nc --argjson b "$1" --argjson c "${2:-[]}" --arg p "${3:-p1}" --argjson a "${4:-false}" \
    '{session_id:"s1",hook_event_name:"Stop",stop_hook_active:$a,prompt_id:$p,background_tasks:$b,session_crons:$c}' | sg stop-check
}
# 発火時刻 fire の ScheduleWakeup を記録する。cron_of は本体が session_crons に出す形の予約を返す。
wake() { post ScheduleWakeup "{\"scheduledFor\":$(($1 * 1000))}" | jq -c --arg k "${2:-tu1}" '.tool_use_id=$k' | sg record; }
cron_of() { local mh; mh=$(date -d "@$1" '+%-M %-H'); echo "{\"id\":\"x$1\",\"schedule\":\"$mh * * *\",\"recurring\":false,\"prompt\":\"p\"}"; }
decision() { if [ -n "$1" ]; then field '.decision // "none"' "$1"; else echo none; fi; }
reason() { field '.reason // ""' "$1"; }
has() { grep -q -- "$1" <<<"$2"; }

reset; out=$(stop '[]')
[ -z "$out" ] && [ ! -e "$D" ] || fail "empty session is silent"
ok "empty session is silent"

reset; agent a1; out=$(stop '[]')
[ -z "$out" ] && [ "$(field '.running|length' "$(last "$D/seen.jsonl")")" = 0 ] || fail "empty Stop with a ledger writes an empty seen"
ok "empty Stop with a ledger writes an empty seen"

l=$(last "$D/turns.jsonl")
[ "$(field .event "$l")" = stop ] && [ "$(field .at "$l")" = "$NOW" ] || fail "stop writes a turn boundary: $l"
ok "stop writes a turn boundary"

reset; STALL_GUARD_NOW=$((NOW - 1500)) agent a1; out=$(stop "$(bt a1:subagent)")
[ "$(decision "$out")" = block ] && has a1 "$(reason "$out")" && has 25 "$(reason "$out")" || fail "running task without a wakeup is blocked: $out"
ok "running task without a wakeup is blocked"

reset; agent a1; f=$((NOW + 1200)); wake $f; out=$(stop "$(bt a1:subagent)" "[$(cron_of $f)]")
[ -z "$out" ] || fail "wakeup within interval passes: $out"
ok "wakeup within interval passes"

reset; agent a1; f=$((NOW + 1500)); wake $f
[ "$(decision "$(stop "$(bt a1:subagent)" "[$(cron_of $f)]")")" = block ] || fail "wakeup beyond interval is blocked"
ok "wakeup beyond interval is blocked"

reset; agent a1; f=$((NOW - 60)); wake $f
[ "$(decision "$(stop "$(bt a1:subagent)" "[$(cron_of $f)]")")" = block ] || fail "past fire does not satisfy"
ok "past fire does not satisfy"

reset; agent a1; record CronCreate "{\"id\":\"c1\",\"recurring\":true,\"nextFireAt\":$(((NOW - 60) * 1000))}"
[ "$(decision "$(stop "$(bt a1:subagent)" '[{"id":"c1","schedule":"*/10 * * * *","recurring":true}]')")" = block ] || fail "recurring cron after its first fire is blocked"
reset; agent a1; record CronCreate "{\"id\":\"c1\",\"recurring\":true,\"nextFireAt\":$(((NOW + 600) * 1000))}"
[ -z "$(stop "$(bt a1:subagent)" '[{"id":"c1","schedule":"*/10 * * * *","recurring":true}]')" ] || fail "recurring cron before its first fire passes"
ok "recurring cron after its first fire is blocked"

reset; agent a1
[ "$(decision "$(stop "$(bt a1:subagent)" '[{"id":"c9","schedule":"*/10 * * * *","recurring":true}]')")" = block ] || fail "unrelated cron does not satisfy"
ok "unrelated cron does not satisfy"

reset; agent a1; f=$((NOW + 600)); wake $f; printf '{"id":"a1","interval_sec":300,"watch":[],"at":%s}\n' "$NOW" >>"$D/deadlines.jsonl"
[ "$(decision "$(stop "$(bt a1:subagent)" "[$(cron_of $f)]")")" = block ] || fail "deadline shortens the interval"
ok "deadline shortens the interval"

reset; shell b1; printf '{"id":"b1","at":%s}\n' "$NOW" >>"$D/keeps.jsonl"
[ -z "$(stop "$(bt b1:shell)")" ] || fail "keep passes a shell without a wakeup"
ok "keep passes a shell without a wakeup"

reset; STALL_GUARD_NOW=$((NOW - 7200)) agent a1
[ "$(decision "$(stop "$(bt a1:subagent)")")" = block ] || fail "two-hour task is blocked without a wakeup"
f=$((NOW + 1200)); wake $f
[ -z "$(stop "$(bt a1:subagent)" "[$(cron_of $f)]" p2)" ] || fail "two-hour task passes with a wakeup"
ok "two-hour task keeps the same rule"

reset; agent a1
[ "$(decision "$(stop "$(bt a1:subagent)" '[]' p1 true)")" = block ] || fail "wake turn with stop_hook_active is still judged"
ok "wake turn with stop_hook_active is still judged"

reset; out=$(stop "$(bt x1:subagent)")
[ "$(decision "$out")" = block ] && grep -q '"x1"' "$D/tasks.jsonl" || fail "unknown running task is adopted: $out"
ok "unknown running task is adopted"

reset; agent a1; printf '{"id":\n' >>"$D/tasks.jsonl"; out=$(stop "$(bt a1:subagent)" 2>"$work/err")
[ "$(decision "$out")" = block ] && grep -q 1 "$work/err" || fail "corrupt line does not hide the rest: $out"
ok "corrupt line does not hide the rest"

reset; agent a1
[ "$(decision "$(stop "$(bt a1:subagent)")")" = block ] && [ "$(decision "$(stop "$(bt a1:subagent)")")" = block ] || fail "two unshrunk blocks"
[ -z "$(stop "$(bt a1:subagent)")" ] && [ "$(lines "$D/released.jsonl")" = 1 ] || fail "release after two unshrunk blocks"
reset; agent a1; agent a2
[ "$(decision "$(stop "$(bt a1:subagent a2:subagent)")")" = block ] && [ "$(decision "$(stop "$(bt a1:subagent)")")" = block ] \
  && [ "$(decision "$(stop "$(bt a1:subagent)")")" = block ] || fail "a shrunk block restarts the count"
ok "release after two unshrunk blocks"

reset; agent a1; shell b1
jq -nc '{session_id:"s1",hook_event_name:"PermissionDenied",tool_name:"ScheduleWakeup",tool_input:{},tool_use_id:"tu2",reason:"denied"}' | sg record --failed
r=$(reason "$(stop "$(bt a1:subagent)")")
has PermissionDenied "$r" && ! has Monitor "$r" && ! has keep "$r" || fail "failed wakeup reports the failure without Monitor: $r"
r=$(reason "$(stop "$(bt b1:shell)" '[]' p9)")
has keep "$r" || fail "shell reason offers keep: $r"
ok "failed wakeup reports the failure without Monitor"

reset; agent a1; f=$((NOW + 1200)); wake $f; out=$(stop "$(bt a1:subagent)" "[$(cron_of $f)]")
[ "$(field '.observed_with|join(",")' "$(last "$D/observed.jsonl")")" = a1 ] || fail "first Stop records observed_with"
ok "first Stop records observed_with"

out=$(stop '[]' "[$(cron_of $f)]" p2); r=$(reason "$out")
[ "$(decision "$out")" = block ] && has a1 "$r" && has "$(date -d "@$f" '+%H:%M')" "$r" && ! has 'stop:true' "$r" && ! has CronDelete "$r" \
  && grep -q '"detected"' "$D/leftover.jsonl" && grep -q '"via":"stop"' "$D/leftover.jsonl" || fail "leftover wakeup is reported: $out"
[ -z "$(stop '[]' "[$(cron_of $f)]" p3)" ] || fail "leftover wakeup is reported once"
ok "leftover wakeup is reported once as a fact"

reset; f=$((NOW + 1200)); wake $f; agent a1; seen '["a1"]'
[ -z "$(stop '[]' "[$(cron_of $f)]")" ] || fail "loop wakeup without work is not reported"
ok "loop wakeup without work is not reported"

reset; shell b1; stop "$(bt b1:shell)" '[]' p1 >/dev/null; f=$((NOW + 1200)); wake $f
[ "$(field '.tasks_at_create|join(",")' "$(last "$D/wakeups.jsonl")")" = b1 ] || fail "completion-notice wakeup has b1 as a candidate"
[ -z "$(stop '[]' "[$(cron_of $f)]" p2)" ] && [ "$(field '.observed_with|length' "$(last "$D/observed.jsonl")")" = 0 ] || fail "wakeup made in the completion-notice turn is not reported"
ok "wakeup made in the completion-notice turn is not reported"

reset; for i in 1 2 3 4 5 6 7; do agent a$i; done
set_of() { local i out=(); for ((i = 1; i <= $1; i++)); do out+=("a$i:subagent"); done; bt "${out[@]}"; }
for n in 7 6 5 4 3 2; do [ "$(decision "$(stop "$(set_of $n)")")" = block ] || fail "six blocks per prompt ($n)"; done
[ -z "$(stop "$(set_of 1)")" ] && grep -q '"cause":"total"' "$D/released.jsonl" || fail "six blocks per prompt at most"
[ "$(decision "$(stop "$(set_of 1)" '[]' p2)")" = block ] || fail "a new prompt restarts the total"
ok "six blocks per prompt at most"

# 台帳ディレクトリが無い (inject が turns を書いていない) 状態から、同じ prompt_id で起動と block を続ける。
xset() { local i out=(); for ((i = 1; i <= $1; i++)); do out+=("x$i:subagent"); done; bt "${out[@]}"; }
reset
for n in 7 6 5 4 3 2; do [ "$(decision "$(stop "$(xset $n)" '[]' p7)")" = block ] || fail "six blocks on the first launching turn ($n)"; done
[ ! -e "$D/turns.jsonl" ] || [ "$(grep -c '"prompt"' "$D/turns.jsonl")" = 0 ] || fail "no prompt boundary was recorded"
[ -z "$(stop "$(xset 1)" '[]' p7)" ] || fail "six blocks on the first launching turn"
ok "six blocks on the first launching turn"

reset; shell b1 true
[ -z "$(stop "$(bt b1:shell)")" ] && [ "$(field '.tasks[0].id' "$(sg status --json --session s1)")" = b1 ] || fail "final-response shell is not blocked"
ok "final-response shell is not blocked"

reset; agent a1; r=$(reason "$(AGENT_DELEGATED_SESSION=1 stop "$(bt a1:subagent)")")
[ -n "$r" ] && ! has Monitor "$r" && ! has ScheduleWakeup "$r" && ! has TaskOutput "$r" || fail "delegated wait route: $r"
ok "delegated wait route"

reset; agent a1; jq -nc '{session_id:"s2",hook_event_name:"PostToolUse",tool_name:"Agent",tool_response:{status:"async_launched",agentId:"z1"}}' | sg record
[ -z "$(stop '[]')" ] || fail "other session's tasks are ignored"
ok "other session's tasks are ignored"

reset; agent a1; sg disable >/dev/null
[ -z "$(stop "$(bt a1:subagent)")" ] && [ "$(lines "$D/crons.jsonl")" = 1 ] && [ ! -e "$D/seen.jsonl" ] || fail "disabled is inert (stop-check)"
ok "disabled is inert (stop-check)"

# --- watch: 見張り (実時刻で動かす) ---

export STALL_GUARD_WATCH_PERIOD=1 STALL_GUARD_ARGV_FILE="$work/argv"
unset CLAUDE_PID
argv() { printf '%s\0' "$@" >"$STALL_GUARD_ARGV_FILE"; }
argv claude --input-format stream-json --output-format stream-json
rnow() { printf '%(%s)T\n' -1; }
# watch_bg <background_tasks> [番号]: 見張りを背景で起動し、pid を W に入れる。
watch_bg() {
  jq -nc --argjson b "$1" '{session_id:"s1",hook_event_name:"Stop",stop_hook_active:false,prompt_id:"p1",background_tasks:$b,session_crons:[]}' >"$work/win${2:-1}.json"
  env -u STALL_GUARD_NOW bash "$HOOK" watch <"$work/win${2:-1}.json" 2>"$work/w${2:-1}.err" &
  W=$!
}
# ends_within <秒> <pid>: その時間内に終われば終了コードを WC に入れて真。
ends_within() {
  local i=0 n=$(($1 * 5))
  WC=
  while [ $i -lt $n ]; do
    if ! kill -0 "$2" 2>/dev/null; then wait "$2" && WC=0 || WC=$?; return 0; fi
    sleep 0.2; i=$((i + 1))
  done
  return 1
}
# stop_watch <pid>: 動き続けた見張りを無効の印で止める (止まらなければ kill)。
stop_watch() { : >"$STALL_GUARD_STATE_DIR/disabled"; ends_within 3 "$1" || kill "$1" 2>/dev/null; rm -f "$STALL_GUARD_STATE_DIR/disabled"; }

reset; jq -nc '{session_id:"s1",hook_event_name:"Stop",prompt_id:"p1",background_tasks:[],session_crons:[]}' | env -u STALL_GUARD_NOW bash "$HOOK" watch || fail "empty session watch exits 0"
[ ! -e "$D" ] || fail "empty session is silent (watch)"
ok "empty session is silent (watch)"

reset; watch_bg "$(bt a1:subagent)"
! ends_within 2 $W || fail "watcher arms from its own stdin before seen exists (ended $WC)"
stop_watch $W
ok "watcher arms from its own stdin before seen exists"

# interval を過ぎても余裕 (120 秒) の内は、予約の起床を優先して起こさない。
reset; STALL_GUARD_NOW=$(($(rnow) - 3000)) agent a1; t=$(($(rnow) - 1260)); printf '{"at":%s,"event":"stop"}\n' "$t" >>"$D/turns.jsonl"
STALL_GUARD_WATCH_STARTED=$t watch_bg "$(bt a1:subagent)"
! ends_within 2 $W || fail "the margin leaves room for the scheduled wake-up (ended $WC)"
stop_watch $W
ok "the margin leaves room for the scheduled wake-up"

reset; STALL_GUARD_NOW=$(($(rnow) - 3000)) agent a1; t=$(($(rnow) - 1321)); printf '{"at":%s,"event":"stop"}\n' "$t" >>"$D/turns.jsonl"
STALL_GUARD_WATCH_STARTED=$t watch_bg "$(bt a1:subagent)"
ends_within 2 $W && [ "$WC" = 2 ] && grep -q a1 "$work/w1.err" && [ "$(field .event "$(last "$D/turns.jsonl")")" = watch ] || fail "due task wakes the model (${WC:-running})"
ok "due task wakes the model"

reset; agent a1; printf '{"at":%s,"event":"stop"}\n' "$(($(rnow) - 5000))" >>"$D/turns.jsonl"
watch_bg "$(bt a1:subagent)"
! ends_within 3 $W || fail "stale turns do not wake at once (ended $WC)"
stop_watch $W
ok "stale turns do not wake at once"

reset; watch_bg "$(bt a1:subagent)"
! ends_within 3 $W || fail "empty turns do not wake at once (ended $WC)"
stop_watch $W
ok "empty turns do not wake at once"

reset; agent a1; watch_bg "$(bt a1:subagent)"; sleep 0.5
STALL_GUARD_NOW=$(rnow) stop '[]' >/dev/null
ends_within 2 $W && [ "$WC" = 0 ] || fail "empty seen ends the watcher (${WC:-running})"
ok "empty seen ends the watcher"

reset; agent a1; seen '["a1"]'; watch_bg "$(bt a1:subagent)"; sleep 0.5
printf '{"id":"a1","by":"SubagentStop","at":%s}\n' "$(rnow)" >>"$D/ended.jsonl"
ends_within 2 $W && [ "$WC" = 0 ] || fail "ended subagent is not watched (${WC:-running})"
ok "ended subagent is not watched"

reset; agent a1; watch_bg "$(bt a1:subagent)"; w1=$W; sleep 0.5; watch_bg "$(bt a1:subagent)" 2; w2=$W
ends_within 3 $w1 && [ "$WC" = 0 ] && kill -0 $w2 && [ "$(jq -r .pid "$D/watch.lock" | tr -d '\r')" = "$w2" ] || fail "newer watcher takes over"
stop_watch $w2
ok "newer watcher takes over"

reset; shell b1; printf '{"id":"b1","at":%s}\n' "$NOW" >>"$D/keeps.jsonl"
watch_bg "$(bt b1:shell)"; ends_within 1 $W && [ "$WC" = 0 ] || fail "kept shell is not watched"
ok "kept shell is not watched"

reset; AGENT_DELEGATED_SESSION=1 watch_bg "$(bt a1:subagent)"; ends_within 1 $W && [ "$WC" = 0 ] || fail "delegated session does not watch"
ok "delegated session does not watch"

reset; sg disable >/dev/null; watch_bg "$(bt a1:subagent)"; ends_within 1 $W && [ "$WC" = 0 ] || fail "disabled is inert (watch at start)"
reset; watch_bg "$(bt a1:subagent)"; sleep 0.5; sg disable >/dev/null
ends_within 2 $W && [ "$WC" = 0 ] || fail "disabled is inert (running watcher)"
ok "disabled is inert (watch)"

reset; argv claude -p --output-format json hello
watch_bg "$(bt a1:subagent)"; ends_within 2 $W && [ "$WC" = 0 ] || fail "text print session does not watch (${WC:-running})"
[ "$(field .text_print "$(last "$D/argv.jsonl")")" = true ] || fail "text print result is kept in the ledger"
argv claude -p --input-format stream-json
watch_bg "$(bt a1:subagent)"; ends_within 2 $W && [ "$WC" = 0 ] && [ "$(lines "$D/argv.jsonl")" = 1 ] || fail "second watcher reads the kept argv result"
ok "text print session does not watch"

reset; argv claude --print --input-format stream-json --output-format stream-json
watch_bg "$(bt a1:subagent)"
! ends_within 2 $W || fail "stream-json print is watched (ended $WC)"
stop_watch $W
ok "stream-json print is watched"

reset; rm -f "$STALL_GUARD_ARGV_FILE"
watch_bg "$(bt a1:subagent)"
! ends_within 2 $W || fail "unreadable argv keeps watching (ended $WC)"
stop_watch $W
[ "$(field .text_print "$(last "$D/argv.jsonl")")" = null ] || fail "unreadable argv is kept as unknown"
ok "unreadable argv keeps watching"

# --- inject・deadline・keep ---

inject() { jq -nc '{session_id:"s1",hook_event_name:"UserPromptSubmit",prompt_id:"p5",prompt:"続けて"}' | sg inject; }
ctx() { field '.hookSpecificOutput.additionalContext // ""' "$1"; }
cs() { CLAUDE_CODE_SESSION_ID=s1 sg "$@"; }

reset; out=$(inject)
[ -z "$out" ] && [ ! -e "$D" ] || fail "inject is silent without tasks"
ok "inject is silent without tasks"

reset; agent a1; seen '["a1"]'; printf 'start\n' >"$work/result.txt"
cs deadline a1 5 --watch "$work/result.txt" || fail "deadline with a watch path"
printf '0123456789' >>"$work/result.txt"
out=$(inject); c=$(ctx "$out")
[ "$(field .hookSpecificOutput.hookEventName "$out")" = UserPromptSubmit ] && has a1 "$c" && has '+10' "$c" && has 'result.txt' "$c" \
  && [ "$(field .event "$(last "$D/turns.jsonl")")" = prompt ] || fail "inject reports facts and growth: $out"
c=$(ctx "$(inject)")
has '+0' "$c" || fail "inject reports growth since the previous prompt: $c"
ok "inject reports facts and growth"

reset; agent a1; f=$((NOW + 1200)); wake $f
stop "$(bt a1:subagent)" "[$(cron_of $f)]" >/dev/null
[ "$(decision "$(stop '[]' "[$(cron_of $f)]" p2)")" = block ] || fail "leftover is blocked once at the transition"
[ -z "$(stop '[]' "[$(cron_of $f)]" p2)" ] || fail "an empty Stop after the transition stays silent"
c=$(ctx "$(inject)")
has "$(date -d "@$f" '+%H:%M')" "$c" && has a1 "$c" && ! has 'stop:true' "$c" && ! has CronDelete "$c" && grep -q '"via":"inject"' "$D/leftover.jsonl" \
  || fail "inject reports leftover wakeups: $c"
! has "$(date -d "@$f" '+%H:%M')" "$(ctx "$(inject)")" || fail "inject reports leftover wakeups once"
reset; agent a1; f=$((NOW + 1200)); wake $f
stop "$(bt a1:subagent)" "[$(cron_of $f)]" >/dev/null; stop '[]' "[$(cron_of $f)]" p2 >/dev/null; stop '[]' '[]' p3 >/dev/null
! has "$(date -d "@$f" '+%H:%M')" "$(ctx "$(inject)")" || fail "a cancelled leftover wakeup is not reported"
ok "inject reports leftover wakeups once"

reset; agent a1
for m in 0 31 x; do ! cs deadline a1 $m 2>/dev/null || fail "deadline rejects $m"; done
[ ! -e "$D/deadlines.jsonl" ] || fail "rejected deadlines are not kept"
! sg deadline a1 5 2>/dev/null || fail "deadline needs CLAUDE_CODE_SESSION_ID"
cs deadline a1 5 && [ "$(field .interval_sec "$(last "$D/deadlines.jsonl")")" = 300 ] || fail "deadline a1 5"
ok "deadline rejects out of range"

reset; agent a1; shell b1; seen '["a1","b1"]'
! cs keep a1 2>/dev/null || fail "keep rejects a subagent"
cs keep b1 || fail "keep accepts a shell"
has keep "$(ctx "$(inject)")" && [ "$(field '.tasks[] | select(.id=="b1") | .keep' "$(sg status --json --session s1)")" = true ] || fail "keep is shown in inject and status"
ok "keep rejects a subagent"

reset; agent a1
stop "$(bt a1:subagent)" >/dev/null; stop "$(bt a1:subagent)" >/dev/null; stop "$(bt a1:subagent)" >/dev/null
[ "$(lines "$D/released.jsonl")" = 1 ] || fail "a released prompt is recorded"
c=$(ctx "$(inject)")
has 'p1' "$c" || fail "released turn is reported: $c"
ok "released turn is reported"

reset; agent a1; seen '["a1"]'; n=$(lines "$D/turns.jsonl"); sg disable >/dev/null
[ -z "$(inject)" ] && [ "$(lines "$D/turns.jsonl")" = "$n" ] || fail "disabled is inert (inject)"
! cs deadline a1 5 2>/dev/null || [ ! -e "$D/deadlines.jsonl" ] || fail "disabled is inert (deadline)"
ok "disabled is inert (inject)"

# --- 登録: claude/settings.json と codex/hooks.json ---

CS="$HOOK_DIR/../../claude/settings.json"
CX="$HOOK_DIR/../../codex/hooks.json"
# reg <file> <event> <matcher か null> <コマンドの末尾の正規表現>: その登録が 1 つだけあれば真。
reg() {
  jq -e --arg ev "$2" --argjson m "$3" --arg re "stall-guard\\.sh $4\$" \
    '[.hooks[$ev][]? | select(.matcher == $m) | .hooks[] | select(.command | test($re))] | length == 1' "$1" >/dev/null
}
reg "$CS" PostToolUse '"Agent|Bash|ScheduleWakeup|CronCreate|TaskStop"' record \
  && reg "$CS" PostToolUseFailure '"ScheduleWakeup|CronCreate"' 'record --failed' \
  && reg "$CS" PermissionDenied '"ScheduleWakeup|CronCreate"' 'record --failed' \
  && reg "$CS" SubagentStop null record \
  && reg "$CS" UserPromptSubmit null inject \
  && reg "$CS" Stop null stop-check \
  && jq -e '[.hooks.Stop[].hooks[] | select(.command | test("stall-guard\\.sh watch$")) | select(.asyncRewake == true and .timeout == 2100)] | length == 1' "$CS" >/dev/null \
  || fail "registration matches the design (claude/settings.json)"
P='"collaborationspawn_agent|collaborationfollowup_task|collaborationinterrupt_agent|collaborationwait_agent"'
reg "$CX" PostToolUse "$P" '--cli codex record' \
  && reg "$CX" PreToolUse '"collaborationwait_agent"' '--cli codex pre-wait' \
  && reg "$CX" SubagentStart null '--cli codex subagent-start' \
  && reg "$CX" SubagentStop null '--cli codex subagent-stop' \
  && reg "$CX" Stop null '--cli codex stop-check' \
  && reg "$CX" UserPromptSubmit null '--cli codex inject' \
  || fail "registration matches the design (codex/hooks.json)"
# Codex の Windows の起動は、既存の hook と同じく invoke-git-bash-hook.ps1 経由で同じ引数を渡す。
jq -e --arg pre "& (Join-Path \$HOME '.agent-shared/bin/invoke-git-bash-hook.ps1') '" --arg suf "'" \
  '[.hooks[][] | .hooks[] | select(.command | test("stall-guard\\.sh"))
    | select(.timeout == 10 and .type == "command" and .commandWindows == ($pre + (.command | sub("^bash "; "")) + $suf))]
  | length == 6' "$CX" >/dev/null || fail "registration matches the design (Codex commandWindows)"
# 既存の出力ゲートと review-rounds の登録が残っている。
jq -e '[.hooks.Stop[].hooks[] | select(.command | test("output-gate-claude\\.sh stop"))] | length == 1' "$CS" >/dev/null \
  && jq -e '[.hooks.SubagentStop[] | select(.matcher != null) | .hooks[] | select(.command | test("review-rounds\\.sh stop"))] | length == 1' "$CS" >/dev/null \
  && jq -e '[.hooks.Stop[].hooks[] | select(.command | test("output-gate-codex\\.sh stop"))] | length == 1' "$CX" >/dev/null \
  && jq -e '[.hooks.SubagentStop[] | select(.matcher != null) | .hooks[] | select(.command | test("review-rounds\\.sh stop"))] | length == 1' "$CX" >/dev/null \
  || fail "registration keeps the output gate and review-rounds hooks"
ok "registration matches the design"
