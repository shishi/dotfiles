#!/usr/bin/env bash
# Codex の監視 hook。Codex は待機中の親を起こせないため、実行中の子エージェントとバックグラウンドのコマンドが
# 残っている間はターン終了を止め、予定の待ち時間 (10・20・40 分、以後 40 分ごと) で見に行かせる。
# 進んでいるかの判断はエージェント自身が行う。
#   pre-bash / post-bash        PreToolUse / PostToolUse (Bash): tool_use_id の組でコマンドの実行中を記録する
#   subagent-start / -stop      子エージェントの実行中を記録する
#   post-followup               PostToolUse (followup_task): 終わった子への再依頼を実行中として記録する
#   post-close                  PostToolUse (close_agent / interrupt_agent): 止めた子の記録を消す
#   pre-wait                    PreToolUse (wait_agent): timeout_ms を予定の待ち時間へ書き換え、次の間隔へ進める
#   post-wait                   PostToolUse (wait_agent): 待機中の子の rollout の最新の内容を渡す
#   prompt                      UserPromptSubmit: 待ち時間を 10 分から数え直す
#   stop [from-kata]            Stop: 実行中のものがあればターン終了を止める。kata の計画を実装中のセッションでは、
#                               kata-completion.sh から from-kata で呼ばれたときだけ判定する
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$HOOK_DIR/lib/task-monitor-common.sh"

mode=${1:-}
in=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$in")
[ -n "$sid" ] || exit 0
state=$(tm_state_dir codex "$sid") || exit 0
run="$state/running"
mkdir -p "$run"

field() { jq -r "$1 // empty" <<<"$in"; }
# 子への宛先 (agent_path・その末尾の名前・id) から、このセッションの子の rollout の id を返す。
# 別のセッションにも同じ名前の子がいるため、親 (parent_thread_id) がこのセッションのものだけを見る。
# 同じ名前の子を作り直した場合に備え、いちばん新しい rollout の子を選ぶ
resolve_agent() {
  local r id best= newest=
  while IFS= read -r r; do
    id=$(head -n 1 "$r" | jq -r --arg t "$1" --arg sid "$sid" '.payload | select(.parent_thread_id == $sid)
      | select(.id == $t or .agent_path == $t or (.agent_path // "" | endswith("/" + $t))) | .id' 2>/dev/null)
    [ -n "$id" ] && { [ -z "$newest" ] || [ "$r" -nt "$newest" ]; } && best=$id newest=$r
  done < <(find "${TASK_MONITOR_CODEX_SESSIONS:-$HOME/.codex/sessions}" -name 'rollout-*.jsonl' -mmin -1440 2>/dev/null)
  [ -n "$best" ] && printf '%s\n' "$best"
}
# プロセスの環境変数を 1 行 1 つで返す。プロセスが無ければ失敗する。読めなければ空を返す
proc_env() {
  local args all again
  case $os in
    Linux) [ -e "/proc/$1" ] && { tr '\0' '\n' 2>/dev/null < "/proc/$1/environ" || :; } ;;
    # macOS の ps -E は引数のあとに環境変数を空白でつないで出す。OS 付属のコマンドは環境変数を出さない。
    # 読む間に別のコマンドへ置き換わると引数を環境変数と取り違えるため、前後の引数が違えば読めなかった扱いにする
    Darwin) args=$(ps -ww -o command= -p "$1") && all=$(ps -E -ww -o command= -p "$1") &&
      again=$(ps -ww -o command= -p "$1") || return 1
      [ "$args" = "$again" ] || return 0
      case $all in "$args" | "$args "*) printf '%s\n' "${all#"$args"}" | tr ' ' '\n' ;; esac ;;
  esac
}
# Codex が直接起動したプロセス (コマンドごとの起点) から、動いているコマンドの呼出し ID を出す。Codex は
# コマンドのプロセスへ CODEX_TOOL_CALL_ID を渡し、Linux の sandbox の外側のプロセスや macOS のシェルが
# それを持ち続ける。環境変数を読めない起点 (HOME も無い。macOS の OS 付属のコマンドなど) があれば、
# 記録したどのコマンドかを判定できないので失敗を返す。読めて ID の無い起点は hook や MCP サーバーなので数えない。
# 起点が自分で ID だけを消して HOME を残すと、動いていても見落とす。
# hook は Codex から新しいセッションで起動されるため、自分のプロセスグループの先頭の親が Codex になる
live_command_ids() {
  local pg root x e unknown=
  pg=$(ps -o pgid= -p $$)
  root=${TASK_MONITOR_CODEX_PID:-$(ps -o ppid= -p $pg)}
  root=$(( root )) && [ "$root" -gt 1 ] || return 1
  for x in $(ps -A -o pid=,ppid= | awk -v r="$root" -v g="$pg" '$2 == r && $1 != g { print $1 }'); do
    e=$(proc_env "$x") || continue
    case $'\n'$e in
      *$'\n'CODEX_TOOL_CALL_ID=*) sed -n 's/^CODEX_TOOL_CALL_ID=//p' <<<"$e" | head -n 1 ;;
      *$'\n'HOME=*) ;;
      *) unknown=1 ;;
    esac
  done
  [ -z "$unknown" ]
}
# Stop で確認できた呼び出しだけを待つ。OS がプロセスの環境を隠す場合は、このスレッドの終了通知を照合し、
# それでも状態が分からない呼び出しは、セッション ID を受け取ったエージェントへ一度だけ確認を戻す。
prune_commands() {
  local files=("$run"/cmd-*) live= finished= complete= f id command
  [ -e "${files[0]}" ] || return 0
  os=$(uname -s)
  case $os in
    Linux | Darwin) if live=$(live_command_ids); then complete=1; fi ;;
  esac
  if [ -z "$complete" ] && [ -r "$transcript" ]; then
    finished=$(jq -Rr --arg sid "$sid" 'fromjson? | select(.type == "event_msg") | .payload
      | select(.thread_id == $sid and .type == "item_completed") | .item
      | select(.type == "CommandExecution" and (.status == "completed" or .status == "failed" or .status == "declined")) | .id' "$transcript")
  fi
  for f in "${files[@]}"; do
    id=${f##*/cmd-}
    grep -qxF -- "$id" <<<"$live" && continue
    if [ -z "$complete" ] && ! grep -qxF -- "$id" <<<"$finished"; then
      command=$(jq -r .command "$f" 2>/dev/null) || continue
      check_list+=$'\n- '"$command"
    fi
    rm -f "$f"
  done
}
num() { cat "$state/$1" 2>/dev/null || echo 0; }
reset() { rm -f "$state/round" "$state/idle" "$state/mark" "$state/seen" "$state/waited"; }

# 子エージェント自身のツール呼出し (agent_id がある) は子が扱う。親の記録・間隔を変えない。
# 子のコマンドは親からは write_stdin で待てない
case $mode in
  pre-bash|pre-wait|post-followup|post-close) [ -n "$(field .agent_id)" ] && exit 0 ;;
esac

case $mode in
  pre-bash)
    id=$(field .tool_use_id); [ -n "$id" ] && jq -c '{command: .tool_input.command}' <<<"$in" > "$run/cmd-$id" ;;
  post-bash)
    id=$(field .tool_use_id); [ -n "$id" ] && rm -f "$run/cmd-$id" ;;
  subagent-start)
    id=$(field .agent_id); [ -n "$id" ] && printf '{}\n' > "$run/agent-$id" && rm -f "$state/round" ;;
  post-followup)
    # 終わった子への再依頼では SubagentStart が発火しない。宛先 (agent_path か id) から子の rollout を探し、
    # その id で記録する。子のターンが終わると SubagentStop が同じ id で記録を消す。
    target=$(field .tool_input.target)
    [ -n "$target" ] || exit 0
    id=$(resolve_agent "$target")
    # 前回の Stop の後に終わった子は seen に残っているため、seen からも消して新しいタスクとして数える
    [ -n "$id" ] && printf '{}\n' > "$run/agent-$id" && rm -f "$state/round" &&
      { [ ! -f "$state/seen" ] || { grep -vxF "agent-$id" "$state/seen" > "$state/seen.new"; mv "$state/seen.new" "$state/seen"; }; } ;;
  post-close)
    # 止めた子に SubagentStop が来るとは限らない。記録が残ると、止めた子を待つよう指示し続けるため消す
    target=$(field .tool_input.target)
    [ -n "$target" ] || exit 0
    id=$(resolve_agent "$target")
    [ -n "$id" ] && rm -f "$run/agent-$id" ;;
  subagent-stop)
    id=$(field .agent_id); [ -n "$id" ] && rm -f "$run/agent-$id" ;;
  prompt)
    reset ;;
  pre-wait)
    # 待つたびに 10・20・40 分と進める。Stop を挟まずに待ち続けても間隔が進み、新しいタスクの起動で 0 に戻る。
    round=$(num round)
    ms=$(( $(tm_interval "$round") * 60000 ))
    printf '%s\n' $((round + 1)) > "$state/round"; : > "$state/waited"
    jq -c --argjson ms "$ms" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
      updatedInput: ((.tool_input // {}) + {timeout_ms: $ms})}}' <<<"$in" ;;
  post-wait)
    ctx=
    for f in "$run"/agent-*; do
      [ -e "$f" ] || continue
      id=${f##*/agent-}
      r=$(ls -t "${TASK_MONITOR_CODEX_SESSIONS:-$HOME/.codex/sessions}"/*/*/*/rollout-*"$id"*.jsonl 2>/dev/null | head -n 1)
      [ -n "$r" ] && ctx="$ctx## 子 $id"$'\n'"$(tm_excerpt "$r" 1500)"$'\n'
    done
    [ -n "$ctx" ] && jq -cn --arg c "$ctx" --arg criteria "$(tm_progress_criteria)" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext:
      ("監視: 待機中の子の最新の内容です。完了した子の結果は回収してください。まだ実行中の子は目的の結果へ進んでいるかを判断し、止まっていれば close_agent か interrupt_agent で止めて、原因を調べ、直すか別の方法で元の目的をやり直してください。\n進捗の判断基準:\n" + $criteria + "\n\n" + $c)}}' ;;
  stop)
    # kata の計画を実装中は、kata-completion.sh がこの判定を呼び、止めない場合だけ計画の完了を判定する。
    # 2 つの Stop hook が別々に判定すると、その間にコマンドが終わったとき、一方は待つものがあるとして判定をやめ、
    # 他方は止めずにターンが終わるため、判定はその呼出しの 1 回だけにする。計画の記録の場所は kata-active・
    # kata-completion.sh と同じにする (ずれると両方の Stop で判定する)
    [ "${2:-}" = from-kata ] || [ ! -f "${KATA_STATE_DIR:-/tmp/claude-$(id -u)/kata}/codex/$sid/plan" ] || exit 0
    transcript=$(field .transcript_path)
    check_list= notice=
    prune_commands
    if [ -n "$check_list" ]; then
      notice="監視 hook では次の呼び出しの状態を確認できません。ツールの返答を確認し、実行中のセッション ID が返っていたものだけ結果を回収してください。起動拒否・終了済みなら、この確認は完了です。$check_list"
    fi
    items=$(ls "$run")
    if [ -z "$items" ]; then
      reset
      [ -z "$notice" ] || jq -cn --arg reason "$notice" '{decision: "block", reason: $reason}'
      exit 0
    fi
    [ -z "$notice" ] || notice=$'\n'"$notice"
    lines=0; [ -f "$transcript" ] && lines=$(wc -l < "$transcript")
    [ -f "$state/seen" ] || : > "$state/seen"
    new=$(comm -23 <(printf '%s\n' "$items") "$state/seen")
    if [ -n "$new" ]; then
      # 子の起動・再依頼は hook で 0 に戻している (その後の wait_agent で進んでいれば、それを使う)。
      # コマンドには起動時に戻す hook がないため、新しいコマンドがあればここで 0 に戻す
      case $'\n'"$new" in *$'\n'cmd-*) round=0 ;; *) round=$(num round) ;; esac
      idle=0
    elif [ "$lines" -gt "$(num mark)" ] &&
         tail -n +"$(( $(num mark) + 1 ))" "$transcript" | jq -R -e -n '
           [inputs | fromjson? | select(.type == "response_item") | .payload.type
            | select(. == "function_call" or . == "custom_tool_call" or . == "local_shell_call")] | length > 0' >/dev/null; then
      # wait_agent で待った場合は pre-wait が間隔を進めている。write_stdin で待った場合だけここで進める
      if [ -e "$state/waited" ]; then round=$(num round); else round=$(( $(num round) + 1 )); fi
      idle=0
    else
      round=$(num round) idle=$(( $(num idle) + 1 ))
    fi
    list=$(for i in $items; do
      case $i in
        cmd-*) printf -- '- バックグラウンドのコマンド: %s\n' "$(jq -r .command "$run/$i")" ;;
        agent-*) printf -- '- 子エージェント: %s\n' "${i#agent-}" ;;
      esac
    done)
    if [ "$idle" -ge 3 ]; then
      rm -f "$run"/*; reset
      jq -cn --arg n "$notice" --arg l "$list" '{decision: "block", reason: ("監視: 実行中として記録したタスクを見に行かないまま 3 回ターンを終えたため、監視をやめました。残っているタスクの状態を確かめ、利用者へ報告して終えてください。\n" + $l + $n)}'
      exit 0
    fi
    printf '%s\n' "$round" > "$state/round"; printf '%s\n' "$idle" > "$state/idle"
    printf '%s\n' "$lines" > "$state/mark"; printf '%s\n' "$items" > "$state/seen"; rm -f "$state/waited"
    ms=$(( $(tm_interval "$round") * 60000 ))
    jq -cn --arg n "$notice" --arg l "$list" --arg ms "$ms" --arg criteria "$(tm_progress_criteria)" '{decision: "block", reason: ("監視: まだ終わっていないタスクがあります。\n" + $l + "\n" +
      "子エージェントは wait_agent で、コマンドは空の write_stdin (yield_time_ms は " + $ms + ") で待ってから最新の内容を確かめてください。完了していれば結果を回収し、進んでいれば続けて待ってください。止まっていれば close_agent / interrupt_agent か write_stdin の割込みで止め、原因を調べて、直すか別の方法で元の目的をやり直して。" + $n + "\n進捗の判断基準:\n" + $criteria)}' ;;
esac
exit 0
