#!/usr/bin/env bash
# Codex の監視 hook を、偽の hook 入力と最小の rollout で確かめる。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/task-monitor-codex.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/task-monitor-codex-test.XXXXXX")
pids=()
stop_pids() { local p; for p in ${pids[@]+"${pids[@]}"}; do pkill -P "$p" 2>/dev/null || :; kill "$p" 2>/dev/null || :; done; pids=(); }
trap 'stop_pids; rm -rf "$work"' EXIT
# 監視 hook は Codex が直接起動したプロセスを調べる。テストではこのスクリプトを Codex に見立てる
export TASK_MONITOR_STATE_DIR="$work/state" TASK_MONITOR_CODEX_SESSIONS="$work/sessions" TASK_MONITOR_CODEX_PID=$$ KATA_STATE_DIR="$work/kata"
R="$work/rollout.jsonl"
: > "$R"

fail() { echo "not ok: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
has() { grep -qF -- "$2" <<<"$1" || fail "$3: '$2' が無い: $1"; }
run() { local mode=$1; shift; jq -cn --arg r "$R" "{session_id:\"s1\", transcript_path:\$r} + $1" | bash "$HOOK" "$mode"; }
stop() { run stop '{}'; }
toolcall() { echo '{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"x"}}' >> "$R"; }
running() { ls "$work/state/codex/s1/running" 2>/dev/null | wc -l | tr -d " "; }
# Codex が実行中のコマンドのプロセスへ渡すのと同じ CODEX_TOOL_CALL_ID を持つプロセスを動かす。
# macOS では OS 付属のコマンド (/bin/sleep など) の環境変数を読めないため、テストを動かしている bash を残す
live() { CODEX_TOOL_CALL_ID=$1 "$BASH" -c 'sleep 600; :' & pids+=($!); }

run pre-bash '{tool_use_id:"t1", tool_input:{command:"ls"}}'
run post-bash '{tool_use_id:"t1", tool_response:"ok"}'
[ -z "$(stop)" ] || fail "終わったコマンドで止めた"
ok "組が閉じたコマンドでは止めない"

# kata の計画を実装中のセッションでは、Stop の判定を kata-completion.sh に任せ、そこから呼ばれたときだけ判定する
mkdir -p "$KATA_STATE_DIR/codex/s1" && : > "$KATA_STATE_DIR/codex/s1/plan"
live k1; run pre-bash '{tool_use_id:"k1", tool_input:{command:"make k"}}'
[ -z "$(stop)" ] || fail "計画の実装中に、監視 hook 自身の Stop で判定した"
out=$(jq -cn --arg r "$R" '{session_id:"s1", transcript_path:$r}' | bash "$HOOK" stop from-kata)
has "$out" "make k" "kata-completion から呼ばれた Stop"
stop_pids; rm -rf "$KATA_STATE_DIR/codex/s1" "$work/state/codex/s1/running/cmd-k1"; run prompt '{prompt:"x"}'
ok "計画の実装中は、kata-completion から呼ばれたときだけ判定する"

# PreToolUse の別の hook や承認で止められたコマンドは実行されず、PostToolUse も来ない。
# 動いているかをプロセスから確かめられるのは Linux と macOS だけなので、ここではその 2 つで確かめる
case $(uname -s) in Linux | Darwin)
  # 同時に動く別の hook (呼出し ID を持たない) が、環境変数を読めないコマンドを起動している場合も含めて確かめる
  env -u CODEX_TOOL_CALL_ID "$BASH" -c "env -i $(command -v sleep) 600; :" & pids+=($!)
  run pre-bash '{tool_use_id:"blocked", tool_input:{command:"cat SKILL.md"}}'
  [ -z "$(stop)" ] || fail "実行されなかったコマンドで止めた"
  [ "$(running)" = 0 ] || fail "実行されなかったコマンドの記録が残る"
  stop_pids
  ok "実行されなかったコマンドでは止めず、記録を消す"

  # バックグラウンドに回ったテストが終わったあと、エージェントが write_stdin で結果を読まずに実行し直すことがある。
  # 終わったコマンドを待たせると、終わったものを「まだ終わっていない」と指示することになる
  printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","thread_id":"s1","turn_id":"u1","item":{"type":"CommandExecution","id":"finished","process_id":"4242","command":["bash","-lc","npm test"],"cwd":"file:///repo","source":"unified_exec_startup","status":"completed","exit_code":0,"aggregated_output":"ok"}}}' >> "$R"
  run pre-bash '{tool_use_id:"finished", tool_input:{command:"npm test"}}'
  [ -z "$(stop)" ] || fail "終わったコマンドを待たせた"
  ok "終わったコマンドは、結果を読んでいなくても待たせない"

  live running
  run pre-bash '{tool_use_id:"running", tool_input:{command:"make all"}}'
  run pre-bash '{tool_use_id:"blocked", tool_input:{command:"cat SKILL.md"}}'
  out=$(stop); has "$out" "make all" "実行中のコマンド"
  ! grep -qF "cat SKILL.md" <<<"$out" || fail "実行中のコマンドと一緒に、実行されなかったコマンドも待たせた: $out"
  stop_pids; rm -f "$work/state/codex/s1/running/cmd-running"; run prompt '{prompt:"x"}'
  ok "実行中のコマンドがあっても、実行されなかったコマンドの記録は消す"

  # 環境変数を空にして動くプロセスは、どの呼出しのものか分からない
  env -i "$(command -v sleep)" 600 & pids+=($!)
  run pre-bash '{tool_use_id:"opaque", tool_input:{command:"exec env -i sleep 600"}}'
  run pre-bash '{tool_use_id:"finished", tool_input:{command:"npm test"}}'
  run pre-bash '{tool_use_id:"denied", tool_input:{command:"denied before startup"}}'
  printf '%s\n' '{"type":"event_msg","payload":{"type":"item_completed","thread_id":"s1","item":{"type":"CommandExecution","id":"denied","process_id":null,"status":"failed"}}}' >> "$R"
  out=$(stop); has "$out" "exec env -i sleep 600" "実行結果を確認するコマンド"
  for word in 'yield_time_ms' 'まだ終わっていない' 'npm test' 'denied before startup'; do
    ! grep -qF "$word" <<<"$out" || fail "照合できないときの誤案内: $out"
  done
  [ -z "$(stop)" ] || fail "同じ記録の確認を繰り返した"
  stop_pids; run prompt '{prompt:"x"}'
  ok "プロセスを識別できないときは拒否・完了済みを除き、残った呼び出しの結果確認を一度だけ促す"
;; esac

# 待機間隔の試験には、各 OS で実行中だと確かめられるタスクを使う。
case $(uname -s) in
  Linux | Darwin)
    live t2
    run pre-bash '{tool_use_id:"t2", tool_input:{command:"make build"}}'
    wait_target='make build' ;;
  *)
    run pre-bash '{tool_use_id:"unknown", tool_input:{command:"unidentified"}}'
    out=$(stop); has "$out" "unidentified" "起動結果の確認"
    [ -z "$(stop)" ] || fail "状態を確認できないコマンドを待ち続けた"
    run subagent-start '{agent_id:"initial-child"}'
    wait_target='initial-child' ;;
esac
out=$(stop)
[ "$(jq -r .decision <<<"$out")" = block ] || fail "実行中で止めない: $out"
has "$out" "yield_time_ms は 600000" "1 回目の待ち時間"; has "$out" "$wait_target" "止める理由"
has "$out" "元の目的をやり直して" "止める理由"
ok "実行中のコマンドがあれば 10 分待つよう指示して止める"

out=$(run pre-wait '{tool_name:"collaborationwait_agent", tool_input:{targets:["a"], timeout_ms:10000}}')
[ "$(jq -c '.hookSpecificOutput.updatedInput' <<<"$out")" = '{"targets":["a"],"timeout_ms":600000}' ] || fail "待ち時間の書き換え: $out"
ok "wait_agent の待ち時間を予定へ書き換え、ほかの入力は残す"

toolcall
out=$(stop); has "$out" "yield_time_ms は 1200000" "wait_agent で待った後の待ち時間"
toolcall
out=$(stop); has "$out" "yield_time_ms は 2400000" "write_stdin で待った後の待ち時間"
ok "見に行った後は次の間隔へ進み、wait_agent で待った分を二重に進めない"

run prompt '{prompt:"x"}'
w() { run pre-wait '{tool_input:{timeout_ms:10000}}' | jq -r '.hookSpecificOutput.updatedInput.timeout_ms'; }
[ "$(w) $(w) $(w) $(w)" = "600000 1200000 2400000 2400000" ] || fail "Stop を挟まない連続の wait"
ok "Stop を挟まずに待ち続けても 10・20・40 分と進む"

for _ in 1 2 3 4 5 6 7 8 9 10; do toolcall; out=$(stop); [ "$(jq -r .decision <<<"$out")" = block ] || fail "見に行き続けているのに解放した"; done
has "$out" "yield_time_ms は 2400000" "以後の待ち時間"
ok "見に行き続ける限り、長いタスクでも止め続ける"

run subagent-start '{agent_id:"019a-child"}'
[ "$(w)" = 600000 ] || fail "子の起動直後の wait"
out=$(stop); has "$out" "yield_time_ms は 1200000" "起動後に待ってからの Stop"; has "$out" "019a-child" "新しいタスク"
has "$out" "the same error or the same action repeating" "Stop からの停滞の判断基準"
ok "子を起動したら、Stop を待たずに 10 分から数え直す"

mkdir -p "$work/sessions/2026/11/10"
printf '%s\n' '{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"cargo test\"}"}}' > "$work/sessions/2026/11/10/rollout-2026-11-10T00-00-00-019a-child.jsonl"
out=$(run post-wait '{tool_name:"collaborationwait_agent", tool_response:"Wait timed out."}')
has "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")" "[tool] exec_command" "子の最新の内容"
has "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")" "the same error or the same action repeating" "wait_agent 後の停滞の判断基準"
ok "wait_agent から戻ったら子の最新の内容を渡す"

run subagent-stop '{agent_id:"019a-child"}'
mkdir -p "$work/sessions/2026/11/10"
printf '%s\n' '{"type":"session_meta","payload":{"id":"019c-other","parent_thread_id":"other","agent_path":"/root/fixer"}}' > "$work/sessions/2026/11/10/rollout-2026-11-10T00-00-02-019c-other.jsonl"
printf '%s\n' '{"type":"session_meta","payload":{"id":"019a-old","parent_thread_id":"s1","agent_path":"/root/fixer"}}' > "$work/sessions/2026/11/10/rollout-2026-11-10T00-00-00-019a-old.jsonl"
old=$(( $(date +%s) - 3600 ))
touch -t "$(date -d "@$old" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$old" +%Y%m%d%H%M.%S)" "$work/sessions/2026/11/10/rollout-2026-11-10T00-00-00-019a-old.jsonl"
printf '%s\n' '{"type":"session_meta","payload":{"id":"019b-done","parent_thread_id":"s1","agent_path":"/root/fixer"}}' > "$work/sessions/2026/11/10/rollout-2026-11-10T00-00-01-019b-done.jsonl"
w >/dev/null; w >/dev/null
echo agent-019b-done >> "$work/state/codex/s1/seen"
run post-followup '{tool_name:"collaborationfollowup_task", tool_input:{target:"fixer", message:"retry"}}'
[ -e "$work/state/codex/s1/running/agent-019b-done" ] || fail "再依頼した子が記録されない"
! grep -qx agent-019b-done "$work/state/codex/s1/seen" || fail "再依頼した子を前回見たタスクのまま数えた"
[ ! -e "$work/state/codex/s1/running/agent-019c-other" ] || fail "別のセッションの同名の子を記録した"
[ ! -e "$work/state/codex/s1/running/agent-019a-old" ] || fail "作り直す前の古い子を記録した"
[ "$(w)" = 600000 ] || fail "再依頼で数え直さない"
run post-close '{tool_name:"collaborationclose_agent", tool_input:{target:"/root/fixer"}}'
[ ! -e "$work/state/codex/s1/running/agent-019b-done" ] || fail "止めた子の記録が残る"
ok "終わった子への再依頼を記録し、止めた子の記録を消す"
run pre-bash '{tool_use_id:"c1", agent_id:"019a-child", tool_input:{command:"cargo watch"}}'
[ ! -e "$work/state/codex/s1/running/cmd-c1" ] || fail "子のコマンドを親の記録に入れた"
ok "子エージェントのコマンドは親の記録に入れない"
toolcall; stop >/dev/null
# 直前の stop の後、見に行かないまま 3 回終える
o1=$(stop); o2=$(stop); o3=$(stop)
for o in "$o1" "$o2"; do has "$o" "yield_time_ms" "無視されている間"; done
has "$o3" "報告" "解放"; [ "$(running)" = 0 ] || fail "解放後に記録が残る"
[ -z "$(stop)" ] || fail "解放後も止める"
ok "見に行かないまま 3 回終えたら解放し、残った記録を消す"

w >/dev/null; w >/dev/null
case $(uname -s) in
  Linux | Darwin) live t3; run pre-bash '{tool_use_id:"t3", tool_input:{command:"sleep 1"}}' ;;
  *) run subagent-start '{agent_id:"new-child"}' ;;
esac
out=$(stop); has "$out" "yield_time_ms は 600000" "待った後に起動したコマンド"
ok "待った後に新しいタスクを起動しても 10 分から数え直す"
toolcall; out=$(stop); has "$out" "1200000" "数え直し前"
run prompt '{prompt:"x"}'
out=$(stop); has "$out" "yield_time_ms は 600000" "利用者の入力"
ok "利用者の入力で 10 分から数え直す"
