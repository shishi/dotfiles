#!/usr/bin/env bash
# Claude Code と Codex 共通の Stop hook。依頼された作業を終えないまま止まろうとしたターン終了を差し戻す。
# 止めてよいかは判定役のモデルが、計画 (kata-active で計画の実装中を記録したセッションだけ)・進捗・
# このセッションのやり取り・最後の応答から判断する。計画が無いセッションでは、利用者の依頼を作業の範囲にし、
# Claude Code の対話のセッションだけを判定する (Codex・委譲された子・非対話の実行は判定しない)。
#   complete          作業を終えた (検証の証拠つき)、または利用者が終えた・取り下げた → 記録を消して止める
#   waiting_on_human  本人の認証・判断・承認が要る、別の手段でも進めない、利用者が一時停止や説明だけを求めた
#                     → 記録を残して止める (返答後も計画を続ける)
#   continue          それ以外 → 残りを進めるよう差し戻す
# 自分で起動したバックグラウンドのタスク (シェル・子エージェント) を待つためのターン終了は判定しない。待ち方は
# task-monitor-*.sh が指示し、ここで「実装を続けて」と差し戻すと、子が担当する task へ親も書きにいくため。
# 判定役を呼べなかったときは止める。差し戻しが続いて終わらない場合に備え、利用者の同じ発言のあいだに
# 連続 MAX_BLOCKS 回差し戻したら止める (利用者の新しい発言で数え直す)。
# Claude Code では asyncRewake で登録し、ターンを終えてから判定して、続けさせるときだけ終了コード 2 で
# エージェントを起こす。利用者はターンの終わりで判定を待たない。Codex は待機中のエージェントを起こせないため、
# ターンの終わりに判定して、続けさせるときは decision: block で差し戻す。
# 引数は登録した CLI (claude / codex)。kata-active と同じく CLI ごとに記録を分ける。
set -u
cli=${1:-}
case $cli in claude|codex) ;; *) echo "kata-completion: 引数に claude か codex を指定してください" >&2; exit 0 ;; esac
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$HOOK_DIR/lib/task-monitor-common.sh"
. "$HOOK_DIR/lib/delegated-session.sh"
turns() { "$(command -v python3 || command -v python)" -I "$HOOK_DIR/lib/session-turns.py" "$@" 2>/dev/null; }
# 同じセッションの Stop どうしで、世代の書き換えと、判定の結果を状態へ反映する処理を順に行う。macOS には flock が
# 無いため mkdir で取る。持ち主が異常終了して残った場合に備え、10 秒待っても取れなければ取り除いて取り直す
lock() { local i=0; until mkdir -p "$dir" && mkdir "$dir/lock" 2>/dev/null; do i=$((i + 1)); [ "$i" -lt 100 ] || { rmdir "$dir/lock" 2>/dev/null; i=0; }; sleep 0.1; done; }
unlock() { rmdir "$dir/lock" 2>/dev/null; }

in=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$in")
[ -n "$sid" ] || exit 0
# kata-active と同じ場所。両 CLI の sandbox から書ける /tmp/claude-<uid> の下に置く
dir="${KATA_STATE_DIR:-/tmp/claude-$(id -u)/kata}/$cli/$sid"
plan=
[ -f "$dir/plan" ] && plan=$(cat "$dir/plan")
# 計画が無いとき、Codex は判定しない。Codex は待機中のエージェントを起こせず、判定のたびに利用者がターンの
# 終わりで待つため。このとき監視 hook (task-monitor-codex.sh) は自分の Stop で判定する
[ ! -f "$dir/plan" ] && [ "$cli" = codex ] && exit 0
# Codex の計画の実装中は、監視 hook の Stop の判定をここから呼ぶ。監視 hook は計画の実装中のセッションでは
# 自分の Stop で判定せず、この呼出しに任せる
if [ "$cli" = codex ]; then
  monitor=$(bash "$HOOK_DIR/task-monitor-codex.sh" stop from-kata <<<"$in")
  [ -n "$monitor" ] && { printf '%s\n' "$monitor"; exit 0; }
  # 計画ファイルが空なら、計画が無いのと同じく判定しない
  [ -n "$plan" ] || exit 0
fi
transcript=$(jq -r '.transcript_path // empty' <<<"$in")
# 計画が無いとき、委譲された子と、プログラムから起動した非対話の実行は判定しない。完了は呼び出し元が確かめ、
# 続けさせると呼び出し元が受け取る出力が変わるため
if [ -z "$plan" ]; then
  delegated_session "$sid" && exit 0
  [ ! -f "$transcript" ] || [ "$(turns "$transcript" interactive)" != no ] || exit 0
fi
# 計画ファイルが消えた (/tmp の掃除など) 記録では判定できないため、記録を消して止める
[ -z "$plan" ] || [ -f "$plan" ] || { rm -rf "$dir"; exit 0; }
mkdir -p "$dir"

# 後から来た Stop が書き換える。Claude Code で判定の間に次のターンが終わったら (バックグラウンドのタスクを待つ Stop も含めて)、古い判定では起こさない
# date の %N は macOS の古い版で使えないため、整数のナノ秒は Python で取る (テストでは KATA_COMPLETION_NOW で固定する)
gen=${KATA_COMPLETION_NOW:-$("$(command -v python3 || command -v python)" -c 'import time; print(time.time_ns())')}
# 世代は Stop の開始時刻。ロックを待つ間に後から始まった Stop が先に書いていたら、自分は古いので書かずに抜ける
lock
current=$(cat "$dir/gen" 2>/dev/null)
# 以前の版が書いた整数でない世代は、比べずに書き換える
case $current in '' | *[!0-9]*) current=0 ;; esac
[ "$current" -le "$gen" ] || { unlock; exit 0; }
printf '%s\n' "$gen" > "$dir/gen"
unlock
if [ "$cli" = claude ]; then
  [ "$(jq '[.background_tasks[]? | select(.type == "shell" or .type == "subagent")] | length' <<<"$in")" -gt 0 ] && exit 0
fi

# Claude Code は同期の Stop hook の差し戻しが 10 回続くとターンを終える (2.1.309 の実測)。両 CLI で同じ回数にそろえる
MAX_BLOCKS=10
# 判定役を待つ上限。hook 全体の実測は 2〜11 秒。hook の timeout (120 秒) より短くし、超えたら止める側へ倒す
JUDGE_TIMEOUT=90

cwd=$(jq -r '.cwd // empty' <<<"$in")
final=$(jq -r '.last_assistant_message // empty' <<<"$in")
activity= requests= last_user=
if [ -f "$transcript" ]; then
  # 検証の結果は 1 つのコマンドの出力の後半にあることが多いため、結果は先頭と末尾を長めに残す。
  # 1 行が長くなる分、直近の操作が残るよう全体の上限も広げる
  activity=$(tm_excerpt "$transcript" 12000 1500)
  # 計画が無いセッションでは、前の依頼の残りも作業の範囲になる。依頼ごとに、終えたのか一時停止したのかを
  # 判定役が知れるよう、利用者の発言とそのターンの最後の文を順に渡す (取り出し方は lib/session-turns.py)
  # 依頼・最後の発言・発言の数は、同じ時点の記録から作る。読む間に利用者の発言が届いても食い違わないよう、
  # 一度写してから読む
  # 後片付けが消すのは写しだけにする。写せなかったときは、書き込み中の原本から読むと同じ時点の材料にならない
  # ため判定しない
  copy=$(mktemp "${TMPDIR:-/tmp}/kata-completion.XXXXXX") || exit 0
  trap 'rm -f -- "$copy"' EXIT
  cp "$transcript" "$copy" || exit 0
  snapshot=$copy
  requests=$(turns "$snapshot" turns)
  last_user=$(turns "$snapshot" last)
  # Stop の最後の応答より後に利用者の発言が届いていたら、その発言のターンの Stop に判定を任せる
  [ -z "$final" ] || [ "$(printf '%s' "$final" | turns "$snapshot" replied)" != no ] || exit 0
fi
# 差し戻しの連続回数は、利用者の発言ごとに数え直す。Claude Code では後から起こすため、
# stop_hook_active では同じ発言の続きかを見分けられない。同じ文面を送り直した場合も見分けるよう、発言の数で比べる
user_mark=$( [ -f "$transcript" ] && turns "$snapshot" mark || echo 0)
[ "$(cat "$dir/user" 2>/dev/null)" = "$user_mark" ] || { rm -f "$dir/blocks"; printf '%s\n' "$user_mark" > "$dir/user"; }
blocks=$(cat "$dir/blocks" 2>/dev/null || echo 0)
if [ "$blocks" -ge "$MAX_BLOCKS" ]; then
  rm -f "$dir/blocks"
  echo "kata-completion: 差し戻しが $MAX_BLOCKS 回続いたため止めます" >&2
  exit 0
fi
progress=
[ -n "$plan" ] && [ -f "$(dirname "$plan")/progress.md" ] && progress=$(cat "$(dirname "$plan")/progress.md")

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

if raw=$(printf 'PLAN (%s):\n%s\n\nPROGRESS:\n%s\n\nUSER REQUESTS:\n%s\n\nLAST USER MESSAGE:\n%s\n\nRECENT ACTIVITY:\n%s\n\nFINAL MESSAGE:\n%s\n' \
           "${plan:-none}" "$( [ -n "$plan" ] && cat "$plan" 2>/dev/null || echo '(no plan: the work is what USER REQUESTS asked for)')" \
           "${progress:-(none)}" "${requests:-(unknown)}" "${last_user:-(unknown)}" \
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
# Claude Code では判定の間に利用者が発言したら、その時点の判定に任せて何もしない
if [ "$cli" = claude ] && [ -f "$transcript" ]; then
  [ "$(turns "$transcript" mark)" = "$user_mark" ] || exit 0
fi
# 次の Stop が来ていたら古い判定は捨てる。世代の照合から状態の書き換えまでを、世代の書き換えと順に行う
lock
[ "$(cat "$dir/gen" 2>/dev/null)" = "$gen" ] || { unlock; exit 0; }
case $status in
  # 状態のディレクトリごとは消さない。次の Stop が書いた世代を消すと、その判定が古いものとして捨てられる。
  # 計画は、判定を始めたときと同じものだけを消す (判定の間に別の計画が記録されていたら残す)
  complete)
    [ "$(cat "$dir/plan" 2>/dev/null)" != "$plan" ] || rm -f "$dir/plan"
    rm -f "$dir/blocks"; unlock; exit 0 ;;
  waiting_on_human) rm -f "$dir/blocks"; unlock; exit 0 ;;
esac
printf '%s\n' $((blocks + 1)) > "$dir/blocks"
unlock
message="kata: "
if [ -z "$plan" ]; then
  message+="依頼された作業がまだ終わっていません ($reason)。このセッションの依頼と訂正を確かめて、残りを実行・検証してください。"
else
  message+="計画 $plan の実装がまだ終わっていません ($reason)。計画と進捗を確かめて、残りの task を実装・検証してください。"
fi
message+="本人の認証・判断・承認が必要な場合は、必要な理由と最小の操作を具体的に報告して終えてください。"
[ -z "$plan" ] || message+="計画を終えた、または利用者の指示で中止した場合は \`~/.agent-shared/bin/kata-active $cli done\` を実行してから終えてください。"
if [ "$cli" = claude ]; then
  printf '%s\n' "$message" >&2
  exit 2
fi
jq -cn --arg m "$message" '{decision: "block", reason: $m}'
exit 0
