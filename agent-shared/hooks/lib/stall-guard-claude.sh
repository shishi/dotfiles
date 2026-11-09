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
    | any($crons[]; (.recurring == false)
        and (((.schedule // "") | split(" ")) as $p | (($p[0] | tonumber?) == $m) and (($p[1] | tonumber?) == $h)))
  end;
def needs_observation($L; $t; $crons):
  (interval_of($L; $t.id)) as $iv | ((($now + $iv + 59) / 60 | floor) * 60) as $due
  | ($t.kind != "shell" or ((kept($L; $t.id) | not) and $t.ends_with_final != true))
    and (any(($L.wakeups // [])[]; live(.; $crons) and .fire > $now and .fire <= $due) | not);
def observed_of($L; $key): ([($L.observed // [])[] | select(.key == $key)] | last | .observed_with) // null;
# 終了の記録は、最新の seen 以後のものだけで running から外す (それより前の終了で、後の Stop が running と報告した作業を隠さない)。
def ended_since($L): (lastof($L.seen).at // 0) as $a | [($L.ended // [])[] | select(.at >= $a) | .id];
# 今 running とみなす作業: 最新の seen の running から ended を除く (seen が無ければ tasks から)。
def running_ids($L):
  (if lastof($L.seen) then lastof($L.seen).running else ids($L.tasks) end) - ended_since($L);
def task_of($L; $id): (last_by_id($L.tasks; $id) // {id: $id, kind: "unknown", started: $now});
'

claude_main() {
  local sub=$1
  shift
  case $sub in
    record) claude_record "$@" ;;
    stop-check) claude_stop_check "$@" ;;
    status) claude_status "$@" ;;
    watch) claude_watch "$@"; return $? ;;
    inject) claude_inject "$@" ;;
    deadline) claude_deadline "$@"; return $? ;;
    keep) claude_keep "$@"; return $? ;;
    *) echo "stall-guard: unknown subcommand: $sub" >&2; return 1 ;;
  esac
  return 0
}

# モデルが Bash で実行する deadline・keep は、Bash の子に入る CLAUDE_CODE_SESSION_ID で自分の台帳を探す。
claude_cmd_dir() {
  local sid=${CLAUDE_CODE_SESSION_ID:-}
  if ! sg_valid_sid "$sid"; then echo "stall-guard: CLAUDE_CODE_SESSION_ID is not set; run this from a Claude Code Bash tool" >&2; return 1; fi
  sg_session_dir claude "$sid"
}

# path の大きさと更新時刻を「パス・大きさ・時刻」の順に並べる (無いパスは null)。
claude_stat_args() {
  local p s
  for p in "$@"; do
    s=$(stat -c '%s %Y' -- "$p" 2>/dev/null) || s="null null"
    printf '%s\n%s\n%s\n' "$p" "${s% *}" "${s#* }"
  done
}

# claude_line_ends: claude_stat_args の出力 (パス・大きさ・更新時刻の 3 行組) の大きさを、最後の改行の直後の位置に直す
# (示し始める基準が書きかけの行の途中を指さないように)。
claude_line_ends() {
  local p s t
  while IFS= read -r p && IFS= read -r s && IFS= read -r t; do
    [[ "$s" =~ ^[0-9]+$ ]] && s=$(sg_line_end "$p" 0 "$s")
    printf '%s\n%s\n%s\n' "$p" "$s" "$t"
  done
}

# deadline <id> <分> [--watch <path>]...: 作業の確認の間隔を 1〜30 分に変え、成果物のパスを登録する。
claude_deadline() {
  local id=${1:-} min=${2:-} dir
  if [ -z "$id" ] || ! [[ "$min" =~ ^[0-9]+$ ]] || [ "$min" -lt 1 ] || [ "$min" -gt 30 ]; then
    echo "stall-guard: usage: deadline <id> <minutes 1-30> [--watch <path>]... (got '${min}')" >&2
    return 1
  fi
  shift 2
  local paths=() p
  while [ $# -gt 0 ]; do
    case $1 in
      --watch)
        p=${2:-}
        [ -n "$p" ] || { echo "stall-guard: --watch needs a path" >&2; return 1; }
        [[ "$p" == /* || "$p" =~ ^[A-Za-z]: ]] || p="$PWD/$p"
        paths+=("$p"); shift 2 ;;
      *) echo "stall-guard: unknown argument: $1" >&2; return 1 ;;
    esac
  done
  dir=$(claude_cmd_dir) || return 1
  if sg_disabled; then echo "stall-guard: disabled; nothing recorded"; return 0; fi
  local now plan
  now=$(sg_now)
  # 既に示した位置があるパスは基準を書き直さない (間隔を変えても、前回以後の追記を飛ばさないため)。
  local known
  known=$(jq -sc '[.[].path]' "$dir/obs.jsonl" 2>/dev/null) || known='[]'
  plan=$(claude_stat_args ${paths[@]+"${paths[@]}"} | claude_line_ends | jq -nrR --arg id "$id" --argjson iv $((min * 60)) --argjson now "$now" --argjson known "${known:-[]}" '
    [inputs] as $a | [range(0; $a | length; 3) as $i | {path: $a[$i], size: ($a[$i + 1] | tonumber?), mtime: ($a[$i + 2] | tonumber?)}] as $p
    | "A\tdeadlines\t\({id: $id, interval_sec: $iv, watch: [$p[].path], at: $now} | tojson)",
      ($p[] | select(.path as $q | $known | index($q) | not) | "A\tobs\t\(. + {at: $now} | tojson)")') || return 1
  sg_apply "$dir" "$plan"
  echo "stall-guard: $id is checked every $min minute(s)"
}

# keep <id>: 意図して動かし続ける shell の作業を、確認の予約を求める対象から外す (期限なし)。
claude_keep() {
  local id=${1:-} dir kind
  [ -n "$id" ] || { echo "stall-guard: usage: keep <id>" >&2; return 1; }
  dir=$(claude_cmd_dir) || return 1
  if sg_disabled; then echo "stall-guard: disabled; nothing recorded"; return 0; fi
  sg_files "$dir" tasks
  kind=$(jq -nrR --arg id "$id" --argjson now 0 --argjson off 0 "$SG_JQ_LOAD$CLAUDE_JQ_DEFS"'sg_load as $L | (last_by_id($L.tasks; $id).kind // "none")' "${SG_FILES[@]}" 2>/dev/null)
  kind=${kind//$SG_CR/}
  if [ "$kind" != shell ]; then
    echo "stall-guard: keep is only for background shell tasks; $id is ${kind:-none}. Schedule a check, check it now, or report it as unfinished." >&2
    return 1
  fi
  sg_append "$dir/keeps.jsonl" "{\"id\":\"$id\",\"at\":$(sg_now)}"
  echo "stall-guard: $id is kept running without check schedules"
}

# inject (UserPromptSubmit): ターンの境界を書き、確認が必要な作業・前のターンで抜けた記録・残った予約を渡す。
claude_inject() {
  local input sid
  input=$(cat) || return 0
  sid=$(jq -r '.session_id | tostring' <<<"$input" 2>/dev/null) || return 0
  sid=${sid//$SG_CR/}
  sg_valid_sid "$sid" || return 0
  sg_mark_hooked claude "$sid"
  sg_disabled && return 0
  local dir now off plan paths
  dir=$(sg_session_dir claude "$sid") || return 0
  [ -d "$dir" ] || return 0
  now=$(sg_now)
  off=$(sg_tz_offset)
  sg_files "$dir" tasks wakeups failed ended seen crons observed released leftover deadlines keeps turns obs
  local files=("${SG_FILES[@]}")
  # 1 回目: 内容を読むパス (running の作業の watch と outputFile) を、鍵・パス・前回観測した大きさの組で出す。
  paths=$(jq -nrR --argjson now "$now" --argjson off "$off" "$SG_JQ_LOAD$CLAUDE_JQ_DEFS"'
    sg_load as $L | running_ids($L)[] as $id
    | select(needs_observation($L; task_of($L; $id); crons_now($L)))
    | ((last_by_id($L.deadlines; $id).watch // [])[], (task_of($L; $id).output_file // empty)) as $p
    | $p, $p, ([($L.obs // [])[] | select(.path == $p)] | last | .size // 0)' "${files[@]}" 2>/dev/null) || return 0
  paths=${paths//$SG_CR/}
  local triples=() added
  [ -n "$paths" ] && mapfile -t triples <<<"$paths"
  added=$(sg_added_map ${triples[@]+"${triples[@]}"}) || return 0
  plan=$(jq -nrR --argjson now "$now" --argjson off "$off" --argjson added "${added//$SG_CR/}" --arg self "$SG_SELF" "$SG_JQ_LOAD$CLAUDE_JQ_DEFS$SG_ADDED_JQ"'
    def hm($t): ($t + $off) | strftime("%H:%M");
    def growth($L; $p): "\($p): " + added_fact($added[$p] // {});
    sg_load as $L | crons_now($L) as $crons
    | ([($L.turns // [])[] | select(.event == "prompt") | .at] | last // 0) as $prev
    | [running_ids($L)[] as $id | task_of($L; $id) as $t
        | select(needs_observation($L; $t; $crons))
        | ([($L.deadlines // [])[] | select(.id == $id)] | last) as $d
        | "- \($id) (\($t.kind)): 起動から \((($now - $t.started) / 60) | floor) 分、確認の間隔 \(interval_of($L; $id) / 60 | floor) 分"
          + (if kept($L; $id) then "、keep 中 (確認の予約を求めない)" else "" end)
          + (if $d then "、deadline \($d.interval_sec / 60 | floor) 分 (\(hm($d.at)) に設定)" else "" end)
          + ([($L.failed // [])[] | select(.at >= $t.started)] | if length > 0 then "、予約の失敗: " + (map("\(.event) \(.tool) \(hm(.at))") | join(", ")) else "" end)
          + ([($d.watch // [])[] | "\n  成果物 " + growth($L; .)] | join(""))
          + (if $t.output_file then "\n  会話記録 " + growth($L; $t.output_file) else "" end)
          + (if (($d.watch // []) | length) == 0 and ($t.output_file | not) then
               "\n  内容を読む対象が未登録。出力ファイルを `bash \($self) deadline \($id) <分> --watch <path>` で登録すると、確認ごとに追記された内容を示す"
             else "" end)] as $facts
    | [($L.released // [])[] | select(.at >= $prev)
        | "- 前のターン (prompt \(.prompt_id)) で、stall-guard は block をやめた (\(if .cause == "total" then "1 ターンの block の上限" else "block に応じた変化が無い" end))。確認の予定が無い作業: \(.unmet | join(", "))"] as $rel
    | [($L.leftover // [])[] | select(.event == "detected") | .set as $set
        | select(any(($L.leftover // [])[]; .event == "delivered" and .via == "inject" and ((.set | sort) == ($set | sort))) | not)
        | {set: $set, live: [($L.wakeups // [])[] | select(.key as $k | $set | index($k)) | select(live(.; $crons))]}
        | select(.live | length > 0)] as $left
    | "A\tturns\t\({at: $now, event: "prompt"} | tojson)",
      ($added | to_entries[] | select(.value.end != null) | "A\tobs\t\({path: .key, size: .value.end, at: $now} | tojson)"),
      ($left[] | "A\tleftover\t\({event: "delivered", set: .set, via: "inject", at: $now} | tojson)"),
      "S\t\($L._skipped)",
      (($facts | if length > 0 then ["stall-guard: 動いているバックグラウンド処理の事実 (確認するか、続けるか止めるかの判断に使う。進捗は追加された内容が目的の結果へ近づいているかで判断し、大きさや更新時刻の変化だけでは判断しない):"] + . else [] end)
        + $rel
        + [$left[] | .live[] | "- バックグラウンド処理は全て終わったが、作業のために作った確認の予約が残っている (事実の連絡。取り消すかは判断に任せる): \(.source) \(.key) が \(hm(.fire)) に発火予定 (同時に動いていた作業: \(observed_of($L; .key) // [] | join(", ")))"]
       | if length > 0 then "O\t\({hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: join("\n")}} | tojson)" else empty end)' \
    "${files[@]}" 2>/dev/null) || return 0
  sg_apply "$dir" "$plan"
}

# 本体 (CLAUDE_PID) の起動引数を NUL 区切りで出す。読めなければ非 0。
claude_host_argv() {
  if [ -n "${STALL_GUARD_ARGV_FILE:-}" ]; then
    [ -f "$STALL_GUARD_ARGV_FILE" ] && cat "$STALL_GUARD_ARGV_FILE"
    return
  fi
  local pid=${CLAUDE_PID:-}
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  if [ -r "/proc/$pid/cmdline" ]; then cat "/proc/$pid/cmdline"; return; fi
  case $(uname -s 2>/dev/null) in MINGW* | MSYS* | CYGWIN*) ;; *) return 1 ;; esac
  local py
  for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then "$py" -I "$SG_HOOK_DIR/lib/stall-guard-argv.py" "$pid"; return; fi
  done
  return 1
}

# 非ストリーミングの -p か (true / false / null は読めない)。本体が asyncRewake を背景で走らせない条件
# (対話でも streaming 入力でもない) を、ホストのプロセス自身の起動引数の配列の要素で判定する。
claude_text_print() {
  local args=()
  mapfile -d '' -t args < <(claude_host_argv 2>/dev/null)
  [ ${#args[@]} -gt 0 ] || { echo null; return; }
  local i print=false stream=false
  for ((i = 1; i < ${#args[@]}; i++)); do
    case ${args[i]} in
      -p | --print) print=true ;;
      --input-format) [ "${args[i + 1]:-}" = stream-json ] && stream=true ;;
      --input-format=stream-json) stream=true ;;
    esac
  done
  if $print && ! $stream; then echo true; else echo false; fi
}

# claude_wake_facts <dir> <now>: 見張りの判定結果の F (事実) と P (読むパス) の行を、事実と追記内容に直して出す。
# 読み終えた位置を obs に記録し、次の確認ではそれ以後の追記だけを示す。
claude_wake_facts() {
  local dir=$1 now=$2 kind label p prev a line
  while IFS=$'\t' read -r kind label p prev; do
    case $kind in
      F) printf '%s\n' "$label" ;;
      P)
        a=$(sg_added_map x "$p" "$prev") || continue
        line=$(jq -r --arg l "$label" --arg p "$p" "$SG_ADDED_JQ"'"  \($l) \($p): " + added_fact(.x)' <<<"$a") && printf '%s\n' "$line"
        a=$(jq -c --arg p "$p" --argjson at "$now" 'select(.x.end != null) | {path: $p, size: .x.end, at: $at}' <<<"$a")
        [ -n "$a" ] && sg_append "$dir/obs.jsonl" "$a"
        ;;
    esac
  done
}

# 見張り: asyncRewake の Stop hook。確認時刻を過ぎた作業があれば事実を stderr に書いて exit 2 でモデルを起こす。
# 確認時刻 = max(最後のターン境界, 見張りの起動時刻) + interval + 120 秒。60 秒ごとに台帳を読み直し、
# 対象が無くなる・後から仕掛かった見張りに lock を引き継がれる・無効化・台帳の削除で exit 0 する。
claude_watch() {
  local input meta sid st
  input=$(cat) || return 0
  [ "${AGENT_DELEGATED_SESSION:-}" = 1 ] && return 0
  meta=$(jq -r '(.session_id | tostring),
    ({running: [(.background_tasks // [])[] | select(.status == "running") | {id, type}]} | tojson)' <<<"$input" 2>/dev/null) || return 0
  meta=${meta//$SG_CR/}
  sid=${meta%%$'\n'*}
  st=${meta#*$'\n'}
  sg_valid_sid "$sid" || return 0
  sg_mark_hooked claude "$sid"
  [[ "$st" == *'"running":[]'* ]] && return 0
  local dir
  dir=$(sg_session_dir claude "$sid") || return 0
  local started=${STALL_GUARD_WATCH_STARTED:-$(sg_now)} period=${STALL_GUARD_WATCH_PERIOD:-60}
  local first=true existed=false me=$$ now res count due argv_state lock
  while :; do
    sg_disabled && return 0
    if [ -d "$dir" ]; then existed=true; elif $existed; then return 0; fi
    if ! $first; then
      lock=$(cat "$dir/watch.lock" 2>/dev/null)
      [[ "$lock" =~ \"pid\":([0-9]+) ]] && [ "${BASH_REMATCH[1]}" = "$me" ] || return 0
    fi
    now=$(sg_now)
    sg_files "$dir" tasks seen ended keeps deadlines turns argv obs
    res=$(jq -nrR --argjson S "$st" --argjson first "$first" --argjson now "$now" --argjson started "$started" --argjson off 0 \
      "$SG_JQ_LOAD$CLAUDE_JQ_DEFS"'
      sg_load as $L
      | (if $first or (lastof($L.seen) | not) then [$S.running[].id] else lastof($L.seen).running end) - ended_since($L)
      | [.[] as $id | (last_by_id($L.tasks; $id) // {kind: ([$S.running[] | select(.id == $id) | .type] | first // "unknown"), started: $now}) as $t
          | select(($t.kind == "shell" and (kept($L; $id) or $t.ends_with_final == true)) | not)
          | ([(lastof($L.turns).at // 0), $started] | max) as $base | interval_of($L; $id) as $iv
          | {id: $id, kind: $t.kind, started: ($t.started // $now), iv: $iv, base: $base, due: ([$base + $iv + 120, $started + 2100 - 60] | min)}] as $T
      | "N\t\($T | length)",
        "V\t\(if $L.argv then (lastof($L.argv).text_print | tojson) else "unread" end)",
        "D\t\(any($T[]; .due <= $now))",
        ($T[] | select(.due <= $now)
          | "F\t- \(.id) (\(.kind)): 起動から \((($now - .started) / 60) | floor) 分、確認の間隔 \(.iv / 60 | floor) 分、最後の確認から \((($now - .base) / 60) | floor) 分",
            (.id as $id | (((last_by_id($L.deadlines; $id).watch // [])[] | ["成果物", .]), (task_of($L; $id).output_file // empty | ["会話記録", .]))
              | . as [$label, $q] | "P\t\($label)\t\($q)\t\([($L.obs // [])[] | select(.path == $q)] | last | .size // 0)"))' \
      ${SG_FILES[@]+"${SG_FILES[@]}"} 2>/dev/null) || return 0
    res=${res//$SG_CR/}
    count=$(sed -n 's/^N\t//p' <<<"$res")
    [ "${count:-0}" -gt 0 ] 2>/dev/null || return 0
    if $first; then
      argv_state=$(sed -n 's/^V\t//p' <<<"$res")
      if [ "$argv_state" = unread ]; then
        argv_state=$(claude_text_print)
        sg_append "$dir/argv.jsonl" "{\"at\":$now,\"text_print\":$argv_state}"
      fi
      # 非ストリーミングの -p では asyncRewake が同期で走り、プロセスを待たせるので仕掛けない。
      [ "$argv_state" = true ] && return 0
      mkdir -p "$dir" && printf '{"pid":%s,"until":%s}\n' "$me" $((now + 2100)) >"$dir/watch.lock.$me" && mv -f "$dir/watch.lock.$me" "$dir/watch.lock"
      existed=true
      first=false
    fi
    due=$(sed -n 's/^D\t//p' <<<"$res")
    if [ "$due" = true ]; then
      lock=$(cat "$dir/watch.lock" 2>/dev/null)
      [[ "$lock" =~ \"pid\":([0-9]+) ]] && [ "${BASH_REMATCH[1]}" = "$me" ] || return 0
      sg_append "$dir/turns.jsonl" "{\"at\":$now,\"event\":\"watch\"}"
      {
        echo "stall-guard: 確認時刻を過ぎたバックグラウンド処理がある。追加された内容が目的の結果へ近づいているかで進捗を判断し (大きさや更新時刻の変化だけでは判断しない)、続けるなら確認を予約し直すか、止める・未完了として報告するかを決める。"
        claude_wake_facts "$dir" "$now" <<<"$res"
      } >&2
      return 2
    fi
    sleep "$period"
  done
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
    | ($in.session_id | tostring), ($f | tojson)' <<<"$input" 2>/dev/null) || return 0
  meta=${meta//$SG_CR/}
  sid=${meta%%$'\n'*}
  fact=${meta#*$'\n'}
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

# 終了の関所。running のバックグラウンド処理それぞれに、今から interval 以内に発火する生きた予約が無ければ block する。
# 同じ prompt_id の中で、満たさない作業の集合が縮まない block が 2 回続くか、block が合計 6 回になれば抜ける
# (本体の連続 block の上限 8 を出力ゲートと共有するため。抜けた後は見張りが確認時刻に起こす)。
claude_stop_check() {
  local input now meta sid st
  input=$(cat) || return 0
  now=$(sg_now)
  meta=$(jq -r '(.session_id | tostring),
    ({pid: (.prompt_id // ""), crons: (.session_crons // []),
      running: [(.background_tasks // [])[] | select(.status == "running") | {id, type}]} | tojson)' <<<"$input" 2>/dev/null) || return 0
  meta=${meta//$SG_CR/}
  sid=${meta%%$'\n'*}
  st=${meta#*$'\n'}
  sg_valid_sid "$sid" || return 0
  sg_mark_hooked claude "$sid"
  local dir
  dir=$(sg_session_dir claude "$sid") || return 0
  # バックグラウンド処理も台帳も無い普段のセッションは、ここで終える (jq 1 回だけ)。
  [ ! -d "$dir" ] && [[ "$st" == *'"running":[]'* ]] && return 0
  if sg_disabled; then
    # 無効化の後も、撤去の照合のために session_crons の観測値だけを書く。
    [ -d "$dir" ] && sg_append "$dir/crons.jsonl" "$(jq -c --argjson now "$now" '{at: $now, crons: .crons}' <<<"$st")"
    return 0
  fi
  local delegated=false plan
  [ "${AGENT_DELEGATED_SESSION:-}" = 1 ] && delegated=true
  sg_files "$dir" tasks wakeups failed ended seen observed blocks released leftover deadlines keeps
  plan=$(jq -nrR --argjson S "$st" --argjson now "$now" --argjson off "$(sg_tz_offset)" --argjson delegated "$delegated" \
    --arg self "$SG_SELF" "$SG_JQ_LOAD$CLAUDE_JQ_DEFS"'
    def inter($a; $b): [$a[] | select(. as $x | any($b[]; . == $x))];
    def hm($t): ($t + $off) | strftime("%H:%M");
    def same_set($a; $b): ($a | sort) == ($b | sort);
    sg_load as $L | $S.crons as $crons | [$S.running[].id] as $rids
    | (lastof($L.seen).running // []) as $prev
    | [$S.running[] | select(.id as $i | ids($L.tasks) | index($i) | not) | {id, kind: .type, started: $now}] as $adopt
    | {tasks: (($L.tasks // []) + $adopt)} as $T
    # 作成後の最初の Stop で、作成時の候補のうち今も running の作業を observed_with に残す (残った予約で使う)。
    | [($L.wakeups // [])[] | select(.key as $k | any(($L.observed // [])[]; .key == $k) | not)
        | {key, observed_with: inter(.tasks_at_create // []; $rids), at: $now}] as $obs
    | {observed: (($L.observed // []) + $obs)} as $O
    | [$rids[] as $id | last_by_id($T.tasks; $id) as $t
        | select(needs_observation($L; $t; $crons))
        | {id: $id, kind: $t.kind, started: $t.started, interval: interval_of($L; $id)}] as $unmet
    | ([($L.blocks // [])[] | select(.prompt_id == $S.pid)]) as $B
    | ([$B[] | select(.kind != "leftover")] | reduce .[] as $b ({prev: null, streak: 0};
        if .prev != null and ($b.unmet | length) < (.prev | length) and (inter($b.unmet; .prev) | length) == ($b.unmet | length)
        then {prev: $b.unmet, streak: 0} else {prev: $b.unmet, streak: (.streak + 1)} end)) as $k
    | [$unmet[].id] as $uids
    | ($k.prev != null and ($uids | length) < ($k.prev | length) and (inter($uids; $k.prev) | length) == ($uids | length)) as $shrunk_now
    | any(($L.released // [])[]; .prompt_id == $S.pid) as $already
    # 残った予約: 作業が全て終わった Stop で、作業と同時に動いていたと観測した予約のうち生きているもの。
    | (if ($prev | length) > 0 and ($rids | length) == 0 then
         [($L.wakeups // [])[] | select((observed_of($O; .key) // []) | length > 0) | select(live(.; $crons))]
       else [] end) as $left
    | [$left[].key] as $lkeys
    | (($lkeys | length) > 0 and (any(($L.leftover // [])[]; .event == "delivered" and .via == "stop" and same_set(.set; $lkeys)) | not)) as $left_new
    | (if ($unmet | length) > 0 then
         if ($B | length) >= 6 then "total"
         elif $k.streak >= 2 and ($shrunk_now | not) then "unshrunk"
         else null end
       else null end) as $release
    | (($left_new) and ($B | length) < 6) as $left_block
    | def fact($u):
        "- \($u.id) (\($u.kind)): 起動から \((($now - $u.started) / 60) | floor) 分、確認の間隔 \($u.interval / 60 | floor) 分、間隔内に発火する確認の予約なし"
        + ([($L.deadlines // [])[] | select(.id == $u.id)] | last | if . then "、deadline \(.interval_sec / 60 | floor) 分 (\(hm(.at)) に設定)" + (if (.watch | length) > 0 then "、watch \(.watch | join(" "))" else "" end) else "" end)
        + ([($L.failed // [])[] | select(.at >= $u.started)] | if length > 0 then "、予約の失敗: " + (map("\(.event) \(.tool) \(hm(.at))") | join(", ")) + " (今確認するか未完了として報告する)" else "" end);
      def means($u):
        if $delegated then "  手段: 今この作業を確認する、または未完了として報告する。"
        else "  手段: ScheduleWakeup の delaySeconds を \($u.interval) 秒以内にして確認を予約する / `bash \($self) deadline \($u.id) <1〜30 分>` で間隔を変える / 今確認する / 未完了として報告する"
          + (if $u.kind == "shell" then " / 意図して動かし続ける shell なら `bash \($self) keep \($u.id)`" else "" end) + "。"
        end;
    "A\tseen\t\({at: $now, running: $rids} | tojson)",
    "A\tturns\t\({at: $now, event: "stop"} | tojson)",
    "A\tcrons\t\({at: $now, crons: $crons} | tojson)",
    ($adopt[] | "A\ttasks\t\(tojson)"),
    ($obs[] | "A\tobserved\t\(tojson)"),
    "S\t\($L._skipped)",
    (if ($unmet | length) > 0 then
       if $release then
         (if $already then empty else "A\treleased\t\({prompt_id: $S.pid, at: $now, unmet: $uids, cause: $release} | tojson)" end)
       else
         "A\tblocks\t\({prompt_id: $S.pid, unmet: $uids, at: $now, kind: "tasks"} | tojson)",
         "O\t\({decision: "block", reason: (["stall-guard: バックグラウンド処理が確認の予定なしで動いている。ターンを終える前に、作業ごとに次のどれかを行う。"] + [$unmet[] | fact(.), means(.)] | join("\n"))} | tojson)"
       end
     elif ($lkeys | length) > 0 then
       (if any(($L.leftover // [])[]; .event == "detected" and same_set(.set; $lkeys)) then empty
        else "A\tleftover\t\({event: "detected", set: $lkeys, at: $now} | tojson)" end),
       (if $left_block then
          "A\tleftover\t\({event: "delivered", set: $lkeys, via: "stop", at: $now} | tojson)",
          "A\tblocks\t\({prompt_id: $S.pid, unmet: [], at: $now, kind: "leftover"} | tojson)",
          "O\t\({decision: "block", reason: (["stall-guard: バックグラウンド処理は全て終わったが、作業のために作った確認の予約が残っている (事実の連絡。取り消すかは判断に任せる)。"]
             + [$left[] | "- \(.source) \(.key): \(hm(.fire)) に発火予定 (同時に動いていた作業: \(observed_of($O; .key) | join(", ")))"] | join("\n"))} | tojson)"
        else empty end)
     else empty end)' ${SG_FILES[@]+"${SG_FILES[@]}"}) || return 0
  sg_apply "$dir" "$plan"
}
