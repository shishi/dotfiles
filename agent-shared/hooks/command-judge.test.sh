#!/usr/bin/env bash
# PATH 上の codex を偽物に差し替えて、command-judge.sh の判定結果の扱いと登録を確認する。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/command-judge.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/command-judge-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
py_bin=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "" >/dev/null 2>&1; then py_bin=$(command -v "$candidate"); break; fi
done
[ -n "$py_bin" ] || { echo "not ok: no runnable python" >&2; exit 1; }

# 偽の判定役: 受け取った入力を保存し、STUB_OUTPUT を出して STUB_EXIT で終わる。
# 判定役が動くかを確かめる問いには STUB_PROBE を出して STUB_PROBE_EXIT で終わる。
mkdir -p "$work/bin"
cat >"$work/bin/fake_codex.py" <<'PY'
import os, sys, time
work = os.environ["STUB_WORK"]
data = sys.stdin.buffer.read()
if b"Reply with exactly: OK" in data:
    print(os.environ.get("STUB_PROBE", "OK"))
    sys.exit(int(os.environ.get("STUB_PROBE_EXIT", "0")))
with open(os.path.join(work, "judge-input"), "wb") as f:
    f.write(data)
with open(os.path.join(work, "calls"), "a") as f:
    f.write("x\n")
if os.environ.get("STUB_AUTH_FAIL"):   # ログインが無効な codex のように 401 を出し続ける
    for _ in range(5):
        print("2026-11-02T03:25:44.557043Z ERROR codex_api::endpoint::responses_websocket: failed to connect "
              "to websocket: HTTP error: 401 Unauthorized, url: wss://api.openai.com/v1/responses",
              file=sys.stderr, flush=True)
time.sleep(float(os.environ.get("STUB_SLEEP", "0")))
print(os.environ.get("STUB_OUTPUT", ""))
sys.exit(int(os.environ.get("STUB_EXIT", "0")))
PY
printf '#!/bin/sh\nexec "%s" -I "%s/bin/fake_codex.py" "$@"\n' "$py_bin" "$work" >"$work/bin/codex"
chmod +x "$work/bin/codex"
# Windows の python は拡張子の無いスクリプトを実行ファイルとして見つけないため、.cmd も置く。
printf '@"%s" -I "%%~dp0fake_codex.py" %%*\r\n' "$(cygpath -w "$py_bin" 2>/dev/null || echo "$py_bin")" >"$work/bin/codex.cmd"
export PATH="$work/bin:$PATH"
export STUB_WORK="$work" COMMAND_JUDGE_STATE_DIR="$work/state" STUB_OUTPUT STUB_EXIT=0 STUB_PROBE=OK STUB_PROBE_EXIT=0
unset AGENT_DELEGATED_SESSION COMMAND_JUDGE_ACTIVE

pre_tool_use() {
  jq -n --argjson cmd "$1" '{session_id:"s1",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd,description:"状態を確認する"}}'
}
record() { jq -n --arg p "$1" '{session_id:"s1",prompt:$p}' | bash "$HOOK" --record-prompt "${@:2}"; }
calls() { if [ -f "$work/calls" ]; then wc -l <"$work/calls" | tr -d ' '; else echo 0; fi; }
decision() { [ -n "$1" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$1"; }
reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // .systemMessage // ""' <<<"$1"; }
fail() { echo "not ok: $1" >&2; exit 1; }
token=$("$py_bin" -I -c "import secrets,string;print('ghp_'+''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(36)))")
SAFE='{"danger":false,"user_requested":false,"body_from_file":false,"external":false,"reason":""}'

STUB_OUTPUT='{"danger":true,"user_requested":false,"body_from_file":false,"external":false,"reason":"マシンを再起動する"}'
out=$(pre_tool_use '"sudo reboot"' | bash "$HOOK")
[ "$(decision "$out")" = deny ] || fail "danger is denied: $out"
reason "$out" | grep -q 'マシンを再起動する' || fail "deny reason carries the judge reason"
echo 'ok: a dangerous command is denied with the judge reason'

rm -f "$work/calls"
STUB_OUTPUT="判定します
$SAFE"
out=$(pre_tool_use '"git status"' | bash "$HOOK")
[ -z "$out" ] || fail "safe command is allowed silently: $out"
grep -q 'git status' "$work/judge-input" || fail "judge input contains the command"
grep -q '状態を確認する' "$work/judge-input" || fail "judge input contains the stated purpose"
grep -q 'エージェント: claude' "$work/judge-input" || fail "judge input names the shell and the agent"
echo 'ok: a safe command is allowed silently'

STUB_OUTPUT='{"danger":true,"user_requested":false,"body_from_file":false,"external":false,"reason":"cache must not be bypassed"}'
out=$(pre_tool_use '"git status"' | bash "$HOOK")
[ -z "$out" ] && [ "$(calls)" = 1 ] || fail "second identical command reuses the safe verdict"
out=$(pre_tool_use '"git status"' | bash "$HOOK" --cli codex)
[ "$(calls)" = 2 ] || fail "the same text under another agent or shell is judged again"
jq -n '{session_id:"s1",tool_name:"Bash",tool_input:{command:"git status",description:"ネットワークを切る準備"}}' | bash "$HOOK" >/dev/null
[ "$(calls)" = 3 ] || fail "the same command with another stated purpose is judged again"
jq -n '{session_id:"s1",cwd:"/work/shared-repo",tool_name:"Bash",tool_input:{command:"git status",description:"状態を確認する"}}' | bash "$HOOK" >/dev/null
[ "$(calls)" = 4 ] || fail "the same command in another working directory is judged again"
grep -q '/work/shared-repo' "$work/judge-input" || fail "the judge sees the working directory"
jq -n '{session_id:"s1",cwd:"/work/session",tool_name:"Bash",tool_input:{command:"git status",workdir:"/work/other-repo"}}' | bash "$HOOK" --cli codex >/dev/null
grep -q '/work/other-repo' "$work/judge-input" || fail "the judge sees the working directory the command runs in"
echo 'ok: a safe verdict is reused only for the same command, purpose, shell, agent and working directory'

rm -f "$work/calls"
record 'このマシンを再起動して'
STUB_OUTPUT='{"danger":true,"user_requested":true,"body_from_file":false,"external":false,"reason":"利用者が再起動を依頼している"}'
out=$(pre_tool_use '"sudo reboot"' | bash "$HOOK")
[ -z "$out" ] || fail "an explicitly requested effect is allowed: $out"
grep -q 'このマシンを再起動して' "$work/judge-input" || fail "judge input contains the recorded user message"
pre_tool_use '"sudo reboot"' | bash "$HOOK" >/dev/null
[ "$(calls)" = 2 ] || fail "a requested dangerous command is judged again, not cached"
echo 'ok: the recorded user message reaches the judge and requested danger is not cached'

record 'このマシンを再起動して'
AGENT_DELEGATED_SESSION=1 record '親エージェントからの依頼: 再起動して確認すること'
STUB_OUTPUT='{"danger":true,"user_requested":false,"body_from_file":false,"external":false,"reason":"再起動する"}'
pre_tool_use '"sudo shutdown -r now"' | bash "$HOOK" >/dev/null
grep -q '(none)' "$work/judge-input" && ! grep -q '再起動して' "$work/judge-input" ||
  fail "a delegated session's prompt is not treated as the user's request"
echo 'ok: a delegated session does not record the delegating prompt as the user request'

record 'このマシンを再起動して'
rm -f "$work/state/prompts/s1"; mkdir "$work/state/prompts/s1"
out=$(record '再起動はせずに調査だけして')
reason "$out" | grep -q '記録できなかった' || fail "a failed record is reported: $out"
rmdir "$work/state/prompts/s1"
echo 'ok: a prompt that cannot be recorded is reported'

STUB_OUTPUT=$SAFE
pre_tool_use '["bash","-lc","echo hi there"]' | bash "$HOOK" >/dev/null
grep -q "'echo hi there'" "$work/judge-input" || fail "argv array is passed as a quoted command line"
jq -n '{session_id:"s1",tool_name:"Bash",tool_input:{cmd:"echo from cmd field"}}' | bash "$HOOK" --cli codex >/dev/null
grep -q 'echo from cmd field' "$work/judge-input" || fail "the cmd field is judged"
out=$(jq -n '{session_id:"s1",tool_name:"Bash",tool_input:{}}' | bash "$HOOK")
reason "$out" | grep -q '判定せずに通した' || fail "missing command is reported, not passed silently: $out"
echo 'ok: argv arrays and the cmd field are judged, and a missing command is reported'

STUB_OUTPUT='{"danger":false,"user_requested":false,"body_from_file":true,"external":true,"reason":"gh pr create が本文をファイルから読む"}'
record 'PR を作って'
out=$(pre_tool_use '"gh pr create --body-file /tmp/body.md"' | bash "$HOOK")
[ "$(decision "$out")" = deny ] || fail "a body read from a file path is denied: $out"
reason "$out" | grep -q '標準入力' || fail "the deny reason tells how to pass the body"
echo 'ok: posting a body from a file path is denied with the fix'

rm -f "$work/calls"
record 'テストを直して'
STUB_OUTPUT='{"danger":false,"user_requested":false,"body_from_file":false,"external":true,"reason":"commit を共有の remote へ送る"}'
out=$(pre_tool_use '"git push origin HEAD"' | bash "$HOOK")
[ "$(decision "$out")" = ask ] && reason "$out" | grep -q 'commit を共有の remote へ送る' ||
  fail "Claude asks the user before an unauthorized external effect: $out"
out=$(pre_tool_use '"git push origin HEAD"' | bash "$HOOK" --cli codex)
[ "$(decision "$out")" = deny ] && reason "$out" | grep -q '許可' ||
  fail "Codex denies an unauthorized external effect and tells the agent to get permission: $out"
[ "$(calls)" = 2 ] || fail "an external effect is not cached as safe"
record 'push して'
STUB_OUTPUT='{"danger":false,"user_requested":true,"body_from_file":false,"external":true,"reason":"commit を共有の remote へ送る"}'
for agent in claude codex; do
  out=$(pre_tool_use '"git push origin HEAD"' | bash "$HOOK" --cli "$agent")
  [ -z "$out" ] || fail "$agent allows an external effect the user permitted: $out"
done
[ "$(calls)" = 4 ] || fail "a permitted external effect is judged again, not cached"
echo 'ok: an external effect needs the user permission, asked in Claude and denied in Codex'

record '修正して push までして'
record '進捗は？'
STUB_OUTPUT=$SAFE
pre_tool_use '"git push origin HEAD"' | bash "$HOOK" >/dev/null
grep -q '修正して push までして' "$work/judge-input" && grep -q '進捗は？' "$work/judge-input" ||
  fail "the judge sees a permission given in an earlier message of the session"
[ "$(grep -n '修正して push までして' "$work/judge-input" | cut -d: -f1)" -lt "$(grep -n '進捗は？' "$work/judge-input" | cut -d: -f1)" ] ||
  fail "the user's messages reach the judge oldest first"
for n in $(seq 1 6); do record "進捗は？ $n"; done
pre_tool_use '"git push origin main"' | bash "$HOOK" >/dev/null
grep -q '修正して push までして' "$work/judge-input" || fail "a permission survives several progress checks"
for n in $(seq 7 20); do record "進捗は？ $n"; done
pre_tool_use '"git push origin dev"' | bash "$HOOK" >/dev/null
! grep -q '修正して push までして' "$work/judge-input" && grep -q '進捗は？ 20' "$work/judge-input" ||
  fail "only the recent user messages reach the judge"
echo 'ok: the judge sees the recent user messages, oldest first'

rm -f "$work/state/prompts/s1"
jq -nc '{type:"response_item",payload:{type:"message",role:"assistant",phase:"final_answer",content:[{type:"output_text",text:"DNS サーバーの設定を反映していい？"}]}}' >"$work/transcript.jsonl"
jq -nc '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"いい"}]}}' >>"$work/transcript.jsonl"
jq -n --arg t "$work/transcript.jsonl" '{session_id:"s1",prompt:"いい",transcript_path:$t}' | bash "$HOOK" --cli codex --record-prompt
record '進めて' --cli codex
STUB_OUTPUT=$SAFE
pre_tool_use '"ssh dns-host apply"' | bash "$HOOK" --cli codex >/dev/null
grep -q 'DNS サーバーの設定を反映していい？' "$work/judge-input" && grep -q 'いい' "$work/judge-input" ||
  fail 'the preceding assistant question and the user approval must reach the judge together'
echo 'ok: the preceding assistant question accompanies the user approval'

rm -f "$work/state/prompts/s1"
jq -nc '{type:"response_item",payload:{type:"message",role:"assistant",phase:"final_answer",content:[{type:"output_text",text:"古い提案"}]}}' >"$work/transcript.jsonl"
jq -nc '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"その話は中止"}]}}' >>"$work/transcript.jsonl"
jq -nc '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"いい"}]}}' >>"$work/transcript.jsonl"
jq -n --arg t "$work/transcript.jsonl" '{session_id:"s1",prompt:"いい",transcript_path:$t}' | bash "$HOOK" --cli codex --record-prompt
pre_tool_use '"ssh another-host apply"' | bash "$HOOK" --cli codex >/dev/null
! grep -q '古い提案' "$work/judge-input" || fail 'an intervening user message must not attach an old proposal'
echo 'ok: an intervening user message prevents stale proposal association'

rm -f "$work/state/prompts/s1"
record 'origin main への push を許可する' --cli codex
long_question=$(printf '%04001d' 0)
jq -nc --arg q "$long_question" '{type:"response_item",payload:{type:"message",role:"assistant",phase:"final_answer",content:[{type:"output_text",text:$q}]}}' >"$work/transcript.jsonl"
jq -n --arg t "$work/transcript.jsonl" '{session_id:"s1",prompt:"いい",transcript_path:$t}' | bash "$HOOK" --cli codex --record-prompt
rm -f "$work/state/safe/"*
pre_tool_use '"git push origin main"' | bash "$HOOK" --cli codex >/dev/null
! grep -q 'origin main への push を許可する' "$work/judge-input" || fail 'an omitted assistant response must not leave earlier permissions in effect'
echo 'ok: omitted oversized context clears earlier permissions'

record 'push して'
record "push はしないで $token" >/dev/null
pre_tool_use '"git push origin topic"' | bash "$HOOK" >/dev/null
! grep -q 'push して' "$work/judge-input" || fail "an omitted message drops the earlier permissions it may withdraw"
echo 'ok: an omitted message drops the earlier messages'

now=$(date +%s)
{ jq -nc --argjson at $((now - 50000)) '{at: $at, text: "半日以上前の push の許可"}'
  jq -nc --argjson at $((now - 50000)) --arg t "$(printf 'A%.0s' $(seq 3000))中央$(printf 'B%.0s' $(seq 3000))" '{at: $at, text: $t}'
  jq -nc --argjson at $((now - 120)) '{at: $at, text: "省略した長文の前の push の許可"}'
  jq -nc --argjson at $((now - 60)) --arg t "$(printf 'C%.0s' $(seq 3000))中央$(printf 'D%.0s' $(seq 3000))" '{at: $at, text: $t}'
  jq -nc --argjson at $((now - 50000)) --arg t "$(printf 'E%.0s' $(seq 3000))最新の中央" '{at: $at, text: $t}'
} >"$work/state/prompts/s1"
pre_tool_use '"git push origin old"' | bash "$HOOK" >/dev/null
! grep -q '半日以上前' "$work/judge-input" && ! grep -q 'CCCC' "$work/judge-input" && ! grep -q '省略した長文の前' "$work/judge-input" &&
  grep -q '最新の中央' "$work/judge-input" ||
  fail "old earlier messages, a long earlier message and those before it are dropped, and the latest is kept whole"
echo 'ok: earlier messages older than the window or a long earlier message and those before it are dropped, but the latest is kept whole'

rm -f "$work/calls"
STUB_EXIT=1 STUB_OUTPUT='boom' STUB_PROBE='' STUB_PROBE_EXIT=1
for agent in claude codex; do
  out=$(pre_tool_use '"make build"' | bash "$HOOK" --cli "$agent")
  [ "$(decision "$out")" = none ] && reason "$out" | grep -q '簡単な問いにも答えない' ||
    fail "$agent warns and lets the command run when the judge does not answer at all: $out"
done
calls_before=$(calls)
out=$(pre_tool_use '"make check"' | bash "$HOOK" --cli codex)
[ "$(decision "$out")" = none ] && [ "$(calls)" = "$calls_before" ] ||
  fail "right after the judge failed to answer, commands are passed without waiting for the judge again: $out"
rm -f "$work/state/judge-down-"*
STUB_PROBE='OK' STUB_PROBE_EXIT=1
out=$(pre_tool_use '"make build"' | bash "$HOOK" --cli codex)
[ "$(decision "$out")" = none ] || fail "a probe that prints OK but fails is not taken as a working judge: $out"
rm -f "$work/state/judge-down-"*
STUB_PROBE=OK STUB_PROBE_EXIT=0
out=$(pre_tool_use '"make build"' | bash "$HOOK")
[ "$(decision "$out")" = ask ] && reason "$out" | grep -q '終了コード 1' || fail "Claude asks when only this judgement failed: $out"
for command in '"make build"' '"make build"' '"make  build 2>&1"' '"make lint"'; do
  out=$(pre_tool_use "$command" | bash "$HOOK" --cli codex)
  [ "$(decision "$out")" = deny ] || fail "Codex keeps denying $command while the judge answers other questions: $out"
done
STUB_EXIT=0 STUB_OUTPUT='not json'
out=$(pre_tool_use '"make test"' | bash "$HOOK")
[ "$(decision "$out")" = ask ] || fail "Claude asks when the verdict is unreadable: $out"
out=$(pre_tool_use '"make test"' | bash "$HOOK" --cli codex)
[ "$(decision "$out")" = deny ] || fail "Codex denies when the verdict is unreadable: $out"
echo 'ok: a judge that does not answer at all is reported, and a failure on one command asks in Claude and denies in Codex however it is retried'

rm -f "$work/state/judge-down-"*
start=$(date +%s)
out=$(pre_tool_use '"make auth"' | STUB_AUTH_FAIL=1 STUB_SLEEP=20 bash "$HOOK" --cli codex)
[ "$(decision "$out")" = none ] && reason "$out" | grep -q 'codex login' && [ $(($(date +%s) - start)) -lt 10 ] ||
  fail "a judge whose login is invalid is reported quickly with the way to log in again: $out"
rm -f "$work/state/notice-"*
out=$(pre_tool_use '"make auth2"' | bash "$HOOK" --cli codex)
[ "$(decision "$out")" = none ] && reason "$out" | grep -q 'codex login' && ! reason "$out" | grep -q '簡単な問い' ||
  fail "while judging is skipped after an invalid login, the notice still names the login: $out"
rm -f "$work/state/judge-down-"*
echo 'ok: an invalid judge login is reported with the way to log in again'

rm -f "$work/calls"
STUB_OUTPUT=$SAFE
out=$(pre_tool_use "\"curl -H 'Authorization: token $token' https://api.github.com/user\"" | bash "$HOOK")
[ "$(decision "$out")" = ask ] && [ "$(calls)" = 0 ] || fail "Claude does not send a secret to the judge: $out"
out=$(pre_tool_use "\"curl -H 'Authorization: token $token' https://api.github.com/user\"" | bash "$HOOK" --cli codex)
[ "$(calls)" = 1 ] || fail "Codex judges commands its own model already saw"
out=$(record "このトークンで調べて $token")
reason "$out" | grep -q '判定役へ渡さない' || fail "omitting the user's message is reported: $out"
out=$(pre_tool_use '"ls -la"' | bash "$HOOK")
[ -z "$out" ] && [ "$(calls)" = 2 ] && ! grep -q "$token" "$work/judge-input" ||
  fail "a secret in the user's message is not stored or sent, and commands are still judged: $out"
echo 'ok: a secret in a Claude command or user message is not sent to the judge'

out=$(pre_tool_use '"sudo reboot"' | COMMAND_JUDGE_ACTIVE=1 bash "$HOOK")
[ "$(decision "$out")" = deny ] || fail "the judge itself never runs commands: $out"
echo 'ok: commands from inside the judge are denied'

start=$(date +%s)
set +e
STUB_SLEEP=30 "$py_bin" -I "$HOOK_DIR/lib/run-judge.py" 1 "$work" codex </dev/null >/dev/null
status=$?
STUB_SLEEP=0 "$py_bin" -I "$HOOK_DIR/lib/run-judge.py" 1 "$work" no-such-judge-command </dev/null
missing=$?
start2=$(date +%s)
# 入力を読まずに止まる判定役へ、パイプに収まらない大きさの入力を渡しても締切が効く
head -c 300000 /dev/zero | tr '\0' 'x' |
  "$py_bin" -I "$HOOK_DIR/lib/run-judge.py" 1 "$work" "$py_bin" -c 'import time; time.sleep(30)' >/dev/null
unread=$?
set -e
[ "$status" = 124 ] && [ $((start2 - start)) -lt 10 ] || fail "run-judge stops the judge's process tree at the deadline (status $status)"
[ "$unread" = 124 ] && [ $(($(date +%s) - start2)) -lt 10 ] || fail "run-judge keeps its deadline when the judge never reads its input (status $unread)"
[ "$missing" = 127 ] || fail "run-judge reports a missing judge as 127 (status $missing)"
echo 'ok: run-judge stops a slow judge and reports a missing one'

for config in claude/settings.json codex/hooks.json; do
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | test("command-judge\\.sh"))] | length == 1' "$HOOK_DIR/../../$config" >/dev/null || fail "$config registers the judge for Bash"
  jq -e '[.hooks.UserPromptSubmit[].hooks[] | select(.command | test("command-judge\\.sh .*--record-prompt"))] | length == 1' "$HOOK_DIR/../../$config" >/dev/null || fail "$config records the prompt"
  jq -e '[.. | strings | select(test("gh-body-file-guard"))] | length == 0' "$HOOK_DIR/../../$config" >/dev/null || fail "$config no longer runs the pattern-based gh guard"
  echo "ok: $config registers the judge and the prompt recorder"
done
