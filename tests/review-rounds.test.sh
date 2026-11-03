#!/usr/bin/env bash
# review-rounds.sh: 同じ基準 commit の上でレビューの周回が収束しないとき、新しい周の起動を止めるか。
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/agent-shared/hooks/review-rounds.sh"
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/review-rounds-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
export REVIEW_ROUNDS_STATE="$T/state"
W="$T/work"
git init -q "$W" && git -C "$W" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m base

ok() { echo "ok: $1"; }
ng() { echo "not ok: $1"; FAIL=$((FAIL + 1)); }
claude_pre() { jq -nc --arg cwd "$W" --arg a "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Agent",tool_input:{subagent_type:$a,prompt:"x"}}' | bash "$HOOK" pre; }
codex_pre() { jq -nc --arg cwd "$W" --arg a "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"collaborationspawn_agent",tool_input:{task_name:"r",agent_type:$a,message:"x"}}' | bash "$HOOK" pre; }
stop() { jq -nc --arg cwd "$W" --arg a "$1" --arg m "$2" '{hook_event_name:"SubagentStop",cwd:$cwd,agent_type:$a,last_assistant_message:$m}' | bash "$HOOK" stop; }
counts() { printf '[correctness-1] should a.py:1\n...\n{"review_counts":{"blocker":%s,"should":%s,"note":%s}}' "$1" "$2" "$3"; }
denied() { jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 <<<"$1"; }
edit() { echo "$1" > "$W/f.txt"; }

out=$(claude_pre Explore); [ -z "$out" ] && ok "other agents are not counted" || ng "other agents are not counted: $out"

out=$(claude_pre correctness-reviewer); denied "$out" && ng "round 1 runs" || ok "round 1 runs"
out=$(claude_pre spec-scope-reviewer); denied "$out" && ng "parallel lanes on the same tree are one round" || ok "parallel lanes on the same tree are one round"
stop correctness-reviewer "$(counts 2 3 1)"
edit a
out=$(claude_pre correctness-reviewer); denied "$out" && ng "round 2 runs" || ok "round 2 runs"
stop correctness-reviewer "$(counts 0 4 2)"
stop spec-scope-reviewer "$(counts 0 1 3)"
edit b
out=$(claude_pre correctness-reviewer)
if denied "$out"; then ok "round 3 stops when round 2 had no blocker"; else ng "round 3 stops when round 2 had no blocker: $out"; fi
reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$out")
case "$reason" in *"blocker 2"*"should 3"*"blocker 0"*"should 5"*"note 5"*) ok "the stop shows the trend of each round";; *) ng "the stop shows the trend of each round: $reason";; esac
out=$(claude_pre spec-scope-reviewer); denied "$out" && ok "a stopped round stays stopped" || ng "a stopped round stays stopped"

git -C "$W" add -A && git -C "$W" -c user.email=t@example.invalid -c user.name=t commit -q -m next
out=$(claude_pre correctness-reviewer); denied "$out" && ng "a new base commit starts over" || ok "a new base commit starts over"
stop correctness-reviewer "$(counts 0 0 0)"
edit c
out=$(codex_pre correctness-reviewer); denied "$out" && ng "codex round 2 runs" || ok "codex round 2 runs"
stop correctness-reviewer "$(counts 1 0 0)"
edit d
out=$(codex_pre correctness-reviewer); denied "$out" && ng "a blocker in the last round lets round 3 run" || ok "a blocker in the last round lets round 3 run"
edit e
out=$(codex_pre correctness-reviewer); denied "$out" && ok "a round with no recorded counts is treated as blocker-free" || ng "a round with no recorded counts is treated as blocker-free: $out"

# 他方の CLI のレビューの blocker も数える (record)
counts 1 0 0 > "$T/cross.txt"
(cd "$W" && bash "$HOOK" record "$T/cross.txt")
edit g
out=$(claude_pre correctness-reviewer); denied "$out" && ng "a blocker from the other CLI lets the next round run" || ok "a blocker from the other CLI lets the next round run"

# branch 上の commit では数え直さない
git -C "$W" checkout -q -b topic
for x in 1 2; do edit "t$x"; claude_pre correctness-reviewer >/dev/null; stop correctness-reviewer "$(counts 0 1 0)"
  git -C "$W" add -A && git -C "$W" -c user.email=t@example.invalid -c user.name=t commit -q -m "t$x"; done
edit t3
out=$(claude_pre correctness-reviewer); denied "$out" && ok "commits on a branch do not reset the rounds" || ng "commits on a branch do not reset the rounds: $out"

# 記録が壊れていても起動は止めない
git -C "$W" checkout -q -b broken
for f in "$REVIEW_ROUNDS_STATE"/*.jsonl; do printf '{"e":"d","tre' >>"$f"; done
edit z
out=$(claude_pre correctness-reviewer); denied "$out" && ng "a broken log does not stop reviews" || ok "a broken log does not stop reviews"

[ "$FAIL" = 0 ]
