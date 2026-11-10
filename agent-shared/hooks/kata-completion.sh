#!/usr/bin/env bash
# Claude Code と Codex 共通の Stop hook。kata-active で計画の実装中を記録したセッションでだけ動き、
# 計画を終えないまま止まろうとしたターン終了を差し戻す。止めてよいかは判定役のモデルが、計画・進捗・
# 直近の利用者の発言・最後の応答から判断する。記録が無いセッションでは何もせずに終わる。
#   complete          計画を終えた (検証の証拠つき)、または利用者が計画を終えた・取り下げた → 記録を消して止める
#   waiting_on_human  本人の認証・判断・承認が要る、別の手段でも進めない、利用者が一時停止や説明だけを求めた
#                     → 記録を残して止める (返答後も計画を続ける)
#   continue          それ以外 → 残りを進めるよう差し戻す
# 自分で起動したバックグラウンドのタスク (シェル・子エージェント) を待つためのターン終了は判定しない。待ち方は
# task-monitor-*.sh が指示し、ここで「実装を続けて」と差し戻すと、子が担当する task へ親も書きにいくため。
# 判定役を呼べなかったときは止める。差し戻しが続いて終わらない場合に備え、利用者のターンの中で
# 連続 MAX_BLOCKS 回差し戻したら止める (stop_hook_active が無い最初の Stop で数え直す)。
# 引数は登録した CLI (claude / codex)。kata-active と同じく CLI ごとに記録を分ける。
set -u
cli=${1:-}
case $cli in claude|codex) ;; *) echo "kata-completion: 引数に claude か codex を指定してください" >&2; exit 0 ;; esac
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$HOOK_DIR/lib/task-monitor-common.sh"

in=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$in")
[ -n "$sid" ] || exit 0
# kata-active と同じ場所。両 CLI の sandbox から書ける /tmp/claude-<uid> の下に置く
dir="${KATA_STATE_DIR:-/tmp/claude-$(id -u)/kata}/$cli/$sid"
[ -f "$dir/plan" ] || exit 0
plan=$(cat "$dir/plan")
# 計画ファイルが消えた (/tmp の掃除など) 記録では判定できないため、記録を消して止める
[ -f "$plan" ] || { rm -rf "$dir"; exit 0; }

if [ "$cli" = claude ]; then
  [ "$(jq '[.background_tasks[]? | select(.type == "shell" or .type == "subagent")] | length' <<<"$in")" -gt 0 ] && exit 0
else
  # task-monitor-codex.sh が実行中のコマンド・子エージェントを記録する場所 (tm_state_dir と同じ)
  running="${TASK_MONITOR_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/task-monitor}/codex/$sid/running"
  [ -n "$(ls -A "$running" 2>/dev/null)" ] && exit 0
fi

# Claude Code は同じ hook の差し戻しが 10 回続くとターンを終える (2.1.309 の実測)。両 CLI で同じ回数にそろえる
MAX_BLOCKS=10
# 判定役を待つ上限。実測は 2〜4 秒。hook の timeout (120 秒) より短くし、超えたら止める側へ倒す
JUDGE_TIMEOUT=90

[ "$(jq -r '.stop_hook_active // false' <<<"$in")" = true ] || rm -f "$dir/blocks"
blocks=$(cat "$dir/blocks" 2>/dev/null || echo 0)
if [ "$blocks" -ge "$MAX_BLOCKS" ]; then
  rm -f "$dir/blocks"
  echo "kata-completion: 差し戻しが $MAX_BLOCKS 回続いたため止めます" >&2
  exit 0
fi

cwd=$(jq -r '.cwd // empty' <<<"$in")
transcript=$(jq -r '.transcript_path // empty' <<<"$in")
final=$(jq -r '.last_assistant_message // empty' <<<"$in")
activity= last_user=
if [ -f "$transcript" ]; then
  # 検証の結果は 1 つのコマンドの出力の後半にあることが多いため、結果は先頭と末尾を長めに残す。
  # 1 行が長くなる分、直近の操作が残るよう全体の上限も広げる
  activity=$(tm_excerpt "$transcript" 12000 1500)
  # Claude の会話記録は利用者の入力を type=user・本文が文字列の行に残す。Codex の rollout (0.167.0) は
  # role=user の message に残し、AGENTS.md・環境・hook の差し戻しと同じ形になるため、各要素の
  # provenance が user のものだけを取る。ツール結果や注入された指示は含めない
  last_user=$(jq -R -r '
    fromjson? |
    if .type == "user" and (.isMeta | not) and (.message.content | type == "string") then .message.content
    elif .type == "user" and (.isMeta | not) and (.message.content | type == "array")
         and ([.message.content[] | select(.type == "tool_result")] | length == 0) then
      [.message.content[] | select(.type == "text") | .text] | join(" ")
    elif .type == "response_item" and .payload.type == "message" and .payload.role == "user" then
      [.payload.content, (.payload.internal_chat_message_metadata_passthrough.content_item_metadata // [])]
      | transpose | map(select(.[1].provenance.type? == "user") | .[0].text? // empty) | join(" ")
    else empty end | select(length > 0) | gsub("\\s+"; " ")' "$transcript" | tail -n 1)
fi
progress=
[ -f "$(dirname "$plan")/progress.md" ] && progress=$(cat "$(dirname "$plan")/progress.md")

schema='{"type":"object","properties":{"status":{"type":"string","enum":["complete","waiting_on_human","continue"]},"reason":{"type":"string"}},"required":["status","reason"],"additionalProperties":false}'
judge() {
  if [ -n "${KATA_COMPLETION_JUDGE:-}" ]; then
    $KATA_COMPLETION_JUDGE
  else
    "$(command -v python3 || command -v python)" -I "$HOOK_DIR/lib/run-judge.py" "$JUDGE_TIMEOUT" "${cwd:-/}" \
      claude -p --model sonnet --setting-sources "" --strict-mcp-config --tools "" --no-session-persistence \
      --system-prompt-file "$HOOK_DIR/kata-completion-judge-prompt.md" --json-schema "$schema" --output-format json
  fi
}

if raw=$(printf 'PLAN (%s):\n%s\n\nPROGRESS:\n%s\n\nLAST USER MESSAGE:\n%s\n\nRECENT ACTIVITY:\n%s\n\nFINAL MESSAGE:\n%s\n' \
           "$plan" "$(cat "$plan" 2>/dev/null)" "${progress:-(none)}" "${last_user:-(unknown)}" \
           "${activity:-(unknown)}" "${final:-(unknown)}" | judge 2>/dev/null); then
  v=$(jq -sc 'if length == 1 and .[0].is_error == false and .[0].subtype == "success"
              and (.[0].structured_output.status | IN("complete", "waiting_on_human", "continue"))
              and (.[0].structured_output.reason | type == "string" and length > 0)
              then .[0].structured_output else empty end' <<<"$raw" 2>/dev/null)
else
  v=
fi
if [ -z "$v" ]; then
  echo "kata-completion: 判定役から有効な判定を得られなかったため止めます" >&2
  exit 0
fi

status=$(jq -r .status <<<"$v") reason=$(jq -r .reason <<<"$v")
case $status in
  complete) rm -rf "$dir" ;;
  waiting_on_human) rm -f "$dir/blocks" ;;
  continue)
    printf '%s\n' $((blocks + 1)) > "$dir/blocks"
    jq -cn --arg plan "$plan" --arg r "$reason" --arg cli "$cli" '{decision: "block", reason: (
      "kata: 計画 " + $plan + " の実装がまだ終わっていません (" + $r + ")。計画と進捗を確かめて、残りの task を実装・検証してください。" +
      "本人の認証・判断・承認が必要な場合は、必要な理由と最小の操作を具体的に報告して終えてください。" +
      "計画を終えた、または利用者の指示で中止した場合は `~/.agent-shared/bin/kata-active " + $cli + " done` を実行してから終えてください。")}' ;;
esac
exit 0
