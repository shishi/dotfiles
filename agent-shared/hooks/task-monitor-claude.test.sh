#!/usr/bin/env bash
# Claude Code の監視 hook を、偽の Stop 入力と判定役の代役で確かめる。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/task-monitor-claude.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/task-monitor-claude-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
export TASK_MONITOR_STATE_DIR="$work/state" TASK_MONITOR_TASKS_DIR="$work/tasks" TASK_MONITOR_MINUTE=0
export TASK_MONITOR_JUDGE="bash $work/judge.sh"
mkdir -p "$work/tasks"

fail() { echo "not ok: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
has() { grep -qF -- "$2" <<<"$1" || fail "$3: '$2' が無い: $1"; }

# 判定役の代役: 入力を judge.in に追記し、answers の先頭行の判定を返して消費する。answers が fail なら失敗する。
cat > "$work/judge.sh" <<'J'
w=$(dirname "$0")
cat >> "$w/judge.in"; echo "---" >> "$w/judge.in"
a=$(head -n 1 "$w/answers"); sed -i 1d "$w/answers"
[ "$a" = fail ] && exit 1
if [ "$a" = progressing-rc1 ]; then jq -cn '{type:"result",subtype:"success",is_error:false,structured_output:{status:"progressing",reason:"x"}}'; exit 1; fi
if [ "$a" = noreason ]; then jq -cn '{type:"result",subtype:"success",is_error:false,structured_output:{status:"progressing"}}'; exit 0; fi
jq -cn --arg s "$a" '{type:"result",subtype:"success",is_error:false,structured_output:{status:$s,reason:"代役の判定"}}'
J
answers() { printf '%s\n' "$@" > "$work/answers"; : > "$work/judge.in"; }
stop() { jq -cn --arg sid "${2:-s1}" --argjson t "$1" '{session_id:$sid, cwd:"/tmp", hook_event_name:"Stop", background_tasks:$t}'; }
SHELL_TASK='[{"id":"b1","type":"shell","status":"running","description":"依存の取得","command":"sh deps.sh"}]'
printf '{"level":"warn","payload":{"msg":"Retrying (1/inf)..."}}\n' > "$work/tasks/b1.output"

set +e
out=$(stop '[]' | bash "$HOOK" 2>&1); rc=$?
set -e
[ $rc = 0 ] && [ -z "$out" ] || fail "タスクなし: rc=$rc out=$out"
ok "実行中のタスクが無ければ何もしない"

answers progressing progressing stalled
set +e
out=$(stop "$SHELL_TASK" | bash "$HOOK" 2>&1 >/dev/null); rc=$?
set -e
[ $rc = 2 ] || fail "停滞: rc=$rc"
has "$out" "b1" "停滞の起床文"; has "$out" "stalled" "停滞の起床文"; has "$out" "TaskStop で止め" "停滞の起床文"
has "$out" "Retrying (1/inf)" "停滞の起床文"
[ "$(grep -c '^---$' "$work/judge.in")" = 3 ] || fail "判定は 3 回のはず"
has "$(cat "$work/judge.in")" "(first check)" "1 回目の判定入力"
has "$(cat "$work/judge.in")" "sh deps.sh" "判定入力のコマンド"
ok "進んでいる間は起こさず、停滞したら起こす"

answers fail
set +e
out=$(stop "$SHELL_TASK" | bash "$HOOK" 2>&1 >/dev/null); rc=$?
set -e
[ $rc = 2 ] || fail "判定役の失敗: rc=$rc"; has "$out" "unclear" "判定役の失敗"
for a in progressing-rc1 noreason; do
  answers $a
  set +e
  out=$(stop "$SHELL_TASK" | bash "$HOOK" 2>&1 >/dev/null); rc=$?
  set -e
  [ $rc = 2 ] || fail "$a: rc=$rc"; has "$out" "unclear" "$a"
done
ok "判定役が失敗したら、出力の形が正しく見えても unclear として起こす"

ln -s "$work/sub.jsonl" "$work/tasks/a1.output"
printf '%s\n' '{"type":"assistant","sessionId":"x","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"onFailure"}}]}}' > "$work/sub.jsonl"
answers stalled
set +e
stop '[{"id":"a1","type":"subagent","status":"running","description":"レビュー","agent_type":"correctness-reviewer"},{"id":"m1","type":"monitor","status":"running","description":"x"}]' | bash "$HOOK" >/dev/null 2>&1; rc=$?
set -e
[ $rc = 2 ] || fail "子エージェント: rc=$rc"
has "$(cat "$work/judge.in")" "[tool] Grep" "子エージェントの判定入力"
[ "$(grep -c '^---$' "$work/judge.in")" = 1 ] || fail "monitor のタスクは判定しない"
ok "子エージェントは会話記録の抜粋で判定し、ほかの種類は見ない"

answers progressing progressing progressing
set +e
s=$(date +%s)
out=$(stop "$SHELL_TASK" | TASK_MONITOR_MINUTE=1 TASK_MONITOR_BUDGET_MIN=15 bash "$HOOK" 2>&1 >/dev/null); rc=$?
e=$(( $(date +%s) - s ))
set -e
[ $rc = 2 ] || fail "上限: rc=$rc"; has "$out" "b1" "上限の起床文"; has "$out" "progressing" "上限の起床文"
[ "$e" -ge 9 ] && [ "$e" -le 13 ] || fail "上限: 1 回確認した直後に起こすはず (経過 ${e}s)"
ok "hook の制限時間が尽きる前に状態を添えて起こす"

answers progressing progressing progressing progressing
stop "$SHELL_TASK" s2 | TASK_MONITOR_MINUTE=1 bash "$HOOK" > "$work/first.out" 2>&1 &
first=$!
sleep 2
stop '[]' s2 | bash "$HOOK"
for _ in 1 2 3 4; do kill -0 $first 2>/dev/null || break; sleep 1; done
kill -0 $first 2>/dev/null && fail "古い監視が 1 分 (代役では 1 秒) 以内に終わらない"
set +e; wait $first; rc=$?; set -e
[ $rc = 0 ] && [ ! -s "$work/first.out" ] || fail "古い監視: rc=$rc out=$(cat "$work/first.out")"
ok "新しい Stop が来たら古い監視は黙って終わる"

# 前面のコマンドは監視できないため、既定の上限 (BASH_DEFAULT_TIMEOUT_MS) を超える待ちを指定した前面の起動は、
# バックグラウンドでの起動へ差し戻す
pre() { jq -cn "{session_id:\"s1\", hook_event_name:\"PreToolUse\", tool_name:\"Bash\", tool_input:$1} + ${2:-{\}}" | BASH_DEFAULT_TIMEOUT_MS=300000 bash "$HOOK" pre-bash; }
out=$(pre '{command:"make test", timeout:600000}')
[ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out")" = deny ] || fail "長い前面の起動を止めない: $out"
has "$out" "run_in_background" "差し戻しの理由"; has "$out" "5 分" "差し戻しの理由の上限"
[ -z "$(pre '{command:"make test", timeout:600000, run_in_background:true}')" ] || fail "バックグラウンドの起動を止めた"
[ -z "$(pre '{command:"ls", timeout:300000}')" ] && [ -z "$(pre '{command:"ls", timeout:180000}')" ] && [ -z "$(pre '{command:"ls"}')" ] ||
  fail "既定の上限以内の前面の起動を止めた"
[ -z "$(pre '{command:"make test", timeout:600000}' '{agent_id:"a1"}')" ] || fail "子エージェントの起動を止めた"
[ -n "$(jq -cn '{tool_input:{command:"ls", timeout:180000}}' | env -u BASH_DEFAULT_TIMEOUT_MS bash "$HOOK" pre-bash)" ] ||
  fail "BASH_DEFAULT_TIMEOUT_MS が無いとき 2 分を上限にしない"
ok "既定の上限を超える待ちを指定した前面のコマンドは、バックグラウンドで起動し直させる (子エージェントは除く)"
