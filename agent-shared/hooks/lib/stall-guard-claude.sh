# stall-guard の Claude Code 側。stall-guard.sh から source される (共通関数はそちら)。
# 台帳: <根>/claude/<session_id>/ の tasks・wakeups・failed・ended・seen・crons・observed・turns・
# blocks・released・leftover・deadlines・keeps (いずれも 1 行 1 事実の JSONL)。

# 台帳の status と判定で共通に使う jq の定義。$now・$off (UTC からの差、秒) を引数で受ける。
CLAUDE_JQ_DEFS='
def ids($a): [($a // [])[] | .id];
def uniq_keep: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
def last_by_id($a; $id): [($a // [])[] | select(.id == $id)] | last;
def interval_of($L; $id): (last_by_id($L.deadlines; $id).interval_sec // 1200);
def kept($L; $id): any(($L.keeps // [])[]; .id == $id);
def crons_now($L): (lastof($L.crons).crons // null);
# 予約が今も生きているか: Stop の session_crons (最新の観測値) にあるかだけで決める。
# CronCreate は id、ScheduleWakeup は recurring:false の cron 式の分・時と発火時刻のローカルの分・時で結ぶ。
def live($w; $crons):
  if $crons == null then false
  elif $w.source == "CronCreate" then any($crons[]; .id == $w.cron_id)
  else (($w.fire + $off) % 3600 / 60 | floor) as $m | (($w.fire + $off) % 86400 / 3600 | floor) as $h
    | any($crons[]; .recurring == false and ((.schedule // "") | split(" ")) as $p
        | (($p[0] | tonumber?) == $m) and (($p[1] | tonumber?) == $h))
  end;
def observed_of($L; $key): ([($L.observed // [])[] | select(.key == $key)] | last | .observed_with) // null;
# 今 running とみなす作業: 最新の seen の running から ended を除く (seen が無ければ tasks から)。
def running_ids($L):
  (if lastof($L.seen) then lastof($L.seen).running else ids($L.tasks) end) - ids($L.ended);
def task_of($L; $id): (last_by_id($L.tasks; $id) // {id: $id, kind: "unknown", started: $now});
'

claude_main() {
  local sub=$1
  shift
  case $sub in
    record) claude_record "$@" ;;
    stop-check) claude_stop_check "$@" ;;
    status) claude_status "$@" ;;
    *) echo "stall-guard: unknown subcommand: $sub" >&2; return 1 ;;
  esac
  return 0
}

claude_record() {
  local failed=false
  [ "${1:-}" = --failed ] && failed=true
  local input now meta sid fact
  input=$(cat) || return 0
  now=$(sg_now)
  meta=$(jq -r --argjson now "$now" --argjson failed "$failed" '
    . as $in | ($in.tool_response | if type == "object" then . else {} end) as $r
    | (if $failed then {file: "failed", v: {tool: $in.tool_name, event: $in.hook_event_name, at: $now}}
       elif $in.hook_event_name == "SubagentStop" and ($in.agent_id | type) == "string" then
         {file: "ended", needdir: true, v: {id: $in.agent_id, by: "SubagentStop", at: $now}}
       elif $in.hook_event_name != "PostToolUse" then null
       elif $in.tool_name == "Agent" and $r.status == "async_launched" and ($r.agentId | type) == "string" then
         {file: "tasks", v: {id: $r.agentId, kind: "subagent", started: $now, output_file: $r.outputFile}}
       elif $in.tool_name == "Bash" and ($r.backgroundTaskId | type) == "string" then
         {file: "tasks", v: {id: $r.backgroundTaskId, kind: "shell", started: $now, ends_with_final: ($r.backgroundEndsWithFinalResponse == true)}}
       elif $in.tool_name == "TaskStop" then
         (($in.tool_input.task_id // $in.tool_input.shell_id) as $id
          | if ($id | type) == "string" then {file: "ended", v: {id: $id, by: "TaskStop", at: $now}} else null end)
       elif $in.tool_name == "ScheduleWakeup" and ($r.scheduledFor | type) == "number" then
         {file: "wakeups", cand: true, v: {key: $in.tool_use_id, source: "ScheduleWakeup", fire: ($r.scheduledFor / 1000 | floor), recurring: false, created: $now}}
       elif $in.tool_name == "CronCreate" and ($r.id | type) == "string" then
         {file: "wakeups", cand: true, v: {key: $r.id, source: "CronCreate", cron_id: $r.id, fire: (($r.nextFireAt // 0) / 1000 | floor), recurring: ($r.recurring == true), created: $now}}
       else null end) as $f
    | [($in.session_id | tostring), ($f | tojson)] | @tsv' <<<"$input" 2>/dev/null) || return 0
  meta=${meta//$SG_CR/}
  sid=${meta%%$'\t'*}
  fact=${meta#*$'\t'}
  sg_valid_sid "$sid" || return 0
  sg_mark_hooked claude "$sid"
  [ "$fact" = null ] && return 0
  sg_disabled && return 0
  local dir
  dir=$(sg_session_dir claude "$sid") || return 0
  [[ "$fact" == *'"needdir":true'* ]] && [ ! -d "$dir" ] && return 0
  local plan
  sg_files "$dir" seen tasks ended
  plan=$(jq -nrR --argjson f "$fact" --argjson now "$now" --argjson off 0 "$SG_JQ_LOAD$CLAUDE_JQ_DEFS"'
    (if $f.cand then
       sg_load as $L | lastof($L.seen) as $s
       | (if $s then ($s.running + [($L.tasks // [])[] | select(.started >= $s.at) | .id]) else ids($L.tasks) end)
       | uniq_keep - ids($L.ended) | . as $c | $f.v + {tasks_at_create: $c}
     else $f.v end) as $v
    | "A\t\($f.file)\t\($v | tojson)"' ${SG_FILES[@]+"${SG_FILES[@]}"} 2>/dev/null) || return 0
  sg_apply "$dir" "$plan"
}

claude_status() {
  local json=false sid=${CLAUDE_CODE_SESSION_ID:-}
  while [ $# -gt 0 ]; do
    case $1 in
      --json) json=true ;;
      --session) sid=${2:-}; shift ;;
    esac
    shift
  done
  if ! sg_valid_sid "$sid"; then echo "stall-guard: no valid session (use --session <id>)" >&2; return 1; fi
  local dir hooked=false now
  dir=$(sg_session_dir claude "$sid")
  [ -e "$SG_ROOT/hooked/claude/$sid" ] && hooked=true
  now=$(sg_now)
  sg_files "$dir" tasks wakeups failed ended seen crons observed released deadlines keeps
  local out
  out=$(jq -nrR --arg sid "$sid" --argjson hooked "$hooked" --argjson now "$now" --argjson off "$(sg_tz_offset)" --argjson json "$json" \
    "$SG_JQ_LOAD$CLAUDE_JQ_DEFS"'
    sg_load as $L | crons_now($L) as $crons
    | {session: $sid, hooked: $hooked, skipped_lines: $L._skipped,
       tasks: [running_ids($L)[] as $id | task_of($L; $id) as $t
         | ([($L.deadlines // [])[] | select(.id == $id)] | last) as $d
         | {id: $id, kind: $t.kind, elapsed_sec: ($now - $t.started), interval_sec: interval_of($L; $id),
            keep: kept($L; $id), watch_paths: ($d.watch // []),
            last_seen: ([($L.seen // [])[] | select(any(.running[]; . == $id)) | .at] | last),
            ends_with_final: ($t.ends_with_final == true)}],
       wakeups: [($L.wakeups // [])[] as $w
         | {key: $w.key, source: $w.source, fire: $w.fire, cron_id: $w.cron_id, recurring: $w.recurring,
            live: live($w; $crons), tasks_at_create: $w.tasks_at_create, observed_with: observed_of($L; $w.key)}],
       released: ($L.released // []), failed: ($L.failed // [])} as $s
    | "S\t\($L._skipped)",
      if $json then "O\t\($s | tojson)"
      else "O\tsession \($sid) hooked=\($hooked)",
        ($s.tasks[] | "O\ttask \(.id) kind=\(.kind) elapsed=\(.elapsed_sec)s interval=\(.interval_sec)s keep=\(.keep) ends_with_final=\(.ends_with_final) watch=\(.watch_paths | join(","))"),
        ($s.wakeups[] | "O\twakeup \(.source) key=\(.key) fire=\(.fire | todate) recurring=\(.recurring) live=\(.live)"),
        ($s.released[] | "O\treleased prompt=\(.prompt_id) at=\(.at | todate) cause=\(.cause)")
      end' ${SG_FILES[@]+"${SG_FILES[@]}"}) || return 0
  sg_apply "$dir" "$out"
}

claude_stop_check() { cat >/dev/null; return 0; }
