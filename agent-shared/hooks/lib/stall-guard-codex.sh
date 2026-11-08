# stall-guard の Codex 側。stall-guard.sh から source される (共通関数はそちら)。
# 台帳: <根>/codex/<session_id>/ の children・accepts・interrupts・runs・offsets・waits・blocks・released・
# notified・turns (いずれも 1 行 1 事実の JSONL) と、最後の畳み込みの結果 fold.json。
# 子の run は子の rollout の task_started で始まり、同じ turn_id の task_complete / turn_aborted で閉じる。
# hook の入力に実行中の子の一覧が無いので、rollout を読み進めた事実と受付の事実を毎回照合し直して状態を出す。
#
# jq の program には逆斜線の連続を書かない (Windows の起動経路で 2 個が 1 個に縮むため、正規表現は [.] などで書く)。

# wait_agent は子を止めずに観測を区切る待機。戻るたびに子の rollout の内容を示すので、最低の待ち時間は
# 内容を確かめる間隔 (数分) にする。これより短い待機の連打は、内容が進む前に確認を繰り返すだけになる。
CODEX_WAIT_MIN_MS=180000
CODEX_ACCEPT_TTL=120
CODEX_LOCK_STALE=10

# 畳み込みと判定で共通に使う jq の定義。
CODEX_JQ_DEFS='
def uniq_by_first(f): reduce .[] as $x ({seen: {}, out: []};
  ($x | f | tostring) as $k | if .seen[$k] then . else .seen[$k] = true | .out += [$x] end) | .out;
def parent_path: if type == "string" then (split("/") | .[:-1] | join("/")) else null end;
# 子の指定を path に揃える: / で始まればそのまま、それ以外は呼び出し元 (親自身なら /root) の下。
def resolve($t; $parent; $paths):
  if ($t | type) != "string" then null
  elif ($t | startswith("/")) then $t
  elif ($parent // "root") == "root" then "/root/" + $t
  elif $paths[$parent] then $paths[$parent] + "/" + $t
  else null end;
# 開始を確認できない受付の失効。境界を観測していない既知の子の受付は失効させない (黙って捨てないため)。
def expired($p; $now):
  if $p.child_known and ($p.boundary_seen | not) then false else ($now - $p.at) >= $ttl end;
# 台帳の事実を全て照合し直して、子・run・受付の状態を返す (読み終えた位置や届いた順序に依らない)。
def fold($L; $now):
  ($L.runs // []) as $R
  | (reduce ($R[] | select(.event == "meta" and (.agent_path | type) == "string")) as $m ({};
      .[$m.agent_id] //= $m.agent_path)) as $paths
  | ($paths | to_entries | map({key: .value, value: .key}) | from_entries) as $byPath
  | (reduce ($L.offsets // [])[] as $o ({}; .[$o.agent_id] = ([.[$o.agent_id], $o.mtime] | max))) as $mt
  | [(reduce ($L.children // [])[] as $c ({};
        .[$c.agent_id] |= ((. // {agent_id: $c.agent_id, first_at: $c.at})
          | .rollout = ($c.rollout // .rollout) | .hint = (.hint // $c.start_turn_hint))))[]
     | $paths[.agent_id] as $tn | ($tn | parent_path) as $pp
     | . + {task_name: $tn, pp: $pp,
            parent: (if $pp == null or $pp == "/root" then "root" else ($byPath[$pp] // $pp) end)}] as $C
  # 子自身の実行の境界: turn_attribution が子の親の path を指す最初の started、無ければ SubagentStart の turn_id。
  # 境界より前 (fork で残る親の過去のターン、先頭の親の turn_id の組) は run にしない。
  | [$C[] as $c
      | [$R[] | select(.event == "started" and .agent_id == $c.agent_id)] as $S
      | (first(range(0; $S | length) as $i | select($c.pp != null and $S[$i].initiating_agent_path == $c.pp
                                                     and $S[$i].parent_turn_id != null) | $i)
         // first(range(0; $S | length) as $i | select($c.hint != null and $S[$i].turn_id == $c.hint) | $i)
         // null) as $b
      | {child: ($c + {boundary_seen: ($b != null)}),
         runs: (if $b == null then [] else ($S[$b:] | uniq_by_first(.turn_id)) end
           | map(. as $s
               | ([$R[] | select(.event == "ended" and .agent_id == $c.agent_id and .turn_id == $s.turn_id)] | first) as $e
               | {agent_id: $c.agent_id, task_name: $c.task_name, turn_id: $s.turn_id, started_at: $s.at,
                  parent_turn_id: $s.parent_turn_id, end: $e.end, end_at: $e.at, child_parent: $c.parent,
                  child_at: $c.first_at, rollout_mtime: $mt[$c.agent_id], binds: []}))}] as $X
  | [$X[].child] as $children
  # interrupt_agent: その時刻に running の run を interrupted で閉じる。子が既に完了していた (completed) か、
  # 状態が読めない応答では閉じない。先に終端があれば変えない。
  | (reduce ($L.interrupts // [])[] as $i ([$X[].runs[]];
      resolve($i.target; $i.parent; $paths) as $p
      | if $p == null or $i.previous_status == null or $i.previous_status == "completed" then .
        else (first(range(0; length) as $k
                | select(.[$k].task_name == $p and .[$k].started_at <= $i.at and (.[$k].end == null or .[$k].end_at > $i.at)) | $k)
              // null) as $k
          | if $k == null then . else .[$k].end = "interrupted" | .[$k].end_at = $i.at end
        end)) as $runs1
  | [($R[] | select(.event == "released")) | [.agent_id, .turn_id]] as $rel
  | [$runs1[] | . + {released: ([.agent_id, .turn_id] as $k | any($rel[]; . == $k))}] as $runs2
  # 受付ごとに 1 つの run に結ぶ: 1. parent_turn_id が受付のターン、2. 前の受付より後に始まった未結合の run、
  # 3. 受付の時刻に実行中の run (実行中の子への followup は新しい task_started を作らないため)。
  | ($L.accepts // []) as $A
  | (reduce range(0; $A | length) as $n ({runs: $runs2, pending: [], prev: {}};
      $A[$n] as $a | resolve($a.target; $a.parent; $paths) as $p | (if $p then .prev[$p] else null end) as $pv
      | (if $p == null then null else
          (first(range(0; .runs | length) as $k | .runs[$k] as $r
             | select($r.task_name == $p and $a.turn_id != null and $r.parent_turn_id == $a.turn_id) | $k)
           // first(range(0; .runs | length) as $k | .runs[$k] as $r
             | select($r.task_name == $p and ($r.binds | length) == 0 and ($pv == null or $r.started_at >= $pv)) | $k)
           // first(range(0; .runs | length) as $k | .runs[$k] as $r
             | select($r.task_name == $p and $r.started_at <= $a.at and ($r.end == null or $r.end_at > $a.at)) | $k)
           // null) end) as $k
      | (if $k == null then .pending += [$a + {target: ($p // $a.target)}] else .runs[$k].binds += [$a] end)
      | (if $p then .prev[$p] = $a.at else . end))) as $B
  | {children: [$children[] | {agent_id, task_name, boundary_seen}],
     runs: [$B.runs[]
       | . + {accepted_turn: (.binds | last | .turn_id), accepted_at: ((.binds | first | .at) // .child_at // .started_at),
              parent: ((.binds | last | .parent) // .child_parent)}
       | del(.binds, .child_parent, .child_at)],
     pending: [$B.pending[] | . as $a | ([$children[] | select(.task_name == $a.target)] | first) as $c
       | {target: $a.target, event: $a.event, turn_id: $a.turn_id, at: $a.at, parent: ($a.parent // "root"),
          child_known: ($c != null), boundary_seen: ($c.boundary_seen == true)}],
     accepts_lines: ($A | length)};
def unrecovered($F): [$F.runs[] | select(.end != "completed" and (.end != null or .released))];
def age($t; $now): if $t == null then "?" else "\($now - $t) 秒" end;
def run_fact($now):
  "- \(.task_name // .agent_id) (agent_id \(.agent_id)、turn \(.turn_id)): 受付から \(age(.accepted_at; $now))"
  + (if .end != null then "、終了理由 \(.end)" else "" end) + (if .released then "、歯止めで抜けたターンに動いていた" else "" end)
  + (($added[.agent_id].text // "") as $t
     | if $t != "" then "\n  rollout の最新の内容:\n" + ($t | split("\n") | map("    " + .) | join("\n"))
       else "\n  rollout から示せる本文がまだ無い" end);
def pending_fact($now): "- \(.target): 受付 (\(.event // "受付")) から \(age(.at; $now))、子の run の開始を確認できていない";
# 今のターンで受け付けた running の run と開始を確認できない受付。fold.json より後に追記された受付は未結合として足す
# (lock を取れず読み進められなかった時に、block の対象を減らさないため)。
def targets($F; $L; $turn; $now):
  {runs: [$F.runs[] | select(.end == null and .parent == "root" and .accepted_turn == $turn)],
   pending: ([$F.pending[] | select(.turn_id == $turn and .parent == "root" and (expired(.; $now) | not))]
     + [($L.accepts // [])[($F.accepts_lines // 0):][] | select(.turn_id == $turn and (.parent // "root") == "root")
        | {target, event, turn_id, at, parent: "root", child_known: false, boundary_seen: false}])};
def complied($W; $from; $to; $turn): any($W[$from:$to][]; .turn_id == $turn and ((.timeout_ms // 0) >= $wait_ms));
def fold_file($L): (($L["fold.json"] // []) | last) // {children: [], runs: [], pending: [], accepts_lines: 0};
'

codex_main() {
  local sub=$1
  shift
  case $sub in
    record | subagent-start | subagent-stop | stop-check | pre-wait | inject) codex_hook "$sub" ;;
    status) codex_status "$@" ;;
    *) echo "stall-guard: unknown subcommand: $sub" >&2; return 1 ;;
  esac
  return 0
}

codex_jq() { jq --argjson ttl "$CODEX_ACCEPT_TTL" --argjson wait_ms "$CODEX_WAIT_MIN_MS" --argjson added "${CODEX_ADDED:-{\}}" "$@"; }

# hook の入口。jq 1 回目で入力から session_id と事実だけを取り出す。
codex_hook() {
  local sub=$1 input now meta sid turn aid tmo file fact
  input=$(cat) || return 0
  now=$(sg_now)
  meta=$(jq -r --argjson now "$now" --arg sub "$sub" '
    . as $in | (($in.agent_id | strings) // "") as $aid
    | (if $aid == "" then "root" else $aid end) as $parent
    | ($in.tool_response | if type == "string" then (fromjson? // .) else . end) as $r
    | (if $sub == "record" then
         if $in.tool_name == "collaborationspawn_agent" then
           (($r | objects | .task_name | strings) // null) as $tn
           | if $tn then {file: "accepts", v: {event: "spawn", target: $tn, turn_id: $in.turn_id, at: $now, parent: $parent}} else null end
         elif $in.tool_name == "collaborationfollowup_task" then
           (($in.tool_input | objects | .target | strings) // null) as $tg
           | if $tg then {file: "accepts", v: {event: "followup", target: $tg, turn_id: $in.turn_id, at: $now, parent: $parent}} else null end
         elif $in.tool_name == "collaborationinterrupt_agent" then
           (($in.tool_input | objects | .target | strings) // null) as $tg
           # 応答は {"previous_status":{"<状態名>":…}} (実測) か、状態名の文字列 (未実測の形) を受ける。
           | (($r | objects | .previous_status) | if type == "object" then (keys[0] // null) elif type == "string" then . else null end) as $ps
           | if $tg then {file: "interrupts", needdir: true, v: {target: $tg, at: $now, parent: $parent, previous_status: $ps}} else null end
         elif $in.tool_name == "collaborationwait_agent" and $aid == "" then
           {file: "waits", needdir: true, v: {at: $now, turn_id: $in.turn_id, timeout_ms: (($in.tool_input | objects | .timeout_ms | numbers) // null)}}
         else null end
       elif $sub == "subagent-start" and $aid != "" then
         {file: "children", v: {agent_id: $aid, rollout: (($in.transcript_path | strings) // null), start_turn_hint: $in.turn_id, at: $now}}
       elif $sub == "subagent-stop" and $aid != "" then
         {file: "children", v: {agent_id: $aid, rollout: (($in.agent_transcript_path | strings) // null), at: $now}}
       else null end) as $f
    | [($in.session_id | tostring), (($in.turn_id // "") | tostring), $aid,
       (($in.tool_input | objects | .timeout_ms | numbers) // 0 | tostring),
       (if $f then $f.file + (if $f.needdir then "?" else "" end) else "" end), ($f.v | tojson)] | join("\u001f")' <<<"$input" 2>/dev/null) || return 0
  meta=${meta//$SG_CR/}
  # 区切りは US (0x1f)。@tsv は逆斜線 (Windows のパス) を二重にし、タブ区切りでは空の欄が詰まるため。
  IFS=$'\x1f' read -r sid turn aid tmo file fact <<<"$meta"
  sg_valid_sid "$sid" || return 0
  sg_mark_hooked codex "$sid"
  sg_disabled && return 0
  local dir
  dir=$(sg_session_dir codex "$sid") || return 0
  case $sub in
    record)
      [ -n "$file" ] || return 0
      # 受付・wait・interrupt の事実を追記するだけ (lock を取らない)。wait と interrupt は受付の無いセッションでは要らない。
      if [ "${file%\?}" != "$file" ]; then
        [ -d "$dir" ] || return 0
        file=${file%\?}
      fi
      sg_append "$dir/$file.jsonl" "$fact"
      # 親の wait_agent から戻ったら、その時点の子の内容を示す (待機を内容の確認点にする)。
      if [ "$file" = waits ]; then
        codex_advance "$dir" 2
        codex_decide post-wait "$dir" "$turn" "$tmo" "$now"
      fi
      ;;
    subagent-start | subagent-stop)
      [ -n "$file" ] || return 0
      # 台帳に無い子も取り込む (由来不明の子。受付は無く、関所の対象にはならない)。
      sg_append "$dir/$file.jsonl" "$fact" || return 0
      codex_advance "$dir" 2
      ;;
    stop-check | pre-wait | inject)
      # 子自身のターン・子の wait_agent は判定に使わない。
      [ -z "$aid" ] && [ -d "$dir" ] || return 0
      if [ "$sub" = inject ]; then codex_advance "$dir" 2; else codex_advance "$dir" 8; fi
      codex_decide "$sub" "$dir" "$turn" "$tmo" "$now"
      ;;
  esac
  return 0
}

# セッション単位の lock (mkdir)。待ち秒の間に取れなければ非 0。古い lock は落ちた hook の残骸として外す。
codex_lock() {
  local lock=$1 wait=${STALL_GUARD_LOCK_WAIT:-$2} t0 t m i=0
  t0=${EPOCHREALTIME//[.,]/}
  until mkdir "$lock" 2>/dev/null; do
    if [ $((i % 10)) -eq 0 ] && m=$(date -r "$lock" +%s 2>/dev/null) && [ $(($(printf '%(%s)T' -1) - m)) -gt $CODEX_LOCK_STALE ]; then
      rmdir "$lock" 2>/dev/null
    fi
    i=$((i + 1))
    t=${EPOCHREALTIME//[.,]/}
    [ $((t - t0)) -ge $((wait * 1000000)) ] && return 1
    sleep 0.1
  done
  return 0
}

# 既知の子の rollout を読み終えた位置から読み、run の開始・終端の事実を runs.jsonl に書き、畳み込みを fold.json に書く。
# lock を取れなければ読み進めずに戻る (呼び出し元は前回の fold.json で判定する)。
codex_advance() {
  local dir=$1 lock="$1/advance.lock"
  codex_lock "$lock" "$2" || return 1
  local LC_ALL=C list aid path off data chunk facts mt now
  now=$(sg_now)
  sg_files "$dir" children offsets
  list=$(jq -nrR "$SG_JQ_LOAD"'sg_load as $L
    | (reduce ($L.offsets // [])[] as $o ({}; .[$o.agent_id] = ([.[$o.agent_id] // 0, $o.offset] | max))) as $off
    | (reduce ($L.children // [])[] as $c ({}; if $c.rollout then .[$c.agent_id] = $c.rollout else . end))
    | to_entries[] | [.key, .value, ($off[.key] // 0 | tostring)] | join("\u001f")' ${SG_FILES[@]+"${SG_FILES[@]}"} /dev/null 2>/dev/null)
  list=${list//$SG_CR/}
  while IFS=$'\x1f' read -r aid path off; do
    sg_valid_sid "$aid" && [ -f "$path" ] || continue
    data=$(tail -c +$((off + 1)) "$path" 2>/dev/null; printf x)
    data=${data%x}
    # 改行で終わっていない最後の行は書きかけなので次回に回す。
    [[ $data == *$'\n'* ]] || continue
    chunk=${data%$'\n'*}$'\n'
    facts=$(jq -cR --arg aid "$aid" --argjson now "$now" '
      fromjson? | objects
      | (((.timestamp | strings | sub("[.][0-9]+"; "") | fromdateiso8601?) // $now)) as $at
      | if .type == "session_meta" then
          ((.payload.agent_path | strings) // (.payload.source | objects | .subagent.thread_spawn.agent_path | strings) // null) as $p
          | if $p then {event: "meta", agent_id: $aid, agent_path: $p} else empty end
        elif .type == "event_msg" then .payload as $p
          | if $p.type == "task_started" then
              {event: "started", agent_id: $aid, turn_id: ($p.turn_id // $p.turn_attribution.turn_id), at: $at,
               parent_turn_id: $p.turn_attribution.parent_turn_id, initiating_agent_path: $p.turn_attribution.initiating_agent_path}
            elif $p.type == "task_complete" or $p.type == "turn_complete" then
              {event: "ended", agent_id: $aid, turn_id: $p.turn_id, end: "completed", at: $at}
            elif $p.type == "turn_aborted" then
              {event: "ended", agent_id: $aid, turn_id: $p.turn_id, end: "aborted", at: $at}
            else empty end
        else empty end' <<<"$chunk" 2>/dev/null) || continue
    facts=${facts//$SG_CR/}
    [ -n "$facts" ] && printf '%s\n' "$facts" >>"$dir/runs.jsonl"
    mt=$(date -r "$path" +%s 2>/dev/null) || mt=null
    sg_append "$dir/offsets.jsonl" "{\"agent_id\":\"$aid\",\"offset\":$((off + ${#chunk})),\"mtime\":$mt}"
  done <<<"$list"
  local plan
  sg_files "$dir" children accepts interrupts runs offsets
  plan=$(codex_jq -nrR --argjson now "$now" "$SG_JQ_LOAD$CODEX_JQ_DEFS"'
    sg_load as $L | "W\tfold.json\t\(fold($L; $now) | tojson)"' ${SG_FILES[@]+"${SG_FILES[@]}"} /dev/null 2>/dev/null)
  [ -n "$plan" ] && sg_apply "$dir" "$plan"
  rmdir "$lock" 2>/dev/null
  return 0
}

codex_decide() {
  local sub=$1 dir=$2 turn=$3 tmo=$4 now=$5 plan files
  # 子の rollout の最新の内容 (発言・ツールの呼出し・結果) を run の事実に添える。
  local args=()
  # 読むのは終わっていない run と未回収の run の子だけ (終わった子の rollout は読まない)。
  [ -f "$dir/children.jsonl" ] && [ -f "$dir/fold.json" ] && mapfile -t args < <(jq -cR 'fromjson? | objects' "$dir/children.jsonl" 2>/dev/null | jq -rs --slurpfile F "$dir/fold.json" '
    [$F[0].runs[]? | select(.end != "completed") | .agent_id] as $live
    | map(select((.rollout | type) == "string" and (.agent_id as $a | $live | index($a)))) | group_by(.agent_id)[] | last
    | .agent_id, .rollout, 0' 2>/dev/null | tr -d '\r')
  local CODEX_ADDED
  CODEX_ADDED=$(sg_added_map ${args[@]+"${args[@]}"}) || CODEX_ADDED='{}'
  sg_files "$dir" accepts waits blocks released notified
  files=(${SG_FILES[@]+"${SG_FILES[@]}"} /dev/null)
  [ -f "$dir/fold.json" ] && files+=("$dir/fold.json")
  plan=$(codex_jq -nrR --arg sub "$sub" --arg turn "$turn" --argjson tmo "${tmo:-0}" --argjson now "$now" "$SG_JQ_LOAD$CODEX_JQ_DEFS"'
    sg_load as $L | fold_file($L) as $F | targets($F; $L; $turn; $now) as $T
    | (($T.runs | length) + ($T.pending | length)) as $n
    | ([$T.runs[] | run_fact($now)] + [$T.pending[] | pending_fact($now)] | join("\n")) as $facts
    | if $sub == "stop-check" then
        if $n == 0 or any(($L.released // [])[]; .turn_id == $turn) then empty
        else [($L.blocks // [])[] | select(.turn_id == $turn)] as $B | ($L.waits // []) as $W | ($B | length) as $k
          # 歯止め: 前の block から次の Stop までに interval 以上の wait_agent が無い block が 2 回続いたら、そのターンでは block しない。
          | if $k >= 2 and (complied($W; $B[$k - 2].waits_seen; $B[$k - 1].waits_seen; $turn) | not)
                       and (complied($W; $B[$k - 1].waits_seen; $W | length; $turn) | not) then
              "A\treleased\t\({turn_id: $turn, at: $now} | tojson)",
              ($T.runs[] | "A\truns\t\({event: "released", agent_id, turn_id, at: $now} | tojson)")
            else
              "A\tblocks\t\({turn_id: $turn, at: $now, waits_seen: ($W | length)} | tojson)",
              "O\t\({decision: "block", reason: ("stall-guard: このターンで受け付けた子の run がまだ終わっていない。"
                + "ターンを終える前に wait_agent を timeout_ms \($wait_ms) 以上で呼んで待つか、止めるなら interrupt_agent を使う"
                + " (wait_agent は子が終われば早く戻る)。\n" + $facts)} | tojson)"
            end
        end
      elif $sub == "post-wait" then
        # 内容を示す対象は、終了を止める対象 (このターンの受付) と分け、動いている run 全部にする。
        [$F.runs[] | select(.end == null)] as $live
        | ([$live[] | run_fact($now)] | join("\n")) as $facts
        | if ($live | length) > 0 then
          "O\t\({hookSpecificOutput: {hookEventName: "PostToolUse",
            additionalContext: ("stall-guard: wait_agent から戻った時点の子の run の事実。rollout の内容が目的の結果へ近づいているかで、"
              + "待ち続けるか止めるかを判断する (更新時刻だけでは判断しない)。\n" + $facts)}} | tojson)"
        else empty end
      elif $sub == "pre-wait" then
        if $n > 0 and $tmo < $wait_ms then
          "O\t\({hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
            permissionDecisionReason: ("stall-guard: このターンで受け付けた子の run を待つ wait_agent は timeout_ms を \($wait_ms) 以上にする"
              + " (今は \($tmo)。子が終われば早く戻る)。\n" + $facts)}} | tojson)"
        else empty end
      else
        ($L.notified // []) as $N
        | [$F.runs[] | select(.end == null)] as $run
        | [($L.released // [])[] | . as $r | select(any($N[]; .released_turn == $r.turn_id) | not)] as $rel
        | [unrecovered($F)[] | . as $u | select(any($N[]; .agent_id == $u.agent_id and .turn_id == $u.turn_id and .end == $u.end) | not)] as $unr
        | "A\tturns\t\({turn_id: $turn, at: $now} | tojson)",
          ($unr[] | "A\tnotified\t\({agent_id, turn_id, end, at: $now} | tojson)"),
          ($rel[] | "A\tnotified\t\({released_turn: .turn_id, at: $now} | tojson)"),
          (if ($run | length) + ($rel | length) + ($unr | length) == 0 then empty
           else "O\t\({hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: (["stall-guard: 子の run の事実 (止めるか待つかはここで判断する。進捗は rollout の内容が目的の結果へ近づいているかで判断し、更新時刻だけでは判断しない)。"]
             + (if ($run | length) > 0 then ["動いている run (前のターンから持ち越したものを含む):"] + [$run[] | run_fact($now)
                 + (if .accepted_turn == null then "、受付の記録なし (由来不明)" elif .accepted_turn != $turn then "、受け付けたターン \(.accepted_turn)" else "" end)] else [] end)
             + (if ($unr | length) > 0 then ["完了せずに終わった run (未回収。成果を受け取れていない):"] + [$unr[] | run_fact($now)] else [] end)
             + (if ($rel | length) > 0 then ["wait_agent で待たずに抜けたターン: " + ([$rel[] | .turn_id] | join(", "))] else [] end)
             | join("\n"))}} | tojson)" end)
      end' "${files[@]}" 2>/dev/null) || return 0
  sg_apply "$dir" "$plan"
}

codex_status() {
  local json=false sid=${CODEX_THREAD_ID:-}
  while [ $# -gt 0 ]; do
    case $1 in
      --json) json=true ;;
      --session) sid=${2:-}; shift ;;
    esac
    shift
  done
  if ! sg_valid_sid "$sid"; then echo "stall-guard: no valid session (use --session <id>)" >&2; return 1; fi
  local dir hooked=false now out
  dir=$(sg_session_dir codex "$sid")
  [ -e "$SG_ROOT/hooked/codex/$sid" ] && hooked=true
  now=$(sg_now)
  sg_files "$dir" children accepts interrupts runs offsets released turns
  out=$(codex_jq -nrR --arg sid "$sid" --argjson hooked "$hooked" --argjson now "$now" --argjson json "$json" \
    "$SG_JQ_LOAD$CODEX_JQ_DEFS"'
    sg_load as $L | fold($L; $now) as $F | (lastof($L.turns).turn_id) as $lt
    | {session: $sid, hooked: $hooked, skipped_lines: $L._skipped,
       children: $F.children,
       running: [$F.runs[] | select(.end == null)
         | {agent_id, task_name, turn_id, elapsed_sec: ($now - .accepted_at), accepted_turn, parent, released,
            carried: (.accepted_turn == null or ($lt != null and .accepted_turn != $lt))}],
       unrecovered: [unrecovered($F)[] | {agent_id, task_name, turn_id, end, released}],
       pending: [$F.pending[] | {target, turn_id, at, expired: expired(.; $now), boundary_seen}],
       released: [($L.released // [])[] | {turn_id, at}]} as $s
    | "S\t\($L._skipped)",
      if $json then "O\t\($s | tojson)"
      else "O\tsession \($sid) hooked=\($hooked)",
        ($s.running[] | "O\trunning \(.task_name) agent=\(.agent_id) turn=\(.turn_id) elapsed=\(.elapsed_sec)s accepted_turn=\(.accepted_turn) carried=\(.carried)"),
        ($s.unrecovered[] | "O\tunrecovered \(.task_name) agent=\(.agent_id) turn=\(.turn_id) end=\(.end) released=\(.released)"),
        ($s.pending[] | "O\tpending \(.target) turn=\(.turn_id) expired=\(.expired) boundary_seen=\(.boundary_seen)"),
        ($s.released[] | "O\treleased turn=\(.turn_id) at=\(.at | todate)")
      end' ${SG_FILES[@]+"${SG_FILES[@]}"} /dev/null) || return 0
  sg_apply "$dir" "$out"
}
