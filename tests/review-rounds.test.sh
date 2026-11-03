#!/usr/bin/env bash
# review-rounds.sh: 新しい変更のレビューは必ず通し、採用した指摘を直しては確かめる周が上限まで続いたときだけ止めるか。
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/agent-shared/hooks/review-rounds.sh"
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/review-rounds-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
export REVIEW_ROUNDS_STATE="$T/state"
W="$T/work"
git init -q -b master "$W" && git -C "$W" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m base

ok() { echo "ok: $1"; }
ng() { echo "not ok: $1"; FAIL=$((FAIL + 1)); }
claude_pre() { jq -nc --arg cwd "$W" --arg a "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Agent",tool_input:{subagent_type:$a,prompt:"x"}}' | bash "$HOOK" pre; }
codex_pre() { jq -nc --arg cwd "$W" --arg a "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"collaborationspawn_agent",tool_input:{task_name:"r",agent_type:$a,message:"x"}}' | bash "$HOOK" pre; }
stop() { jq -nc --arg cwd "$W" --arg a "$1" --arg m "$2" '{hook_event_name:"SubagentStop",cwd:$cwd,agent_type:$a,last_assistant_message:$m}' | bash "$HOOK" stop; }
adopt() { (cd "$W" && bash "$HOOK" adopt "$1" "$2"); }
counts() { printf '[correctness-1] should a.py:1\n...\n{"review_counts":{"blocker":%s,"should":%s,"note":%s}}' "$1" "$2" "$3"; }
denied() { jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 <<<"$1"; }
reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$1"; }
edit() { echo "$1" > "$W/f.txt"; }
commit() { git -C "$W" add -A && git -C "$W" -c user.email=t@example.invalid -c user.name=t commit -q -m "$1"; }

out=$(claude_pre Explore); [ -z "$out" ] && ok "other agents are not counted" || ng "other agents are not counted: $out"

# 1 周目は必ず通す。同じ内容への並んだ起動は同じ周。
out=$(claude_pre correctness-reviewer); denied "$out" && ng "round 1 runs" || ok "round 1 runs"
out=$(claude_pre spec-scope-reviewer); denied "$out" && ng "parallel lanes on the same tree are one round" || ok "parallel lanes on the same tree are one round"
stop correctness-reviewer "$(counts 2 3 1)"

# 採用した指摘があれば、その確認の周を通す
adopt 1 2
edit a
out=$(claude_pre correctness-reviewer); denied "$out" && ng "a round runs to confirm adopted findings" || ok "a round runs to confirm adopted findings"
stop correctness-reviewer "$(counts 1 4 2)"

# 採用の無い周で区切りが付いた後の新しい変更 (別のゲート、追加の依頼) は、新しい区切りの 1 周目として通す
edit b
out=$(claude_pre correctness-reviewer)
denied "$out" && ng "a new change after a round with no adopted findings is reviewed: $out" || ok "a new change after a round with no adopted findings is reviewed"

# delta は、直前の周の内容から今の作業ツリーまでの差分 (新しいファイルを含む) を出す
echo new > "$W/new.txt"
delta=$(cd "$W" && bash "$HOOK" delta)
case "$delta" in *"new.txt"*) ok "delta shows changes since the last round, including new files";; *) ng "delta shows changes since the last round, including new files: $delta";; esac
case "$delta" in *"+b"*) ng "delta excludes changes already reviewed: $delta";; *) ok "delta excludes changes already reviewed";; esac
rm -f "$W/new.txt"

# 上限の周に達したら、採用した指摘があっても止めて推移を示す
commit work1
git -C "$W" checkout -q -b topic
for x in 1 2 3 4 5; do
  edit "t$x"
  out=$(claude_pre correctness-reviewer)
  denied "$out" && { ng "rounds with adopted findings run up to the limit (round $x): $out"; break; }
  stop correctness-reviewer "$(counts 0 1 0)"
  adopt 0 1
done
edit t6
out=$(claude_pre correctness-reviewer)
if denied "$out"; then ok "the limit stops further rounds"; else ng "the limit stops further rounds: $out"; fi
case "$(reason "$out")" in *"5 周目"*"採用"*continue*) ok "the limit shows the trend and how to continue";; *) ng "the limit shows the trend and how to continue: $(reason "$out")";; esac
# 利用者が続けると判断したら、continue の記録で新しい区切りを始める
(cd "$W" && bash "$HOOK" continue >/dev/null)
out=$(claude_pre correctness-reviewer); denied "$out" && ng "continue after the user's decision starts a new cycle: $out" || ok "continue after the user's decision starts a new cycle"
stop correctness-reviewer "$(counts 0 1 0)"
adopt 0 1

# branch 上の commit では数え直さないが、作業を既定ブランチへ取り込めば新しい作業として数え直す
before=$(adopt 0 1)
commit t
after=$(adopt 0 1)
[ -n "$before" ] && [ "${before%%周目*}" = "${after%%周目*}" ] && ok "commits on a branch do not reset the rounds" || ng "commits on a branch do not reset the rounds: $before / $after"
git -C "$W" checkout -q master && git -C "$W" merge -q --ff-only topic && git -C "$W" checkout -q topic
edit next
out=$(claude_pre correctness-reviewer); denied "$out" && ng "a new task after merging into the local default branch starts over: $out" || ok "a new task after merging into the local default branch starts over"
stop correctness-reviewer "$(counts 0 1 0)"
adopt 0 1

# remote の既定ブランチが古くても、ローカルの既定ブランチで作業を区切る
git -C "$W" update-ref refs/remotes/origin/master "$(git -C "$W" rev-parse master~1)"
git -C "$W" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
edit next2
out=$(claude_pre correctness-reviewer)
num=$(adopt 0 1); num=${num#review-rounds: }
[ "${num%% 周目*}" = 2 ] && ok "a stale remote default branch does not merge tasks together" || ng "a stale remote default branch does not merge tasks together: $num"

# 他方の CLI のレビューも周として数え、採用の記録で次の周を通す
stop correctness-reviewer "$(counts 0 0 0)"
counts 1 0 0 > "$T/cross.txt"
(cd "$W" && bash "$HOOK" record "$T/cross.txt")
adopt 1 0
edit g
out=$(codex_pre correctness-reviewer); denied "$out" && ng "codex rounds follow the same rule: $out" || ok "codex rounds follow the same rule"

# 採用の記録が無い周は reviewer が挙げた件数で判断する。記録し忘れても上限は効く。
V="$T/v"
git init -q -b master "$V" && git -C "$V" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m base
git -C "$V" checkout -q -b topic
vpre() { jq -nc --arg cwd "$V" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Agent",tool_input:{subagent_type:"correctness-reviewer",prompt:"x"}}' | bash "$HOOK" pre; }
vstop() { jq -nc --arg cwd "$V" --arg m "$1" '{hook_event_name:"SubagentStop",cwd:$cwd,agent_type:"correctness-reviewer",last_assistant_message:$m}' | bash "$HOOK" stop; }
for x in 1 2 3 4 5; do echo "v$x" > "$V/f.txt"; vpre >/dev/null; vstop "$(counts 0 1 0)"; done
echo v6 > "$V/f.txt"
out=$(vpre); denied "$out" && ok "raised findings without an adopt record count toward the limit" || ng "raised findings without an adopt record count toward the limit: $out"
(cd "$V" && bash "$HOOK" adopt 0 0 >/dev/null)
out=$(vpre); denied "$out" && ng "an explicit adopt 0 0 ends the cycle: $out" || ok "an explicit adopt 0 0 ends the cycle"
E="$T/empty"; git init -q -b master "$E" && git -C "$E" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m base
msg=$(cd "$E" && bash "$HOOK" adopt 0 1 2>&1); case "$msg" in *"記録が無い"*) ok "adopt without any round says so";; *) ng "adopt without any round says so: $msg";; esac

# 引数の足りない adopt は記録せずに使い方を示す
(cd "$W" && bash "$HOOK" adopt 1 >/dev/null 2>&1); [ $? = 2 ] && ok "adopt needs both counts" || ng "adopt needs both counts"

# 既定ブランチの上で直接作業しても、commit のたびに数え直さず、delta も前の周から出せる
M="$T/main"
git init -q -b master "$M" && git -C "$M" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m base
git -C "$M" update-ref refs/remotes/origin/master "$(git -C "$M" rev-parse HEAD)"
git -C "$M" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
mpre() { jq -nc --arg cwd "$M" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Agent",tool_input:{subagent_type:"correctness-reviewer",prompt:"x"}}' | bash "$HOOK" pre; }
echo m1 > "$M/f.txt"; mpre >/dev/null
(cd "$M" && bash "$HOOK" adopt 0 1 >/dev/null)
git -C "$M" add -A && git -C "$M" -c user.email=t@example.invalid -c user.name=t commit -q -m m1
echo m2 > "$M/f.txt"
delta=$(cd "$M" && bash "$HOOK" delta 2>&1)
case "$delta" in *"+m2"*) ok "on the default branch, delta spans commits made between rounds";; *) ng "on the default branch, delta spans commits made between rounds: $delta";; esac

# 記録が壊れていても起動は止めない
stop correctness-reviewer "$(counts 0 1 0)"
adopt 0 1
git -C "$W" checkout -q -b broken
broken_log=$(ls -t "$REVIEW_ROUNDS_STATE"/*.jsonl | head -n 1)
adopted_before=$(jq -cR 'fromjson? // empty' "$broken_log" | jq -s '[.[] | select(.e == "a")] | length' | tr -d '\r')
for f in "$REVIEW_ROUNDS_STATE"/*.jsonl; do printf '{"e":"d","tre' >>"$f"; done
adopt 0 1 >/dev/null
edit z
out=$(claude_pre correctness-reviewer); denied "$out" && ng "a broken log does not stop reviews" || ok "a broken log does not stop reviews"
adopted_after=$(jq -cR 'fromjson? // empty' "$broken_log" | jq -s '[.[] | select(.e == "a")] | length' | tr -d '\r')
[ "$adopted_after" = $((adopted_before + 1)) ] && ok "a record after a broken line is kept" || ng "a record after a broken line is kept ($adopted_before -> $adopted_after)"
REVIEW_ROUNDS_LIMIT=x claude_pre correctness-reviewer >/dev/null 2>&1; edit zz
out=$(REVIEW_ROUNDS_LIMIT=x claude_pre correctness-reviewer 2>/dev/null); denied "$out" && ng "a failed judgement does not stop reviews: $out" || ok "a failed judgement does not stop reviews"

[ "$FAIL" = 0 ]
