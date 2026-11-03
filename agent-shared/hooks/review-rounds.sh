#!/usr/bin/env bash
# 同じ作業で独立レビューの周回が収束しないとき、新しい周の reviewer の起動を止める。
#   pre  (PreToolUse: Claude の Agent、Codex の spawn_agent)  reviewer の起動を周として数え、止めるか決める
#   stop (SubagentStop)                                       reviewer の最後の行の件数を記録する
#   record <file>                                             他方の CLI で行ったレビューの出力の件数を記録する
# 周は作業ツリーの内容 (未コミットの変更を含む tree) で区別する。同じ内容への並んだ起動は同じ周。
# 新しい周が REVIEW_ROUNDS_LIMIT (既定 3) 周目以降で、直前の周に blocker が記録されていなければ止める。
# 作業は checkout と既定ブランチとの分岐点で数える (branch 上の commit では数え直さない)。12 時間より前の記録は数えない。
# 状態はエージェントも消せるので、権限の境界ではない。記録や判定に失敗したときは起動を止めない。
set -u
STATE="${REVIEW_ROUNDS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/review-rounds}"
LIMIT="${REVIEW_ROUNDS_LIMIT:-3}"
REVIEWERS='["correctness-reviewer","adversarial-reviewer","spec-scope-reviewer"]'

mode="${1:-}"
if [ "$mode" = record ]; then
  [ -f "${2:-}" ] || exit 0
  input=$(jq -nc --rawfile m "$2" --arg cwd "$PWD" \
    '{hook_event_name: "SubagentStop", agent_type: "cross-cli-review", cwd: $cwd, last_assistant_message: $m}') || exit 0
  mode=stop
else
  input=$(cat)
  reviewer=$(jq -r 'if .hook_event_name == "SubagentStop" then .agent_type else (.tool_input.subagent_type // .tool_input.agent_type) end // empty' <<<"$input" 2>/dev/null)
  jq -e --arg a "$reviewer" 'index($a) != null' <<<"$REVIEWERS" >/dev/null 2>&1 || exit 0
fi
agent=$(jq -r 'if .hook_event_name == "SubagentStop" then .agent_type else (.tool_input.subagent_type // .tool_input.agent_type) end // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
top=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
default=$(git -C "$top" rev-parse --verify -q refs/remotes/origin/HEAD || git -C "$top" rev-parse --verify -q refs/heads/master ||
  git -C "$top" rev-parse --verify -q refs/heads/main)
base=$(git -C "$top" merge-base HEAD "${default:-HEAD}" 2>/dev/null || git -C "$top" rev-parse HEAD 2>/dev/null) || exit 0
mkdir -p "$STATE" || exit 0
log="$STATE/$(printf '%s\n%s' "$top" "$base" | sha256sum | cut -c1-32).jsonl"
now=$(date +%s)
since=$((now - 43200))
# 周 = 12 時間以内の起動の記録に出た tree を、初めて出た順に並べたもの
ROUNDS='[.[] | select(.e == "d" and .at >= $since) | .tree] | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)'

case "$mode" in
stop)
  counts=$(jq -c '.last_assistant_message // "" | split("\n") | map(try fromjson catch null | objects | .review_counts | objects
    | select((.blocker | numbers) and (.should | numbers) and (.note | numbers))) | last // null' <<<"$input") || counts=null
  round=0
  if [ -f "$log" ]; then round=$(jq -s --argjson since "$since" "$ROUNDS | length" "$log") || exit 0; fi
  jq -nc --arg a "$agent" --argjson c "$counts" --argjson r "$round" --argjson at "$now" \
    '{e: "r", agent: $a, round: $r, counts: $c, at: $at}' >>"$log"
  ;;
pre)
  idx=$(mktemp "${TMPDIR:-/tmp}/review-rounds-index.XXXXXX") || exit 0
  tree=$(GIT_INDEX_FILE="$idx" git -C "$top" read-tree HEAD 2>/dev/null &&
    GIT_INDEX_FILE="$idx" git -C "$top" add -A 2>/dev/null &&
    GIT_INDEX_FILE="$idx" git -C "$top" write-tree 2>/dev/null)
  rm -f "$idx"
  [ -n "$tree" ] || exit 0
  [ -f "$log" ] || : >"$log"
  verdict=$(jq -rs --arg t "$tree" --argjson limit "$LIMIT" --argjson since "$since" "($ROUNDS) as \$rounds"'
    | if ($rounds | index($t)) != null then "allow"
      elif ($rounds | length) + 1 < $limit then "allow"
      elif ([.[] | select(.e == "r" and .at >= $since and .round == ($rounds | length)) | .counts.blocker // 0] | add // 0) > 0 then "allow"
      else "deny" end' "$log") || exit 0
  if [ "$verdict" != deny ]; then
    jq -nc --arg a "$agent" --arg t "$tree" --argjson at "$now" '{e: "d", agent: $a, tree: $t, at: $at}' >>"$log"
    exit 0
  fi
  trend=$(jq -rs --argjson since "$since" "($ROUNDS | length) as \$n"'
    | [range(1; $n + 1) as $i
       | [.[] | select(.e == "r" and .at >= $since and .round == $i and .counts != null) | .counts] as $c
       | if ($c | length) == 0 then "\($i) 周目: 件数の記録なし"
         else "\($i) 周目: blocker \([$c[].blocker] | add) / should \([$c[].should] | add) / note \([$c[].note] | add)" end]
    | join("\n")' "$log") || exit 0
  reason="同じ作業 (分岐点 $(git -C "$top" rev-parse --short "$base")) で、独立レビューが新しい周に入ろうとしています。直前の周に blocker の記録がないため、新しい周の reviewer は起動しません。
${trend}
レビューは未通過のままです。直前の周の後に直した内容と残りの指摘を、この推移と一緒に利用者へ示し、続けるかの判断を待ってください。"
  jq -nc --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  ;;
esac
exit 0
