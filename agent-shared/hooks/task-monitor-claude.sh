#!/usr/bin/env bash
# Claude Code の Stop hook (asyncRewake)。引数 pre-bash では PreToolUse (Bash) の前面起動のガード (下記)。
# ターン終了時に実行中のバックグラウンドのタスク (シェル・子エージェント) を、
# 10・20・40 分、以後 40 分ごとに判定役へ見せ、進んでいなければ終了コード 2 でエージェントを起こす。
# 進んでいる間は起こさないので、エージェントのトークンを使わない。タスクが終われば Claude Code 自身が起こす。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$HOOK_DIR/lib/task-monitor-common.sh"

in=$(cat)

# PreToolUse (Bash) で "pre-bash" を付けて呼ぶ。前面で動くコマンドの間はエージェントもこの監視も動けず、
# 止まったコマンドを見つけられない。前面のコマンドは指定した上限を過ぎるとバックグラウンドへ移り、監視の対象になる。
# 前面で監視されずに待つのを既定の上限 (BASH_DEFAULT_TIMEOUT_MS、未設定なら 2 分) までにするため、
# それより長い待ちを指定した起動はバックグラウンドで起動し直させる。
# 子エージェント (agent_id がある) の呼出しは除く。子は自分のバックグラウンドの完了を待たずに終わりうるため。
if [ "${1:-}" = pre-bash ]; then
  jq -c --argjson d "${BASH_DEFAULT_TIMEOUT_MS:-120000}" '
    select((.agent_id // "") == "" and (.tool_input.run_in_background // false) != true and (.tool_input.timeout // 0) > $d)
    | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason:
        ("監視: 前面で待てるのは既定の上限 (" + ($d / 60000 | tostring) + " 分) までです。それより長い見込みのコマンドは、止まっても誰も気づけません。同じコマンドを run_in_background: true で起動し直してください。進み具合を標準出力にも出すと、監視が止まっているかを判断できます。")}}' <<<"$in"
  exit 0
fi

sid=$(jq -r '.session_id // empty' <<<"$in")
cwd=$(jq -r '.cwd // empty' <<<"$in")
[ -n "$sid" ] || exit 0
state=$(tm_state_dir claude "$sid") || exit 0

# 新しいターン終了で数え直す。後から来た Stop が世代を書き換え、古い監視は次の 1 分の区切りで終わる。
gen=$(date +%s%N)
printf '%s\n' "$gen" > "$state/gen"

tasks=$(jq -c '[.background_tasks[]? | select(.type == "shell" or .type == "subagent")]' <<<"$in")
[ "$(jq length <<<"$tasks")" -gt 0 ] || exit 0
# 判定役を待つ上限。後から来た Stop で古い監視が 1 分以内に終わるよう、1 分より短くする (実測は 1〜2 秒)。
JUDGE_TIMEOUT=50

tasks_dir=${TASK_MONITOR_TASKS_DIR:-/tmp/claude-$(id -u)/$(printf %s "$cwd" | sed 's#[/.]#-#g')/$sid/tasks}
# 一時ディレクトリの場所は OS で違いうるため、既定の場所に無ければセッション ID で探す
if [ ! -d "$tasks_dir" ]; then
  found=$(find "${TMPDIR:-/tmp}" /tmp -maxdepth 4 -type d -path "*/$sid/tasks" 2>/dev/null | head -n 1)
  [ -n "$found" ] && tasks_dir=$found
fi
# hook の timeout (86400 秒) より 10 分短い。打ち切られて黙って監視が消えるのを避けるため、
# 判定役の待ち時間も含めた実経過時間で締切を見る。
budget=${TASK_MONITOR_BUDGET_MIN:-1430}
deadline=$(( $(date +%s) + budget * TASK_MONITOR_MINUTE ))
# 待ち時間を 0 にしたテストでは締切も 0 になるため、締切を見ない
[ "$TASK_MONITOR_MINUTE" -gt 0 ] || deadline=$(( $(date +%s) + 86400 ))
ntasks=$(jq length <<<"$tasks")
schema='{"type":"object","properties":{"status":{"type":"string","enum":["progressing","stalled","unclear"]},"reason":{"type":"string"}},"required":["status","reason"],"additionalProperties":false}'

judge() {
  if [ -n "${TASK_MONITOR_JUDGE:-}" ]; then
    $TASK_MONITOR_JUDGE
  else
    "$py_bin" -I "$HOOK_DIR/lib/run-judge.py" "$JUDGE_TIMEOUT" "${cwd:-/}" claude -p --model haiku --setting-sources "" \
      --strict-mcp-config --tools "" --no-session-persistence \
      --system-prompt-file "$HOOK_DIR/task-monitor-judge-prompt.md" --json-schema "$schema" --output-format json
  fi
}

py_bin=$(command -v python3 || command -v python)

superseded() { [ "$(cat "$state/gen" 2>/dev/null)" != "$gen" ]; }

n=0 summary=
while :; do
  interval=$(tm_interval $n)
  if [ $(( $(date +%s) + (interval * 60 + JUDGE_TIMEOUT * ntasks) * TASK_MONITOR_MINUTE / 60 )) -gt "$deadline" ]; then
    printf '監視: hook の制限時間が近いため、監視をここで終えます。実行中のタスクと直近の判定は次のとおりです。各タスクの出力を確かめ、止まっていれば TaskStop で止めて、原因を調べ、直すか別の方法で元の目的をやり直してください。進んでいれば、ターンを終えると監視が始め直されます。\n%s' "$summary" >&2
    exit 2
  fi
  i=0
  while [ $i -lt "$interval" ]; do
    sleep "$TASK_MONITOR_MINUTE"
    superseded && exit 0
    i=$((i + 1))
  done
  summary=
  for row in $(jq -r '.[] | @base64' <<<"$tasks"); do
    task=$(base64 -d <<<"$row")
    id=$(jq -r .id <<<"$task")
    desc=$(jq -r '.description + " :: " + (.command // .agent_type // "")' <<<"$task")
    out="$tasks_dir/$id.output"
    if [ -e "$out" ]; then
      if [ "$(jq -r .type <<<"$task")" = subagent ]; then cur=$(tm_excerpt "$out"); else cur=$(tail -c 3000 "$out"); fi
      prev=$(cat "$state/prev-$id" 2>/dev/null || echo "(first check)")
      now=$(date +%s)
      since=$(( now - $(cat "$state/prev-time-$id" 2>/dev/null || echo $((now - interval * 60 * TASK_MONITOR_MINUTE / 60))) ))
      if raw=$(printf 'TASK: %s\nSECONDS SINCE PREVIOUS CHECK: %s\n\nPREVIOUS:\n%s\n\nCURRENT:\n%s\n' \
                 "$desc" "$since" "$prev" "$cur" | judge 2>/dev/null); then
        v=$(jq -sc 'if length == 1 and .[0].is_error == false and .[0].subtype == "success"
                    and (.[0].structured_output.status | IN("progressing", "stalled", "unclear"))
                    and (.[0].structured_output.reason | type == "string" and length > 0)
                    then .[0].structured_output else empty end' <<<"$raw" 2>/dev/null)
      else
        v=
      fi
      if [ -n "$v" ]; then
        status=$(jq -r .status <<<"$v") reason=$(jq -r .reason <<<"$v")
      else
        status=unclear reason="判定役から有効な判定を得られなかった"
      fi
      printf '%s' "$cur" > "$state/prev-$id"; printf '%s\n' "$now" > "$state/prev-time-$id"
    else
      cur= status=unclear reason="出力ファイルが見つからない"
    fi
    superseded && exit 0
    summary="$summary- $id ($desc): $status ($reason)"$'\n'
    if [ "$status" != progressing ]; then
      printf '監視: バックグラウンドのタスク %s (%s) が進んでいない可能性があります (%s: %s)。出力ファイル %s の最新の内容を確かめて、止まっているなら TaskStop で止め、原因を調べて、直すか別の方法で、このタスクで達成しようとしていた元の目的をやり直して。\n出力の末尾:\n%s\n' \
        "$id" "$desc" "$status" "$reason" "$out" "$(printf '%s' "$cur" | tail -c 800)" >&2
      exit 2
    fi
  done
  n=$((n + 1))
done
