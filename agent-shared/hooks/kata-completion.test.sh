#!/usr/bin/env bash
# kata の完了確認 hook と kata-active を、偽の判定役と最小の会話記録で確かめる。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/kata-completion.sh"
ACTIVE="$HOOK_DIR/../bin/kata-active"
work=$(mktemp -d "${TMPDIR:-/tmp}/kata-completion-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
export KATA_STATE_DIR="$work/state" TASK_MONITOR_STATE_DIR="$work/task-monitor"
# 委譲された子の中でテストを流しても、委譲の目印で判定を飛ばさないようにする
unset AGENT_DELEGATED_SESSION T3CODE_THREAD_ID CODEX_INTERNAL_ORIGINATOR_OVERRIDE
export CLAUDE_CODE_SESSION_ID=s1 CODEX_THREAD_ID=c1
printf '# Plan\n## Task 1\n' > "$work/plan.md"
printf 'Task 1: verified (review pending)\n' > "$work/progress.md"
T="$work/transcript.jsonl"
cat > "$T" <<'EOF'
{"type":"user","message":{"content":"最初の依頼"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"make test"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"human"},"prompt":"作業中に送った訂正"}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"task-notification","origin":{"kind":"task-notification"},"prompt":"<task-notification>作業中の完了通知</task-notification>"}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","origin":{"kind":"peer","from":"a1"},"prompt":"<agent-message from=\"a1\">子エージェントの報告</agent-message>"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"最初の依頼の結果を報告しました"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"続けて"}],"internal_chat_message_metadata_passthrough":{"content_item_metadata":[{"provenance":{"type":"user"}}]}}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<hook_prompt>差し戻し</hook_prompt>"}],"internal_chat_message_metadata_passthrough":{"content_item_metadata":[{"provenance":{"type":"harness","hook":true}}]}}}
{"type":"user","isMeta":true,"message":{"content":"注入された指示"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Task 1 を終えました"}]}}
{"type":"user","promptSource":"system","origin":{"kind":"task-notification"},"message":{"content":"<task-notification>タスクの完了通知</task-notification>"}}
{"type":"user","isCompactSummary":true,"message":{"content":"圧縮後の要約"}}
{"type":"user","message":{"content":"<local-command-stdout>コマンドの出力</local-command-stdout>"}}
EOF

fail() { echo "not ok: $1" >&2; echo "$1" >> "$work/failures"; exit 1; }
ok() { echo "ok: $1"; }
# 判定役の代わり: 受け取った入力を残し、JUDGE_STATUS の判定を claude -p の JSON 出力の形で返す
cat > "$work/judge.sh" <<'EOF'
cat > "$JUDGE_INPUT"
[ "$JUDGE_STATUS" = fail ] && exit 1
# 判定の途中で利用者が新しく発言した場合を作る
[ -z "${JUDGE_APPEND:-}" ] || printf '%s\n' "$JUDGE_APPEND" >> "$T"
jq -cn --arg s "$JUDGE_STATUS" '{is_error:false, subtype:"success", structured_output:{status:$s, reason:"テストの理由"}}'
EOF
export KATA_COMPLETION_JUDGE="bash $work/judge.sh" JUDGE_INPUT="$work/judge-input" T
# stop <判定> [追加の入力 JSON] [CLI]。差し戻したときだけ、その内容を出す。Claude Code では後から起こすため
# 終了コード 2 と標準エラー、Codex では標準出力の JSON で差し戻す
stop() {
  local rc=0 out
  local args=("${3:-claude}")
  [ -z "${4:-}" ] || args+=("$4")
  rm -f "$JUDGE_INPUT"
  out=$(jq -cn --arg t "$T" "{session_id:\"s1\", cwd:\"/\", transcript_path:\$t, last_assistant_message:\"Task 1 を終えました\"} + ${2:-{\}}" |
    JUDGE_STATUS=$1 bash "$HOOK" "${args[@]}" 2>"$work/err") || rc=$?
  if [ "${3:-claude}" = claude ]; then
    # Claude Code は終了コード 2 でだけエージェントを起こす。標準出力の decision は読まない
    [ -z "$out" ] || fail "Claude Code の Stop で標準出力に書いた: $out"
    case $rc in
      0) ;;
      2) [ -s "$work/err" ] || fail "Claude Code の Stop が理由なしに終了コード 2 で終わった"; cat "$work/err" ;;
      *) fail "Claude Code の Stop が終了コード $rc で終わった" ;;
    esac
  else
    [ "$rc" -eq 0 ] || fail "Codex の Stop が終了コード $rc で終わった"
    # 差し戻すときは decision: block の JSON で返す
    [ -z "$out" ] || [ "$(jq -r .decision <<<"$out" 2>/dev/null)" = block ] || fail "Codex の Stop の出力が差し戻しの JSON ではない: $out"
    printf '%s' "$out"
  fi
}
marked() { [ -f "$work/state/claude/s1/plan" ]; }

mkdir -p "$TASK_MONITOR_STATE_DIR/codex/s1/running"
: > "$TASK_MONITOR_STATE_DIR/codex/s1/running/agent-no-plan"
out=$(stop continue '{}' codex stop)
grep -qF '子エージェント: no-plan' <<<"$out" && [ ! -e "$JUDGE_INPUT" ] || fail "Codex の Stop が計画のないセッションで監視を行わなかった: $out"
[ -z "$(stop continue '{}' codex)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "旧登録が別の Stop hook と重複して監視した"
rm "$TASK_MONITOR_STATE_DIR/codex/s1/running/agent-no-plan"
[ -z "$(stop continue '{}' codex stop)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "Codex の Stop が計画もバックグラウンドのタスクもないセッションを差し戻した"
ok "Codex の統合した Stop は計画なしでも監視し、待つものがなければ判定しない"

out=$(stop continue)
grep -qF "kata:" <<<"$out" && grep -qF テストの理由 <<<"$out" || fail "計画が無いセッションで未完了を差し戻さない: $out"
grep -qF kata-active <<<"$out" && fail "計画が無いのに計画の記録の消し方を案内した: $out"
requests=$(sed -n '/^USER REQUESTS:$/,/^LAST USER MESSAGE:$/p' "$JUDGE_INPUT")
grep -qF 最初の依頼 <<<"$requests" && grep -qF 続けて <<<"$requests" || fail "このセッションの依頼をすべて判定役へ渡さない: $requests"
grep -qF -e 注入された指示 -e 差し戻し -e タスクの完了通知 -e 圧縮後の要約 -e コマンドの出力 <<<"$requests" && fail "注入された指示・hook の差し戻し・タスクの完了通知・圧縮の要約・コマンドの出力を依頼として渡した"
grep -qF 最初の依頼の結果を報告しました <<<"$requests" || fail "前のターンのエージェントの最後の文を判定役へ渡さない: $requests"
grep -qF 作業中に送った訂正 <<<"$requests" || fail "作業の途中で送った利用者の発言を判定役へ渡さない: $requests"
grep -qF -e 作業中の完了通知 -e 子エージェントの報告 <<<"$requests" && fail "作業の途中に届いた完了通知や子エージェントの報告を依頼として渡した"
rm -rf "$work/state"
ok "計画が無いセッションでも、このセッションの依頼を材料に判定して差し戻す"

[ -z "$(stop complete)" ] && [ -z "$(stop waiting_on_human)" ] || fail "計画が無いセッションで、完了・本人待ちなのに差し戻した"
[ -z "$(AGENT_DELEGATED_SESSION=1 stop continue)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "委譲された子のセッションを判定した"
P="$work/print.jsonl"
printf '%s\n' '{"type":"user","entrypoint":"sdk-cli","message":{"content":"1 行で答えて"}}' > "$P"
[ -z "$(jq -cn --arg t "$P" '{session_id:"s1", cwd:"/", transcript_path:$t}' | JUDGE_STATUS=continue bash "$HOOK" claude 2>/dev/null)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "計画が無い claude -p の実行を判定した"
# claude -p で始めた会話を対話で再開したら、今の起動方法で判定する
printf '%s\n' '{"type":"user","entrypoint":"cli","message":{"content":"続きを直して"}}' >> "$P"
jq -cn --arg t "$P" '{session_id:"s1", cwd:"/", transcript_path:$t}' | JUDGE_STATUS=continue bash "$HOOK" claude >/dev/null 2>&1 || :
[ -e "$JUDGE_INPUT" ] || fail "claude -p で始めて対話で再開した会話を判定しない"
rm -rf "$work/state"
ok "計画が無いセッションは、完了・本人待ちなら止め、委譲された子と claude -p の実行は判定しない"

bash "$ACTIVE" claude start "$work/plan.md" >/dev/null
[ "$(bash "$ACTIVE" claude status)" = "$(realpath "$work/plan.md")" ] || fail "start の記録"
CLAUDE_CODE_SESSION_ID=other bash "$ACTIVE" claude status | grep -q 記録はありません || fail "別セッションに記録が見える"
CODEX_THREAD_ID=c1 bash "$ACTIVE" codex status | grep -q 記録はありません || fail "Claude の記録が Codex のセッションに見える"
ok "kata-active は指定した CLI のこのセッションにだけ計画を記録する"

out=$(stop continue)
grep -qF "kata:" <<<"$out" || fail "continue で差し戻さない: $out"
grep -qF "$(realpath "$work/plan.md")" <<<"$out" && grep -qF テストの理由 <<<"$out" || fail "差し戻しの理由: $out"
for want in "## Task 1" "Task 1: verified" "[tool] Bash"; do
  grep -qF -- "$want" "$JUDGE_INPUT" || fail "判定役への入力に '$want' が無い"
done
# 見出しの次の行に、その欄の値が入っている
after() { sed -n "/^$1:\$/{n;p;q;}" "$JUDGE_INPUT"; }
[ "$(after "LAST USER MESSAGE")" = 続けて ] || fail "最後の利用者の発言: $(after "LAST USER MESSAGE")"
[ "$(after "FINAL MESSAGE")" = "Task 1 を終えました" ] || fail "最後の応答: $(after "FINAL MESSAGE")"
grep -qF -e 注入された指示 -e 差し戻し <(sed -n '/LAST USER MESSAGE:/,/RECENT ACTIVITY:/p' "$JUDGE_INPUT") && fail "注入された指示や hook の差し戻しを利用者の発言として渡した"
ok "未完了なら計画・進捗・直近の発言・最後の応答を判定させて差し戻す"

[ -z "$(stop waiting_on_human)" ] && marked || fail "本人待ちで止めない・記録を消した"
[ ! -e "$work/state/claude/s1/blocks" ] || fail "本人待ちで連続回数を数え直さない"
ok "本人の判断待ちなら記録を残して止める"

[ -z "$(stop fail)" ] && marked || fail "判定役の失敗で差し戻した"
ok "判定役が失敗したら止める"

[ -n "$(stop continue)" ] || fail "最初の Stop で差し戻さない"
for _ in $(seq 9); do [ -n "$(stop continue)" ] || fail "上限前に止めた"; done
[ -z "$(stop continue)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "連続 10 回の後も差し戻した"
[ -n "$(stop continue)" ] || fail "上限で止めた後に数え直さない"
for _ in $(seq 5); do stop continue >/dev/null; done
printf '%s\n' '{"type":"user","message":{"content":"次の依頼"}}' '{"type":"assistant","message":{"content":[{"type":"text","text":"Task 1 を終えました"}]}}' >> "$T"
[ -n "$(stop continue)" ] && [ "$(cat "$work/state/claude/s1/blocks")" = 1 ] || fail "利用者の新しい発言で数え直さない"
ok "差し戻しは利用者の同じ発言のあいだ連続 10 回まで続け、新しい発言で数え直す"

[ -z "$(JUDGE_APPEND='{"type":"user","message":{"content":"判定中の新しい依頼"}}' stop continue)" ] || fail "判定の途中で利用者が発言したのに起こした"
# 同じ文面を送り直した場合: 前の依頼に応答した後で判定させ、判定の途中で同じ文面が 1 件増えたら起こさない
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Task 1 を終えました"}]}}' >> "$T"
before=$(grep -c '判定中の新しい依頼' "$T")
[ -z "$(JUDGE_APPEND='{"type":"user","message":{"content":"判定中の新しい依頼"}}' stop continue)" ] || fail "判定の途中で利用者が同じ文面を送り直したのに起こした"
[ -e "$JUDGE_INPUT" ] && [ "$(grep -c '判定中の新しい依頼' "$T")" -eq $((before + 1)) ] || fail "同じ文面の送り直しのテストが判定役まで届いていない"
# Stop の最後の応答より後に利用者の発言が届いていたら、その発言のターンの判定に任せる
printf '%s\n' '{"type":"user","message":{"content":"応答の後に届いた依頼"}}' >> "$T"
[ -z "$(stop continue)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "最後の応答より後の利用者の発言で、前のターンを判定した"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Task 1 を終えました"}]}}' >> "$T"
# 最後の応答がまだ会話記録に無いときは、どのターンの Stop か決められないので判定する (黙って止めない)
[ -n "$(stop continue '{last_assistant_message:"まだ記録に無い応答"}')" ] || fail "最後の応答がまだ会話記録に無いときに判定をやめた"
ok "判定の途中で利用者が新しく発言したら、古い判定では起こさない"

# 後から始まった Stop が先に世代を書いていたら、古い Stop はその世代を上書きせずに抜ける
mkdir -p "$work/state/claude/s1" && echo 1800000000000000001 > "$work/state/claude/s1/gen"
[ -z "$(KATA_COMPLETION_NOW=1800000000000000000 stop continue)" ] && [ ! -e "$JUDGE_INPUT" ] && [ "$(cat "$work/state/claude/s1/gen")" = 1800000000000000001 ] || fail "新しい Stop の世代を古い Stop が上書きした"
# 前の Stop の世代より新しければ、書いて判定する
[ -n "$(KATA_COMPLETION_NOW=1800000000000000002 stop continue)" ] && [ "$(cat "$work/state/claude/s1/gen")" = 1800000000000000002 ] || fail "前の Stop より新しい Stop が世代を書かずに抜けた"
rm -f "$work/state/claude/s1/gen"
ok "後から始まった Stop の世代を、古い Stop は上書きしない"

# 会話記録を写せなかったときも、本物の会話記録は消さない
mkdir -p "$work/badbin" && printf '#!/bin/sh\nexit 1\n' > "$work/badbin/cp" && chmod +x "$work/badbin/cp"
PATH="$work/badbin:$PATH" stop continue >/dev/null
[ -f "$T" ] || fail "会話記録を写せなかったときに、本物の会話記録を消した"
ok "会話記録を写せなくても、本物の会話記録を消さない"

{ printf '{"type":"user","message":{"content":"'; head -c 6000 /dev/zero | tr '\0' z; printf ' 末尾の指示: B を直して"}}\n'; printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Task 1 を終えました"}]}}'; } >> "$T"
stop continue >/dev/null
grep -qF "末尾の指示: B を直して" <(sed -n '/^LAST USER MESSAGE:$/,/^RECENT ACTIVITY:$/p' "$JUDGE_INPUT") || fail "長い発言の末尾の指示を判定役へ渡さない"
ok "長い発言も末尾の指示まで判定役へ渡す"

[ -z "$(stop continue '{background_tasks:[{id:"b1", type:"subagent"}]}')" ] && [ ! -e "$JUDGE_INPUT" ] || fail "Claude のバックグラウンド待ちを差し戻した"
# Codex では監視 hook の判定をここから呼び、止めるならその指示を返して計画の判定はしない。
# 同じ入力で Stop が続いても、監視が止めた回 (見に行かないまま 3 回目になって監視をやめる 4 回目を含む) は判定せず、
# 止めなくなった回で判定する
mkdir -p "$TASK_MONITOR_STATE_DIR/codex/s1/running" && : > "$TASK_MONITOR_STATE_DIR/codex/s1/running/agent-x"
mkdir -p "$work/state/codex/s1" && cp "$work/state/claude/s1/plan" "$work/state/codex/s1/plan"
for n in 1 2 3 4; do
  out=$(stop continue '{}' codex stop)
  grep -qF "監視:" <<<"$out" && [ ! -e "$JUDGE_INPUT" ] || fail "Codex で監視が止めた $n 回目の Stop で計画を判定した: $out"
done
[ -n "$(stop continue '{}' codex stop)" ] && [ -e "$JUDGE_INPUT" ] || fail "Codex で待つものが無いのに判定しない"
[ -n "$(stop continue '{}' codex)" ] && [ -e "$JUDGE_INPUT" ] || fail "Codex の旧登録で計画の完了を判定しない"
# 計画が無いセッションでは判定も監視の呼出しもしない (監視 hook が自分の Stop で判定する)
rm -f "$work/state/codex/s1/plan"
: > "$TASK_MONITOR_STATE_DIR/codex/s1/running/agent-y"
[ -z "$(stop continue '{}' codex)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "Codex の計画が無いセッションで、判定するか監視を呼んだ"
rm -rf "$TASK_MONITOR_STATE_DIR/codex/s1" && mkdir -p "$TASK_MONITOR_STATE_DIR/codex/s1/running"
cp "$work/state/claude/s1/plan" "$work/state/codex/s1/plan"
# 止められて実行されなかったコマンドの記録は、待つものに数えない。ほかの OS では監視 hook が
# 判定役へ進む前に確認を促して止めるため、Linux と macOS でだけ確かめる
case $(uname -s) in Linux | Darwin)
  printf '{"command":"cat SKILL.md"}\n' > "$TASK_MONITOR_STATE_DIR/codex/s1/running/cmd-blocked"
  [ -n "$(TASK_MONITOR_CODEX_PID=$$ stop continue '{}' codex)" ] && [ -e "$JUDGE_INPUT" ] || fail "動いていないコマンドの記録だけで判定をやめた"
  rm -rf "$TASK_MONITOR_STATE_DIR/codex/s1/running"/*
;; esac
rm -rf "$work/state/codex"
ok "バックグラウンドのタスクを待つターン終了は判定しない"

[ -z "$(stop complete)" ] && ! marked || fail "完了で記録を消さない"
ok "完了なら記録を消して止める"

bash "$ACTIVE" claude start "$work/plan.md" >/dev/null && bash "$ACTIVE" claude done >/dev/null && ! marked || fail "done で消えない"
CLAUDE_CODE_SESSION_ID= bash "$ACTIVE" claude start "$work/plan.md" 2>/dev/null && fail "セッション ID 無しで記録した"
bash "$ACTIVE" claude start "$work/none.md" 2>/dev/null && fail "無い計画ファイルを記録した"
ok "kata-active done で消え、セッション ID や計画ファイルが無ければ失敗する"

bash "$ACTIVE" claude start "$work/plan.md" >/dev/null
{ head -c 30000 /dev/zero | tr '\0' x; printf '\n## Task 9: 末尾の task\n'; } >> "$work/plan.md"
stop continue >/dev/null
grep -qF "Task 9: 末尾の task" "$JUDGE_INPUT" || fail "長い計画の末尾の task を判定役へ渡さない"
ok "長い計画も末尾の task まで判定役へ渡す"

mv "$work/plan.md" "$work/plan.gone"
[ -z "$(stop continue)" ] && [ ! -e "$JUDGE_INPUT" ] && ! marked || fail "計画ファイルが消えた記録で判定した"
ok "計画ファイルが消えていたら記録を消して止める"

# 1 つのコマンドで変更前と変更後を確かめると、後半に結果が来る。長い出力でも末尾まで判定役へ渡す
mv "$work/plan.gone" "$work/plan.md"
bash "$ACTIVE" claude start "$work/plan.md" >/dev/null
long="変更前: usage $(head -c 3000 /dev/zero | tr '\0' y) 変更後: 0. [x] a"
jq -cn --arg o "$long" '{type:"user",message:{content:[{type:"tool_result",content:$o}]}}' >> "$T"
stop continue >/dev/null
grep -qF "変更後: 0. [x] a" "$JUDGE_INPUT" || fail "長い結果の末尾を判定役へ渡さない"
ok "長いツール結果は先頭と末尾を判定役へ渡す"

# コマンド置換の中で失敗した確かめも拾う
[ ! -s "$work/failures" ] || { echo "not ok: 途中の確かめが失敗した" >&2; cat "$work/failures" >&2; exit 1; }
