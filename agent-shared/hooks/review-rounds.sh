#!/usr/bin/env bash
# 独立レビューの周を区切りごとに数え、採用した指摘を確かめる周が上限を超えて続くときだけ止める。
#   pre  (PreToolUse: Claude の Agent、Codex の spawn_agent)  reviewer の起動を周として数え、止めるか決める
#   stop (SubagentStop)                                       reviewer の最後の行の件数を記録する (推移の表示用)
#   record <file>                                             他方の CLI で行ったレビューの出力の件数を記録する
#   adopt <blocker> <should>                                  直前の周で司令塔が採用した指摘の件数を記録する
#   continue                                                  上限で止まった後、利用者が続けると決めたことを記録する
#   delta                                                     直前の周の内容から今の作業ツリーまでの差分を出す
# 周は作業ツリーの内容 (未コミットの変更を含む tree) で区別する。同じ内容への並んだ起動は同じ周。
# 周の役目は二つある。まだレビューしていない変更を見る周と、前の周で採用した指摘が直ったかを確かめる周。
# 採用した指摘の無い周 (レビュー通過) か continue の記録で区切りが付き、次の周は新しい区切りの 1 周目になる。
# 新しい変更 (別のゲート、追加の依頼、受入の修正) は必ずレビューできる。止めるのは、採用した指摘のある周が
# REVIEW_ROUNDS_LIMIT (既定 5) 周続き、さらに続けようとするときだけ。収束しない反復なので、推移を示して利用者の
# 判断を求める。採用の件数は司令塔が adopt で記録した件数を使う。記録が無い周は、記録し忘れても上限が効くよう、
# reviewer が挙げた blocker・should の件数で代える。
# 作業は checkout と既定ブランチとの分岐点で数える。タスク用ブランチではローカルの既定ブランチを使う
# (remote の既定ブランチは push していない間は古く、別の作業までまとめてしまうため)。既定ブランチの上で
# 直接作業しているときは、commit のたびに数え直さないよう remote の既定ブランチを使う。12 時間より前の記録は数えない。
# 状態はエージェントも消せるので、権限の境界ではない。記録や判定に失敗したときは起動を止めない。
set -u -o pipefail
STATE="${REVIEW_ROUNDS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/review-rounds}"
LIMIT="${REVIEW_ROUNDS_LIMIT:-5}"
REVIEWERS='["correctness-reviewer","adversarial-reviewer","spec-scope-reviewer"]'

# jq の出力は Windows の jq で CRLF になることがあるため、読み取る値はすべてここを通す。
jqv() { jq "$@" | tr -d '\r'; }

mode="${1:-}"
case "$mode" in
  record)
    [ -f "${2:-}" ] || exit 0
    input=$(jqv -nc --rawfile m "$2" --arg cwd "$PWD" \
      '{hook_event_name: "SubagentStop", agent_type: "cross-cli-review", cwd: $cwd, last_assistant_message: $m}') || exit 0
    mode=stop ;;
  adopt)
    if [ "$#" -ne 3 ] || case "$2" in ""|*[!0-9]*) true ;; *) false ;; esac || case "$3" in ""|*[!0-9]*) true ;; *) false ;; esac; then
      echo "usage: review-rounds.sh adopt <採用した blocker の件数> <採用した should の件数>" >&2
      exit 2
    fi
    input=$(jqv -nc --arg cwd "$PWD" '{cwd: $cwd}') || exit 0 ;;
  continue|delta)
    input=$(jqv -nc --arg cwd "$PWD" '{cwd: $cwd}') || exit 0 ;;
  pre|stop)
    input=$(cat)
    reviewer=$(jqv -r 'if .hook_event_name == "SubagentStop" then .agent_type else (.tool_input.subagent_type // .tool_input.agent_type) end // empty' <<<"$input" 2>/dev/null)
    jq -e --arg a "$reviewer" 'index($a) != null' <<<"$REVIEWERS" >/dev/null 2>&1 || exit 0 ;;
  *) echo "usage: review-rounds.sh pre|stop|record <file>|adopt <blocker> <should>|continue|delta" >&2; exit 2 ;;
esac
agent=$(jqv -r 'if .hook_event_name == "SubagentStop" then .agent_type else (.tool_input.subagent_type // .tool_input.agent_type) end // empty' <<<"$input")
cwd=$(jqv -r '.cwd // empty' <<<"$input")
top=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
local_default=$(git -C "$top" rev-parse --verify -q refs/heads/master || git -C "$top" rev-parse --verify -q refs/heads/main)
on_default=false
case "$(git -C "$top" symbolic-ref -q HEAD 2>/dev/null)" in refs/heads/master|refs/heads/main) on_default=true ;; esac
if [ "$on_default" = true ] || [ -z "$local_default" ]; then
  default=$(git -C "$top" rev-parse --verify -q refs/remotes/origin/HEAD ||
    git -C "$top" rev-parse --verify -q "refs/remotes/origin/$(git -C "$top" symbolic-ref -q --short HEAD 2>/dev/null)")
else
  default=$local_default
fi
base=$(git -C "$top" merge-base HEAD "${default:-HEAD}" 2>/dev/null || git -C "$top" rev-parse HEAD 2>/dev/null) || exit 0
mkdir -p "$STATE" || exit 0
log="$STATE/$(printf '%s\n%s' "$top" "$base" | sha256sum | cut -c1-32).jsonl"
now=$(date +%s)
since=$((now - 43200))
# 周 = 12 時間以内の起動の記録に出た tree を、初めて出た順に並べたもの
ROUNDS='[.[] | select(.e == "d" and .at >= $since) | .tree] | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)'
# 記録の行を 1 行ずつ読み、壊れた行は飛ばす
records() { [ -f "$log" ] && jqv -cR 'fromjson? // empty' "$log"; }
round_count() { records | jqv -s --argjson since "$since" "$ROUNDS | length"; }
# 最後の行が書きかけで改行が無くても、新しい記録が同じ行につながって壊れないようにする
append() {
  [ -s "$log" ] && [ -n "$(tail -c 1 "$log")" ] && printf '\n' >>"$log"
  printf '%s\n' "$1" >>"$log"
}

# 未コミットの変更と新しいファイルを含む、今の作業ツリーの tree
work_tree() {
  local idx tree
  idx=$(mktemp "${TMPDIR:-/tmp}/review-rounds-index.XXXXXX") || return 1
  tree=$(GIT_INDEX_FILE="$idx" git -C "$top" read-tree HEAD 2>/dev/null &&
    GIT_INDEX_FILE="$idx" git -C "$top" add -A 2>/dev/null &&
    GIT_INDEX_FILE="$idx" git -C "$top" write-tree 2>/dev/null)
  rm -f "$idx"
  [ -n "$tree" ] && printf '%s\n' "$tree"
}

case "$mode" in
stop)
  counts=$(jqv -c '.last_assistant_message // "" | split("\n") | map(try fromjson catch null | objects | .review_counts | objects
    | select((.blocker | numbers) and (.should | numbers) and (.note | numbers))) | last // null' <<<"$input") || counts=null
  round=$(round_count) || exit 0
  append "$(jqv -nc --arg a "$agent" --argjson c "$counts" --argjson r "${round:-0}" --argjson at "$now" \
    '{e: "r", agent: $a, round: $r, counts: $c, at: $at}')"
  ;;
adopt)
  round=$(round_count) && [ "${round:-0}" -gt 0 ] || { echo "review-rounds: この作業のレビューの周の記録が無い (reviewer を起動した checkout で実行すること)" >&2; exit 1; }
  append "$(jqv -nc --argjson b "$2" --argjson s "$3" --argjson r "${round:-0}" --argjson at "$now" \
    '{e: "a", round: $r, blocker: $b, should: $s, at: $at}')" || exit 1
  echo "review-rounds: ${round:-0} 周目で採用した指摘を記録した (blocker $2 / should $3)"
  ;;
continue)
  round=$(round_count) && [ "${round:-0}" -gt 0 ] || { echo "review-rounds: この作業のレビューの周の記録が無い (reviewer を起動した checkout で実行すること)" >&2; exit 1; }
  append "$(jqv -nc --argjson r "${round:-0}" --argjson at "$now" '{e: "c", round: $r, at: $at}')" || exit 1
  echo "review-rounds: ${round:-0} 周目の後から、新しい区切りとして周を数え直す"
  ;;
delta)
  last=$(records | jqv -rs --argjson since "$since" "$ROUNDS | last // empty")
  [ -n "$last" ] || { echo "review-rounds: この作業のレビューの周の記録が無い" >&2; exit 1; }
  tree=$(work_tree) || exit 1
  git -C "$top" diff "$last" "$tree"
  ;;
pre)
  tree=$(work_tree) || exit 0
  [ -f "$log" ] || : >"$log"
  # 区切り = 採用の無い周か continue の記録の後。今の区切りで、採用のあった周が直前まで何周続いたかを数える。
  verdict=$(records | jqv -rs --arg t "$tree" --argjson limit "$LIMIT" --argjson since "$since" "($ROUNDS) as \$rounds"'
    | ($rounds | length) as $n
    | (. as $all | [range(1; $n + 1) as $i
        | [$all[] | select(.e == "a" and .at >= $since and .round == $i) | .blocker + .should] as $a
        | if ($a | length) > 0 then ($a | add) > 0
          else ([$all[] | select(.e == "r" and .at >= $since and .round == $i and .counts != null)
                 | .counts.blocker + .counts.should] | add // 0) > 0 end]) as $adopted
    | ([.[] | select(.e == "c" and .at >= $since) | .round] | max // 0) as $cont
    | ([range($n; $cont; -1) | select($adopted[. - 1] | not)] | first // $cont) as $cut
    | if ($rounds | index($t)) != null or $n == 0 or ($adopted[$n - 1] | not) then "allow"
      elif $n - $cut >= $limit then "limit"
      else "allow" end') || exit 0
  case "$verdict" in allow|limit) ;; *) exit 0 ;; esac
  if [ "$verdict" = allow ]; then
    append "$(jqv -nc --arg a "$agent" --arg t "$tree" --argjson at "$now" '{e: "d", agent: $a, tree: $t, at: $at}')"
    exit 0
  fi
  trend=$(records | jqv -rs --argjson since "$since" "($ROUNDS | length) as \$n"'
    | [range(1; $n + 1) as $i
       | [.[] | select(.e == "r" and .at >= $since and .round == $i and .counts != null) | .counts] as $c
       | [.[] | select(.e == "a" and .at >= $since and .round == $i)] as $a
       | "\($i) 周目: 挙がった指摘 "
         + (if ($c | length) == 0 then "記録なし"
            else "blocker \([$c[].blocker] | add) / should \([$c[].should] | add) / note \([$c[].note] | add)" end)
         + "、採用 "
         + (if ($a | length) == 0 then "記録なし"
            else "blocker \([$a[].blocker] | add) / should \([$a[].should] | add)" end)]
    | join("\n")') || exit 0
  reason="同じ作業 (分岐点 $(git -C "$top" rev-parse --short "$base")) で、採用した指摘のある周が ${LIMIT} 周続き、収束していないため、新しい周の reviewer は起動しません。
${trend}
レビューは未通過のままです。直前の周の後に直した内容と残りの指摘を、この推移と一緒に利用者へ示し、続けるかの判断を待ってください。利用者が続けると決めたら \`bash ~/.agent-shared/hooks/review-rounds.sh continue\` を実行してから起動し直してください。"
  jq -nc --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  ;;
esac
exit 0
