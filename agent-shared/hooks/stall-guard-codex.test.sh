#!/usr/bin/env bash
# Codex 側の stall-guard を、偽の hook 入力 JSON とテスト内で書く最小の子の rollout で確かめる。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/stall-guard.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/stall-guard-codex-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
NOW=1793599980
export STALL_GUARD_STATE_DIR="$work/state" STALL_GUARD_NOW=$NOW STALL_GUARD_LOCK_WAIT=2
SID=s1
D="$STALL_GUARD_STATE_DIR/codex/s1"
R="$work/ra.jsonl"

fail() { echo "not ok: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
reset() { rm -rf "$STALL_GUARD_STATE_DIR" "$R"; SID=s1; }
cx() { bash "$HOOK" --cli codex "$@"; }
field() { jq -r "$1" <<<"$2" | tr -d '\r'; }
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
st() { cx status --json --session "$SID"; }
at() { STALL_GUARD_NOW=$((NOW + $1)); export STALL_GUARD_NOW; }

# --- 子の rollout (最小の JSONL) ---
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z; }
js() { if [ -n "${1:-}" ] && [ "$1" != null ]; then printf '"%s"' "$1"; else printf null; fi; }
meta() { printf '{"timestamp":"%s","type":"session_meta","payload":{"id":"x","agent_path":"%s"}}\n' "$(iso "$NOW")" "$2" >>"$1"; }
# started <file> <turn> <秒> [parent_turn_id initiating_agent_path] (後ろ 2 つが無ければ turn_attribution なし)
started() {
  local ta=null
  [ $# -ge 4 ] && ta="{\"turn_id\":\"$2\",\"parent_turn_id\":$(js "$4"),\"initiating_agent_path\":$(js "${5:-}")}"
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"task_started","turn_id":"%s","turn_attribution":%s}}\n' "$(iso $((NOW + $3)))" "$2" "$ta" >>"$1"
}
complete() { printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"task_complete","turn_id":"%s"}}\n' "$(iso $((NOW + $3)))" "$2" >>"$1"; }
aborted() { printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"turn_aborted","turn_id":"%s","reason":"interrupted"}}\n' "$(iso $((NOW + $3)))" "$2" >>"$1"; }

# --- hook の入力 ---
# post <tool> <tool_input> <tool_response> <turn> [agent_id]
post() {
  local extra=
  [ -n "${5:-}" ] && extra=",\"agent_id\":\"$5\",\"agent_type\":\"default\""
  printf '{"session_id":"%s","turn_id":"%s","hook_event_name":"PostToolUse","tool_name":"collaboration%s","tool_input":%s,"tool_response":%s%s}' \
    "$SID" "$4" "$1" "$2" "$3" "$extra" | cx record
}
spawn() { post spawn_agent "{\"task_name\":\"$1\"}" "\"{\\\"task_name\\\":\\\"${4:-/root}/$1\\\"}\"" "${2:-p1}" "${3:-}"; }
followup() { post followup_task "{\"target\":\"$1\"}" '""' "${2:-p1}"; }
# interrupt <target> <tool_response> <turn>
interrupt() { post interrupt_agent "{\"target\":\"$1\"}" "$2" "${3:-p1}"; }
waited() { post wait_agent "{\"timeout_ms\":$1}" '"{\"message\":\"Wait completed.\",\"timed_out\":false}"' "${2:-p1}" "${3:-}"; }
start() { printf '{"session_id":"%s","turn_id":"%s","transcript_path":"%s","hook_event_name":"SubagentStart","agent_id":"%s","agent_type":"default"}' "$SID" "$3" "$2" "$1" | cx subagent-start; }
# SubagentStop は rollout を読む契機にもなる (adv)。
adv() { printf '{"session_id":"%s","turn_id":"p1","agent_id":"%s","agent_transcript_path":"%s","hook_event_name":"SubagentStop","last_assistant_message":"x"}' "$SID" "${1:-A1}" "${2:-$R}" | cx subagent-stop; }

# 今のターン p1 で child_a を起動し、c1 の run が running の状態を作る。
child_a() {
  meta "$R" /root/child_a
  spawn child_a p1
  start A1 "$R" c1
  started "$R" c1 1 p1 /root
  adv
}
running_turns() { field '[.running[].turn_id]|join(",")' "$1"; }

# ===================== Task 5: 台帳・rollout の読み進め・status =====================

reset; child_a; s=$(st)
[ "$(running_turns "$s")" = c1 ] && [ "$(field '.running[0].accepted_turn' "$s")" = p1 ] && [ "$(field '.running[0].task_name' "$s")" = /root/child_a ] \
  && [ "$(field '.running[0].agent_id' "$s")" = A1 ] || fail "spawn then start opens a run: $s"
ok "spawn then start opens a run"

reset; meta "$R" /root/child_a
started "$R" p0 0 null null; complete "$R" p0 0; started "$R" p1 0 null null; aborted "$R" p1 0; started "$R" c1 1 p1 /root
spawn child_a p1; adv; s=$(st)
[ "$(running_turns "$s")" = c1 ] && [ "$(field '.unrecovered|length' "$s")" = 0 ] || fail "forked child keeps only its own runs: $s"
ok "forked child keeps only its own runs"

reset; meta "$R" /root/child_a; started "$R" p1 0; aborted "$R" p1 0; started "$R" c1 1
spawn child_a p1; start A1 "$R" c1; s=$(st)
[ "$(running_turns "$s")" = c1 ] && [ "$(field '.unrecovered|length' "$s")" = 0 ] || fail "boundary falls back to SubagentStart turn_id: $s"
ok "boundary falls back to SubagentStart turn_id"

reset; meta "$R" /root/child_a; started "$R" c1 1 p1 /elsewhere
spawn child_a p1; adv; at 200; s=$(st); at 0
[ "$(field '.children[0].boundary_seen' "$s")" = false ] && [ "$(field '.running|length' "$s")" = 0 ] \
  && [ "$(field '.pending[0].expired' "$s")" = false ] && [ "$(field '.pending[0].boundary_seen' "$s")" = false ] || fail "child without a boundary is reported: $s"
ok "child without a boundary is reported"

reset; child_a; complete "$R" c1 5; adv; s=$(st)
[ "$(field '.running|length' "$s")" = 0 ] && [ "$(field '.unrecovered|length' "$s")" = 0 ] || fail "task_complete closes the run as completed: $s"
ok "task_complete closes the run as completed"

reset; child_a; aborted "$R" c1 5; adv; s=$(st)
[ "$(field '.running|length' "$s")" = 0 ] && [ "$(field '.unrecovered[0].end' "$s")" = aborted ] && [ "$(field '.unrecovered[0].turn_id' "$s")" = c1 ] || fail "turn_aborted closes the run as aborted: $s"
ok "turn_aborted closes the run as aborted"

reset; child_a; complete "$R" c1 5; printf '%s' "$(tail -n 1 "$R")" >"$R.tmp"; head -n -1 "$R" >"$R.head"; cat "$R.head" "$R.tmp" >"$R"
adv; [ "$(field '.running|length' "$(st)")" = 1 ] || fail "partial last line is read next time (partial)"
printf '\n' >>"$R"; adv; [ "$(field '.running|length' "$(st)")" = 0 ] || fail "partial last line is read next time (completed)"
ok "partial last line is read next time"

reset; child_a; at 7200; adv; s=$(st); at 0
[ "$(running_turns "$s")" = c1 ] && [ "$(field '.running[0].elapsed_sec' "$s")" = 7200 ] || fail "silent rollout keeps the run: $s"
ok "silent rollout keeps the run"

reset; child_a; at 10; interrupt child_a '"{\"previous_status\":{\"running\":null}}"'; at 0; aborted "$R" c1 20; adv; s=$(st)
[ "$(field '.running|length' "$s")" = 0 ] && [ "$(field '.unrecovered[0].end' "$s")" = interrupted ] || fail "interrupt_agent closes the run as interrupted: $s"
reset; child_a; at 10; interrupt child_a '"{\"previous_status\":\"running\"}"'; at 0; s=$(st)
[ "$(field '.unrecovered[0].end' "$s")" = interrupted ] || fail "interrupt_agent closes the run as interrupted (string status): $s"
ok "interrupt_agent closes the run as interrupted"

reset; child_a; at 10; interrupt child_a '"{\"previous_status\":{\"completed\":\"DONE\"}}"'; at 0; s=$(st)
[ "$(running_turns "$s")" = c1 ] && [ "$(field '.unrecovered|length' "$s")" = 0 ] || fail "interrupt after completion does not close: $s"
ok "interrupt after completion does not close"

reset; child_a; complete "$R" c1 5; adv; at 10; followup child_a p2; at 0; s=$(st)
[ "$(field '.pending|length' "$s")" = 1 ] && [ "$(field '.pending[0].turn_id' "$s")" = p2 ] || fail "followup on an idle child stays pending (pending): $s"
started "$R" c2 15; adv; at 20; s=$(st); at 0
[ "$(field '.pending|length' "$s")" = 0 ] && [ "$(running_turns "$s")" = c2 ] && [ "$(field '.running[0].accepted_turn' "$s")" = p2 ] || fail "followup on an idle child stays pending until its run starts: $s"
ok "followup on an idle child stays pending until its run starts"

reset; child_a; at 10; followup child_a p1; at 0; s=$(st)
[ "$(field '.pending|length' "$s")" = 0 ] && [ "$(running_turns "$s")" = c1 ] || fail "followup on a running child joins the current run: $s"
ok "followup on a running child joins the current run"

reset; child_a; at 10; followup child_a p2; at 0; s=$(st)
[ "$(field '.running[0].accepted_turn' "$s")" = p2 ] && [ "$(field '.pending|length' "$s")" = 0 ] || fail "followup to a carried running child moves it to this turn: $s"
ok "followup to a carried running child moves it to this turn"

reset; child_a; complete "$R" c1 2; started "$R" c2 4 px /root; started "$R" c3 6 p2 /root; adv; at 10; followup child_a p2; at 0; s=$(st)
[ "$(field '[.running[]|select(.turn_id=="c3")|.accepted_turn]|join(",")' "$s")" = p2 ] \
  && [ "$(field '[.running[]|select(.turn_id=="c2")|.accepted_turn]|map(tostring)|join(",")' "$s")" = null ] || fail "parent_turn_id binds the acceptance: $s"
ok "parent_turn_id binds the acceptance"

c2_turn() { jq -r '[.runs[]|select(.turn_id=="c2")|.accepted_turn]|join(",")' "$D/fold.json" | tr -d '\r'; }
reset; child_a; complete "$R" c1 2; started "$R" c2 5; complete "$R" c2 8; adv; at 10; followup child_a p2; at 0; adv; s=$(st)
[ "$(field '.pending|length' "$s")" = 0 ] && [ "$(field '.unrecovered|length' "$s")" = 0 ] && [ "$(c2_turn)" = p2 ] || fail "start and end recorded before the followup PostToolUse: $s"
reset; child_a; complete "$R" c1 2; adv; at 10; followup child_a p2; at 0; started "$R" c2 5; complete "$R" c2 8; adv; s2=$(st)
[ "$s" = "$s2" ] && [ "$(c2_turn)" = p2 ] || fail "start and end recorded before the followup PostToolUse (reverse): $s2"
ok "start and end recorded before the followup PostToolUse"

reset; meta "$R" /root/child_a; start A1 "$R" c1; started "$R" c1 1 p1 /root; adv; spawn child_a p1; s=$(st)
[ "$(running_turns "$s")" = c1 ] && [ "$(field '.running[0].accepted_turn' "$s")" = p1 ] && [ "$(field '.pending|length' "$s")" = 0 ] || fail "spawn start recorded before the PostToolUse binds the same acceptance: $s"
reset; child_a; s2=$(st)
[ "$(field '.running' "$s")" = "$(field '.running' "$s2")" ] || fail "spawn start recorded before the PostToolUse (reverse): $s2"
ok "spawn start recorded before the PostToolUse binds the same acceptance"

# 読み進めが lock を持っている間 (テストが advance.lock を作って再現する) の record は待たずに追記する。
reset; child_a; complete "$R" c1 2; adv; started "$R" c2 5; mkdir "$D/advance.lock"
t0=$(date +%s%N); at 10; followup child_a p2; at 0; t1=$(date +%s%N)
[ $(((t1 - t0) / 1000000)) -lt 1500 ] && [ "$(lines "$D/accepts.jsonl")" = 2 ] || fail "record and advance interleaved: record waited for the lock"
rmdir "$D/advance.lock"; adv; s=$(st)
reset; child_a; complete "$R" c1 2; adv; started "$R" c2 5; adv; at 10; followup child_a p2; at 0; adv; s2=$(st)
[ "$s" = "$s2" ] && [ "$(running_turns "$s")" = c2 ] && [ "$(field '.running[0].accepted_turn' "$s")" = p2 ] || fail "record and advance interleaved: $s / $s2"
ok "record and advance interleaved"

reset; meta "$R" /root/child_a; started "$R" c1 1 p1 /root; complete "$R" c1 5; spawn child_a p1
adv & adv & wait
size=$(wc -c <"$R" | tr -d ' ')
[ "$(grep -c '"started"' "$D/runs.jsonl")" = 1 ] && [ "$(grep -c '"ended"' "$D/runs.jsonl")" = 1 ] \
  && [ "$(jq -s 'map(.offset)|max' "$D/offsets.jsonl" | tr -d '\r')" = "$size" ] || fail "parallel advances are idempotent: $(cat "$D/runs.jsonl")"
ok "parallel advances are idempotent"

reset; child_a; complete "$R" c1 5; started "$R" c1 6 p1 /root; adv; s=$(st)
[ "$(field '.running|length' "$s")" = 0 ] || fail "end is terminal: $s"
ok "end is terminal"

reset; child_a; spawn grand p1 A1 /root/child_a; waited 1200000 p1 A1
[ "$(jq -r .parent "$D/accepts.jsonl" | tr -d '\r' | tail -n 1)" = A1 ] && [ "$(lines "$D/waits.jsonl")" = 0 ] || fail "child calls are marked with their parent"
ok "child calls are marked with their parent"

reset; spawn child_b p1; at 60; s=$(st); at 121; s2=$(st); at 0
[ "$(field '.pending[0].expired' "$s")" = false ] && [ "$(field '.pending[0].expired' "$s2")" = true ] || fail "unstarted acceptance expires after 120 seconds: $s2"
ok "unstarted acceptance expires after 120 seconds"

reset; meta "$R" /root/child_z; started "$R" p1 0; aborted "$R" p1 0; started "$R" c1 1
at 3; start A9 "$R" c1; at 100; s=$(st); at 0
[ "$(running_turns "$s")" = c1 ] && [ "$(field '.running[0].accepted_turn' "$s")" = null ] && [ "$(field '.running[0].elapsed_sec' "$s")" = 97 ] \
  && [ "$(field '.unrecovered|length' "$s")" = 0 ] || fail "unknown child is adopted: $s"
ok "unknown child is adopted"

reset; child_a; printf '{"event":"started",\n' >>"$D/runs.jsonl"; s=$(st 2>"$work/err")
[ "$(running_turns "$s")" = c1 ] && [ "$(field .skipped_lines "$s")" = 1 ] && grep -q 1 "$work/err" || fail "corrupt line is skipped: $s"
ok "corrupt line is skipped"

reset; child_a; s=$(st)
[ "$(field '[has("session","hooked","children","running","unrecovered","pending","released")]|all' "$s")" = true ] && [ "$(field .hooked "$s")" = true ] \
  || fail "status shape: $s"
[ "$(field .hooked "$(cx status --json --session s9)")" = false ] || fail "status shape (unhooked)"
ok "status shape"

reset; SID=s2; child_a; SID=s1; s=$(st)
[ "$(field '.running|length' "$s")" = 0 ] && [ "$(field '.children|length' "$s")" = 0 ] || fail "other session's tasks are ignored: $s"
ok "other session's tasks are ignored"
