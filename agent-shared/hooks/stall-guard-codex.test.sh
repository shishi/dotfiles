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

# ===================== Task 6: stop-check・pre-wait・inject =====================

stop() { printf '{"session_id":"%s","turn_id":"%s","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"x"}' "$SID" "$1" | cx stop-check; }
# prewait <timeout_ms> <turn> [agent_id]
prewait() {
  local extra=
  [ -n "${3:-}" ] && extra=",\"agent_id\":\"$3\",\"agent_type\":\"default\""
  printf '{"session_id":"%s","turn_id":"%s","hook_event_name":"PreToolUse","tool_name":"collaborationwait_agent","tool_input":{"timeout_ms":%s}%s}' "$SID" "$2" "$1" "$extra" | cx pre-wait
}
inject() { printf '{"session_id":"%s","turn_id":"%s","hook_event_name":"UserPromptSubmit","prompt":"x"}' "$SID" "$1" | cx inject; }
ctx() { field '.hookSpecificOutput.additionalContext' "$1"; }
blocked() { [ "$(field .decision "$1")" = block ]; }
delegator_fails() { [ "$(field '(.running|length>0) or (.unrecovered|length>0) or (.pending|length>0)' "$1")" = true ]; }

reset; a=$(stop p1); b=$(prewait 10000 p1); c=$(inject p1)
[ -z "$a$b$c" ] && [ ! -e "$D" ] || fail "empty session is silent: $a$b$c"
ok "empty session is silent"

reset; child_a; out=$(stop p1)
blocked "$out" && [[ "$(field .reason "$out")" == *"/root/child_a"* ]] && [[ "$(field .reason "$out")" == *180000* ]] || fail "run accepted in this turn blocks the turn: $out"
ok "run accepted in this turn blocks the turn"

reset; child_a; at 180; out=$(waited 180000); at 181; prompt=$(inject p2); at 0
[ -z "$out$prompt" ] || fail "lifecycle-only wait and prompt before observation due are silent: $out$prompt"
ok "lifecycle-only wait and prompt before observation due are silent"

reset; child_a; at 180
printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"Reasoning","id":"empty-reasoning","summary_text":[],"raw_content":[]}}}' \
  '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"SubAgentActivity","model":null,"reasoning_effort":null,"id":"activity","kind":"spawn","agent_thread_id":"child","agent_path":"/root/child_a"}}}' >>"$R"
out=$(waited 180000)
[ -z "$out" ] || fail "native items without substantive content do not notify before the deadline: $out"
printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"Reasoning","id":"real-reasoning","summary_text":["native summary evidence"],"raw_content":["native raw evidence"]}}}' \
  '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"AgentMessage","id":"native-message","content":[{"type":"Text","text":"native assistant evidence"}]}}}' \
  '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"CommandExecution","id":"native-command","command":["test-command"],"status":"Completed","aggregated_output":"native command result","exit_code":0}}}' >>"$R"
out=$(waited 180000)
for text in 'native summary evidence' 'native raw evidence' 'native assistant evidence' 'native command result'; do
  [[ "$(ctx "$out")" == *"$text"* ]] || fail "native item content remains available: $text / $out"
done
printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"AgentMessage","id":"paired-message","content":[{"type":"Text","text":"paired assistant evidence"}]}}}' \
  '{"type":"response_item","payload":{"type":"message","id":"paired-message","role":"assistant","content":[{"type":"output_text","text":"paired assistant evidence"}]}}' >>"$R"
out=$(waited 180000)
[ "$(ctx "$out" | grep -o 'paired assistant evidence' | wc -l)" = 1 ] || fail "native and canonical records of the same item notify once: $out"
printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UnknownEvidence","id":"unknown-item","result":"unknown native evidence"}}}' >>"$R"
out=$(waited 180000)
[[ "$(ctx "$out")" == *"unknown native evidence"* ]] || fail "unknown native evidence remains available: $out"
printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"AgentMessage","id":"split-message","content":[{"type":"Text","text":"split assistant evidence"}]}}}' >>"$R"
out=$(waited 180000)
[[ "$(ctx "$out")" == *"split assistant evidence"* ]] || fail "native content is notified before its canonical record arrives: $out"
printf '%s\n' '{"type":"response_item","payload":{"type":"message","id":"split-message","role":"assistant","content":[{"type":"output_text","text":"split assistant evidence"}]}}' >>"$R"
out=$(waited 180000)
[ -z "$out" ] || fail "the same item across an observation offset is not notified twice: $out"
printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"CommandExecution","id":"native-command","command":["test-command"],"status":"Completed","aggregated_output":"updated native command result","exit_code":0}}}' >>"$R"
out=$(waited 180000)
[[ "$(ctx "$out")" == *"updated native command result"* ]] || fail "changed substantive output on an existing item is not suppressed: $out"
at 0
ok "native items notify substantive content once and retain unknown evidence"

reset; child_a
for ((iteration = 1; iteration <= 50; iteration++)); do
  jq -nc --argjson cycle "$iteration" '[range(0; 8)][] as $i
    | {type:"event_msg",payload:{type:"item_completed",item:{type:"AgentMessage",id:"cycle-\($cycle)-\($i)",
        content:[{type:"Text",text:("cycle \($cycle) item \($i) " + ("x" * 280))}]}}}' >>"$R"
  at $((iteration * 180)); out=$(waited 180000)
  [[ "$(ctx "$out")" == *"cycle $iteration item 7"* ]] || fail "long observation history retains fresh content at cycle $iteration: $out"
done
at 0
ok "long observation history retains fresh content"

reset; child_a; at 1200; out=$(inject p2); at 0
[[ "$(ctx "$out")" == *c1* ]] || fail "observation deadline still requests a content check: $out"
at 1201; out=$(inject p3); at 0
[ -z "$out" ] || fail "a delivered observation postpones the next check: $out"
ok "observation deadline requests a check once per interval"

# 子の rollout の内容 (発言・ツールの呼出し・結果) を示し、更新時刻では示さない。
reset; child_a
printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"差分の 3 件目を照合した"}]}}' \
  '{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"rg -n review src"}}' \
  '{"type":"response_item","payload":{"type":"function_call_output","output":"src/a.rb:3: review"}}' \
  '{"type":"response_item","payload":{"type":"reasoning","encrypted_content":"gAAAA"}}' >>"$R"
out=$(stop p1); r=$(field .reason "$out"); at 1200; c=$(ctx "$(inject p2)"); at 0
for t in "$r" "$c"; do
  [[ "$t" == *"差分の 3 件目を照合した"* && "$t" == *"[tool exec] rg -n review src"* && "$t" == *"src/a.rb:3: review"* \
    && "$t" != *gAAAA* && "$t" != *最終更新* ]] || fail "run facts show the child's content: $t"
done
ok "run facts show the child's content"

# wait_agent から戻ると、その時点の子の内容を示す (待機が内容の確認点になる)。
reset; child_a
printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"4 件目を確認中"}]}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[ "$(field .hookSpecificOutput.hookEventName "$out")" = PostToolUse ] && [[ "$(field .hookSpecificOutput.additionalContext "$out")" == *"4 件目を確認中"* ]] \
  || fail "returning from wait_agent shows the child's content: $out"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[ -z "$out" ] || fail "unchanged child content is not repeated after another wait: $out"
printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":42}}}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[ -z "$out" ] || fail "new lifecycle metadata is not a new progress observation: $out"
printf '%s\n' '{"type":"response_item","payload":{"type":"function_call_output","output":"new substantive result"}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[[ "$(ctx "$out")" == *"new substantive result"* && "$(ctx "$out")" != *"4 件目を確認中"* ]] || fail "only new substantive content is delivered after another wait: $out"
printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ordinary progress"}]}}' \
  '{"type":"custom_progress","payload":{"message":"unknown structured evidence"}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[[ "$(ctx "$out")" == *"unknown structured evidence"* ]] || fail "unknown rollout records retain their content beside known messages: $out"
printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"after usage"}]}}' \
  '{"timestamp":"2026-11-09T05:23:32.071Z","ordinal":21,"type":"token_usage_record","payload":{"thread_id":"01a1bec2-d1bb","turn_id":"01a1bec2-d1de","usage":{"input_tokens":42}}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[[ "$(ctx "$out")" == *"after usage"* && "$(ctx "$out")" != *token_usage_record* ]] || fail "records with only identifiers and numbers are not shown as progress: $out"
printf '%s\n' '{"type":"custom_progress","payload":{"message":"六件目を確認中","id":"01a1bec2-d1bb"}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[[ "$(ctx "$out")" == *"六件目を確認中"* ]] || fail "unknown records keep Japanese text without spaces: $out"
complete "$R" c1 5; out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
[ -z "$out" ] || fail "returning from wait_agent after the run ended is silent: $out"
reset; child_a
printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"5 件目を確認中"}]}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p2)
[[ "$(field .hookSpecificOutput.additionalContext "$out")" == *"5 件目を確認中"* ]] || fail "returning from wait_agent shows a carried-over child's content: $out"
ok "returning from wait_agent shows the child's content"

# 子の rollout に 4 MiB を超える 1 行が来ても、その後の進捗を示し、大きな行の断片を示さない。
reset; child_a
{ printf '%s' '{"type":"response_item","payload":{"type":"function_call_output","output":"'; head -c 5000000 /dev/zero | tr '\0' 'q'; printf '%s\n' '"}}'; } >>"$R"
printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"大きな出力のあと 6 件目を確認中"}]}}' >>"$R"
out=$(post wait_agent '{"timeout_ms":180000}' '{"status":{}}' p1)
c=$(field .hookSpecificOutput.additionalContext "$out")
[[ "$c" == *"大きな出力のあと 6 件目を確認中"* && "$c" != *qqqqqqqq* ]] || fail "returning from wait_agent after a line over 4 MiB shows the following progress: $(head -c 300 <<<"$c")"
ok "returning from wait_agent after a line over 4 MiB shows the following progress"

reset; child_a
jq -nc --arg text "$(head -c 2000 /dev/zero | tr '\0' x)" '{type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:$text}]}}' >>"$R"
waited 180000 >/dev/null
head -n 2 "$R" >"$R.replacement"; mv "$R.replacement" "$R"
printf '%s\n' '{"type":"response_item","payload":{"type":"function_call_output","output":"replacement child output"}}' >>"$R"
out=$(waited 180000)
[[ "$(ctx "$out")" == *"replacement child output"* ]] || fail "a replaced rollout is read from its beginning: $out"
printf '%s\n' '{"type":"response_item","payload":{"type":"function_call_output","output":"latest appended output"}}' >>"$R"
out=$(waited 180000)
[[ "$(ctx "$out")" == *"latest appended output"* && "$(ctx "$out")" != *"replacement child output"* ]] || fail "a replaced rollout continues from its latest observation: $out"
ok "a replaced rollout continues from its latest observation"

reset; child_a; complete "$R" c1 5; adv; out=$(stop p1)
[ -z "$out" ] || fail "closed run does not: $out"
ok "closed run does not"

reset; child_a; a=$(stop p2); b=$(prewait 10000 p2); c=$(inject p2)
[ -z "$a$b$c" ] || fail "carried-over run does not block: $a$b / $c"
ok "carried-over run does not block"

reset; child_a; out=$(prewait 10000 p1); out2=$(prewait 1200000 p1)
[ "$(field .hookSpecificOutput.permissionDecision "$out")" = deny ] && [[ "$(field .hookSpecificOutput.permissionDecisionReason "$out")" == *180000* ]] \
  && [ -z "$out2" ] || fail "short wait is denied: $out / $out2"
ok "short wait is denied"

reset; child_a; out=$(prewait 10000 p1 A1)
[ -z "$out" ] || fail "child wait is not denied: $out"
stop p1 >/dev/null; waited 1200000 p1 A1; stop p1 >/dev/null; waited 1200000 p1 A1; out=$(stop p1)
[ -z "$out" ] && [ "$(lines "$D/released.jsonl")" = 1 ] || fail "child wait is not denied and does not count: $out"
ok "child wait is not denied and does not count"

reset; RG="$work/rg.jsonl"; rm -f "$RG"; meta "$RG" /root/child_a/grand; spawn grand c1 A1 /root/child_a; start G1 "$RG" g1
started "$RG" g1 1 c1 /root/child_a; adv G1 "$RG"; out=$(stop c1); out2=$(stop p1)
[ "$(field '.running[0].parent' "$(st)")" = A1 ] && [ -z "$out$out2" ] || fail "grandchild run does not block the parent: $out$out2"
ok "grandchild run does not block the parent"

reset; child_a; a=$(stop p1); waited 1200000 p1; b=$(stop p1); waited 1200000 p1; c=$(stop p1)
blocked "$a" && blocked "$b" && blocked "$c" || fail "compliant wait resets the brake: $c"
ok "compliant wait resets the brake"

reset; child_a; a=$(stop p1); b=$(stop p1); waited 10000 p1; c=$(stop p1)
blocked "$a" && blocked "$b" && [ -z "$c" ] && [ "$(lines "$D/released.jsonl")" = 1 ] && [ "$(field '.running[0].released' "$(st)")" = true ] \
  || fail "two non-compliant blocks release the turn: $c"
ok "two non-compliant blocks release the turn"

reset; child_a; stop p1 >/dev/null; waited 60000 p1; stop p1 >/dev/null; waited 60000 p1; out=$(stop p1)
[ -z "$out" ] || fail "timed_out false does not count as compliance: $out"
ok "timed_out false does not count as compliance"

reset; child_a; stop p1 >/dev/null; stop p1 >/dev/null; stop p1 >/dev/null; aborted "$R" c1 30; stop p1 >/dev/null; s=$(st)
[ "$(field '.running|length' "$s")" = 0 ] && [ "$(field '.unrecovered[0].end' "$s")" = aborted ] && [ "$(field '.unrecovered[0].released' "$s")" = true ] \
  && delegator_fails "$s" || fail "released run aborted by exec end is unrecovered: $s"
ok "released run aborted by exec end is unrecovered"

out=$(inject p2)
[[ "$(ctx "$out")" == *c1*aborted* ]] && [[ "$(ctx "$out")" == *p1* ]] || fail "inject reports released and unrecovered runs: $out"
ok "inject reports released and unrecovered runs"

reset; child_a; at 7200; a=$(stop p1); waited 1200000 p1; b=$(stop p1); waited 1200000 p1; c=$(stop p1); at 0
blocked "$a" && blocked "$b" && blocked "$c" || fail "long run keeps blocking in its turn: $c"
ok "long run keeps blocking in its turn"

reset; child_a; aborted "$R" c1 5; adv; a=$(inject p2); b=$(inject p3); s=$(st)
[[ "$(ctx "$a")" == *c1* ]] && [ "$(lines "$D/notified.jsonl")" = 1 ] && [ -z "$b" ] && [ "$(field '.unrecovered|length' "$s")" = 1 ] \
  || fail "unrecovered run is injected once: $a / $b"
ok "unrecovered run is injected once"

reset; child_a; mkdir "$D/advance.lock"; complete "$R" c1 5
t0=$(date +%s%N); at 10; interrupt child_a '"{\"previous_status\":{\"running\":null}}"'; at 0; t1=$(date +%s%N)
out=$(STALL_GUARD_LOCK_WAIT=1 stop p1); t2=$(date +%s%N)
[ $(((t1 - t0) / 1000000)) -lt 1500 ] && [ "$(lines "$D/interrupts.jsonl")" = 1 ] || fail "lock held elsewhere: interrupt record waited"
[ $(((t2 - t1) / 1000000)) -ge 900 ] && blocked "$out" || fail "lock held elsewhere keeps blocking: $out"
rmdir "$D/advance.lock"; out=$(stop p1)
[ -z "$out" ] || fail "lock held elsewhere keeps blocking (released lock): $out"
ok "lock held elsewhere keeps blocking"

reset; child_a; complete "$R" c1 5; adv; mkdir "$D/advance.lock"; spawn child_b p2; out=$(STALL_GUARD_LOCK_WAIT=1 stop p2); rmdir "$D/advance.lock"
blocked "$out" && [[ "$(field .reason "$out")" == *child_b* ]] || fail "spawn recorded while the lock is held still blocks: $out"
ok "spawn recorded while the lock is held still blocks"

reset; meta "$R" /root/child_a; started "$R" c1 1 p2 /elsewhere; spawn child_a p2; adv; a=$(stop p2); at 200; b=$(stop p2); s=$(st); at 0
blocked "$a" && blocked "$b" && delegator_fails "$s" && [ "$(field '.pending[0].boundary_seen' "$s")" = false ] \
  || fail "boundary-unseen child blocks its turn and fails the delegator: $b / $s"
ok "boundary-unseen child blocks its turn and fails the delegator"

reset; spawn child_b p1; at 121; out=$(stop p1); s=$(st); at 0
[ -z "$out" ] && [ "$(field '.pending[0].expired' "$s")" = true ] && delegator_fails "$s" || fail "unstarted acceptance counts as a failure for the delegator: $out / $s"
ok "unstarted acceptance counts as a failure for the delegator"

reset; child_a; cx disable >/dev/null; a=$(stop p1); b=$(prewait 10000 p1); c=$(inject p1); spawn child_c p1
[ -z "$a$b$c" ] && [ "$(lines "$D/accepts.jsonl")" = 1 ] || fail "disabled is inert: $a$b$c"
ok "disabled is inert"
