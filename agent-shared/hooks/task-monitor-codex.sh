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
#   stop                        Stop: 実行中のものがあればターン終了を止める
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
# 同じ名前の子を作り直した場合に備え、新しい rollout から順に見る
resolve_agent() {
  local r id
  find "${TASK_MONITOR_CODEX_SESSIONS:-$HOME/.codex/sessions}" -name 'rollout-*.jsonl' -mmin -1440 -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | cut -d' ' -f2- | while IFS= read -r r; do
      id=$(head -n 1 "$r" | jq -r --arg t "$1" --arg sid "$sid" '.payload | select(.parent_thread_id == $sid)
        | select(.id == $t or .agent_path == $t or (.agent_path // "" | endswith("/" + $t))) | .id' 2>/dev/null)
      [ -n "$id" ] && { printf '%s\n' "$id"; break; }
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
      { [ ! -f "$state/seen" ] || sed -i "/^agent-$id\$/d" "$state/seen"; } ;;
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
    [ -n "$ctx" ] && jq -cn --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext:
      ("監視: 待機中の子の最新の内容です。目的の結果へ進んでいるかを判断し、止まっていれば close_agent か interrupt_agent で止めて、原因を調べ、直すか別の方法で元の目的をやり直してください。\n" + $c)}}' ;;
  stop)
    items=$(ls "$run")
    if [ -z "$items" ]; then reset; exit 0; fi
    transcript=$(field .transcript_path)
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
      jq -cn --arg l "$list" '{decision: "block", reason: ("監視: 実行中として記録したタスクを見に行かないまま 3 回ターンを終えたため、監視をやめました。残っているタスクの状態を確かめ、利用者へ報告して終えてください。\n" + $l)}'
      exit 0
    fi
    printf '%s\n' "$round" > "$state/round"; printf '%s\n' "$idle" > "$state/idle"
    printf '%s\n' "$lines" > "$state/mark"; printf '%s\n' "$items" > "$state/seen"; rm -f "$state/waited"
    ms=$(( $(tm_interval "$round") * 60000 ))
    jq -cn --arg l "$list" --arg ms "$ms" '{decision: "block", reason: ("監視: まだ終わっていないタスクがあります。\n" + $l + "\n" +
      "子エージェントは wait_agent で、コマンドは空の write_stdin (yield_time_ms は " + $ms + ") で待ってから最新の内容を確かめてください。進んでいれば続けて待ち、止まっていれば close_agent / interrupt_agent か write_stdin の割込みで止め、原因を調べて、直すか別の方法で元の目的をやり直して。")}' ;;
esac
exit 0
