#!/usr/bin/env bash
# stall-guard: 背景作業 (Claude Code の Agent/Bash の背景、Codex の子の run) があるのに
# 確認の予定が無いままターンを終えることを、hook とコマンドで止める。
#
#   stall-guard.sh [--cli claude|codex] <subcommand> [args]
#     Claude: record [--failed] | inject | stop-check | watch | deadline <id> <分> [--watch <path>]... | keep <id>
#     Codex:  record | subagent-start | subagent-stop | stop-check | pre-wait | inject
#     共通:   status [--json] [--session <id>] | disable
#
# 台帳はセッションごとの JSONL で、Git の外の状態ディレクトリに置く
# (${STALL_GUARD_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/stall-guard}/<cli>/<session_id>/)。
# 判定には本体が出す構造化された値と時刻だけを使い、モデルの文やコマンドの文字列は照合しない。
# hook は自分の失敗で利用者の操作を止めない: 読めない入力や jq の失敗では何も出さずに exit 0 で終わる。
set -u

SG_HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SG_SELF="$SG_HOOK_DIR/stall-guard.sh"
SG_ROOT=${STALL_GUARD_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/stall-guard}
SG_CR=$'\r'
SG_SKIPPED=0
SG_INTERVAL=1200

sg_now() {
  if [ -n "${STALL_GUARD_NOW:-}" ]; then printf '%s\n' "$STALL_GUARD_NOW"; else printf '%(%s)T\n' -1; fi
}

# 本体の cron 式はローカル時刻なので、発火時刻の照合に使う UTC からの差 (秒)。
sg_tz_offset() {
  local z
  printf -v z '%(%z)T' "${1:--1}"
  local sign=1
  [ "${z:0:1}" = - ] && sign=-1
  echo $((sign * (10#${z:1:2} * 3600 + 10#${z:3:2} * 60)))
}

sg_strip_cr() { tr -d '\r'; }

sg_valid_sid() { [[ "${1:-}" =~ ^[A-Za-z0-9_-]+$ ]]; }

sg_session_dir() {
  sg_valid_sid "$2" || return 1
  printf '%s/%s/%s\n' "$SG_ROOT" "$1" "$2"
}

sg_disabled() { [ -e "$SG_ROOT/disabled" ]; }

sg_mark_hooked() {
  local f="$SG_ROOT/hooked/$1/$2"
  [ -e "$f" ] && return 0
  mkdir -p "${f%/*}" 2>/dev/null && : >"$f" 2>/dev/null
  return 0
}

sg_append() {
  mkdir -p "${1%/*}" 2>/dev/null || return 1
  printf '%s\n' "${2//$SG_CR/}" >>"$1"
}

# 台帳を行ごとに読み、JSON の object の行だけを出す。読めない行は飛ばして SG_SKIPPED に足す
# (呼び出し元のシェルで数えるため、結果は変数 SG_READ に入れる)。
sg_read() {
  SG_READ=
  [ -f "$1" ] || return 0
  local out
  out=$(jq -cR 'fromjson? // "\u0000" | if type == "object" then . else "\u0000" end' "$1" 2>/dev/null) || return 0
  out=${out//$SG_CR/}
  local line kept=
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$line" = '"\u0000"' ]; then SG_SKIPPED=$((SG_SKIPPED + 1)); else kept+="$line"$'\n'; fi
  done <<<"$out"
  SG_READ=$kept
}

# 台帳の複数のファイルを 1 回の jq で読むための定義。入力は `jq -nR` の inputs (ファイルの行)。
# 結果は {<ファイル名から .jsonl を除いた名前>: [object...], _skipped: n}。
SG_JQ_LOAD='
def sg_load: reduce inputs as $l ({_skipped: 0};
  (input_filename | sub(".*[/\\\\]"; "") | sub("\\.jsonl$"; "")) as $f
  | if ($l | test("^\\s*$")) then .
    else (($l | fromjson?) // null) as $v
      | if ($v | type) == "object" then .[$f] += [$v] else ._skipped += 1 end
    end);
def lastof($a): ($a // []) | last;
'

# 台帳のディレクトリにある、名前の JSONL のうち存在するものを並べる。
sg_files() {
  local dir=$1 name
  shift
  SG_FILES=()
  for name in "$@"; do
    [ -f "$dir/$name.jsonl" ] && SG_FILES+=("$dir/$name.jsonl")
  done
  # ファイルが 1 つも無いと jq -n の inputs が標準入力を読みにいくため、空の入力を必ず渡す。
  SG_FILES+=(/dev/null)
  return 0
}

# jq が出す手順の行を実行する。
#   A<TAB>name<TAB>json  台帳 name.jsonl へ追記     W<TAB>name<TAB>text  ファイル name へ書く
#   O<TAB>text  標準出力   E<TAB>text  標準エラー   S<TAB>n  読めなかった行の件数   X<TAB>n  終了コード
SG_EXIT=0
sg_apply() {
  local dir=$1 plan=$2 kind a b
  plan=${plan//$SG_CR/}
  while IFS=$'\t' read -r kind a b; do
    case $kind in
      A) sg_append "$dir/$a.jsonl" "$b" ;;
      W) mkdir -p "$dir" && printf '%s\n' "$b" >"$dir/$a.tmp.$$" && mv -f "$dir/$a.tmp.$$" "$dir/$a" ;;
      O) printf '%s\n' "$a" ;;
      E) printf '%s\n' "$a" >&2 ;;
      S) [ "${a:-0}" -gt 0 ] 2>/dev/null && printf 'stall-guard: skipped %s unreadable ledger line(s)\n' "$a" >&2 ;;
      X) SG_EXIT=$a ;;
    esac
  done <<<"$plan"
  return 0
}

# sg_line_end <path> <位置> <大きさ>: 位置から大きさまでのうち、最後の改行の直後の位置を出す (書きかけの行を除く)。
# 大きさを測った時点の範囲だけを読むので、測った後の追記で読み終えた位置が行の途中を指すことはない。
# 読むのは末尾 4 MiB まで。その中に改行が無ければ、改行が来るまで位置を進めない。
sg_line_end() {
  local p=$1 from=$2 size=$3 start last part
  [ "$size" -gt "$from" ] || { echo "$from"; return 0; }
  last=$(tail -c +"$size" -- "$p" 2>/dev/null | head -c 1 | od -An -tx1 | tr -d ' \n')
  if [ "$last" = 0a ]; then echo "$size"; return 0; fi
  start=$from
  [ $((size - from)) -gt 4194304 ] && start=$((size - 4194304))
  part=$(tail -c +$((start + 1)) -- "$p" 2>/dev/null | head -c $((size - start)) | tail -n 1 | wc -c)
  part=${part//[!0-9]/}
  if [ "$part" -ge $((size - start)) ]; then echo "$from"; else echo $((size - part)); fi
}

# sg_added <path> <前回の位置> [codex-rollout]: 前回の位置以後に追記された内容を読む。進捗を大きさや更新時刻でなく内容で
# 判断させるため、1 行目に「読み始めた位置<TAB>読み終えた位置<TAB>いまの大きさ」(無ければ空行)、2 行目以降に
# 追記の末尾 (最大 8 項目) を出す。読むのは最後の改行までの完全な行で、書きかけの行は次回に回す。
# 読むのは範囲の末尾 4 MiB の、末尾 40 行 (1 行が大きくても本文を取り出してから各項目を 300 文字に詰める)。
# 会話記録の行 (Claude の message.content、Codex の response_item) は発言・ツールの呼出し・結果の本文に直し、
# 会話記録を含む読み取り範囲では、それ以外の記録 (推論の暗号文・メタデータ) を出さない。
# 会話記録を含まない JSONL やテキストは行をそのまま出す。前回より小さければ作り直されたとみなし先頭から読む。
# jq の program には逆斜線の連続を書かない (Codex の Windows の起動経路で 2 個が 1 個に縮むため)。
sg_added() {
  local p=$1 from=${2:-0} format=${3:-} seen_items=${4:-[]} size end rendered
  size=$(wc -c <"$p" 2>/dev/null) || { echo; return 0; }
  size=${size//[!0-9]/}
  [[ "$from" =~ ^[0-9]+$ ]] && [ "$from" -le "$size" ] || from=0
  end=$(sg_line_end "$p" "$from" "$size")
  if [ "$format" != codex-rollout ]; then printf '%s\t%s\t%s\n' "$from" "$end" "$size"; fi
  if [ "$end" -le "$from" ]; then
    [ "$format" != codex-rollout ] || printf '%s\t%s\t%s\t%s\n' "$from" "$end" "$size" "$seen_items"
    return 0
  fi
  # 窓が行の途中から始まるときは、その断片を捨てる (断片を別の記録として示さないため)。
  local start=$from skip=1
  if [ $((end - from)) -gt 4194304 ]; then start=$((end - 4194304)); skip=2; fi
  rendered=$(tail -c +$((start + 1)) -- "$p" 2>/dev/null | head -c $((end - start)) | tail -n +$skip | tail -n 40 | tr -d '\000' | jq -cRs --arg format "$format" --argjson seen_items "$seen_items" '
    def txt: if type == "string" then . elif type == "array" then map(.text? // empty | strings) | join(" ") else tojson end;
    def flat: .[:2000] | gsub("[[:space:]]+"; " ") | .[:300];
    def cut: txt | flat;
    def msg: (.message | type) == "object" and ((.message.content | type) as $t | $t == "string" or $t == "array");
    def item: .type == "response_item" and (.payload | type) == "object";
    def native_text:
      if type == "string" then . elif type == "array" then map(native_text) | join(" ")
      elif type == "object" then (.text // "") | native_text else "" end;
    def native_item_text:
      if .type == "AgentMessage" then .content | native_text | flat | select(test("[^[:space:]]")) | "[assistant] " + .
      elif .type == "Reasoning" then [.summary_text, .raw_content] | native_text | flat | select(test("[^[:space:]]")) | "[reasoning] " + .
      elif .type == "CommandExecution" then
        (.aggregated_output | native_text | flat) as $output
        | if ($output | test("[^[:space:]]")) then "[result] " + $output
          else .command | native_text | flat | select(test("[^[:space:]]")) | "[tool exec] " + . end
      elif .type == "SubAgentActivity" then empty
      else null end;
    def item_identity:
      (if .type == "response_item" then .payload
       elif .type == "event_msg" and (.payload.type == "item_completed" or .payload.type == "item_started") then .payload.item
       else {} end)
      | if (.id | type) != "string" then null
        elif .type == "AgentMessage" or .type == "message" then "message:" + .id
        elif .type == "Reasoning" or .type == "reasoning" then "reasoning:" + .id
        elif .type == "CommandExecution" then "command:" + .id
        else null end;
    [split("\n")[] | select(length > 0) | {raw: ., v: (fromjson? // null)}] as $rows
    | any($rows[].v | objects; msg or item) as $transcript
    | [$rows[] | .raw as $raw | .v as $v
    | (if ($v | type) == "object" then $v else {} end) as $record
    | (if ($v | type) == "object" and ($v | item) then $v.payload
        | if .type == "message" and .role != "developer" and .role != "system" then "[\(.role)] \(.content | cut)"
          elif .type == "function_call" or .type == "custom_tool_call" then "[tool \(.name)] \((.arguments // .input) | cut)"
          elif .type == "function_call_output" or .type == "custom_tool_call_output" then "[result] \(.output | cut)"
          elif $format == "codex-rollout" and .type == "reasoning" then
            [.summary, .content] | native_text | flat | select(test("[^[:space:]]")) | "[reasoning] " + .
          else empty end
      elif ($v | type) == "object" and ($v | msg) then
        ($v.message.content | if type == "string" then [{type: "text", text: .}] else . end)[]
        | if .type == "text" then "[\($v.message.role // $v.type // "text")] \(.text | cut)"
          elif .type == "tool_use" then "[tool \(.name)] \(.input | cut)"
          elif .type == "tool_result" then "[result] \(.content | cut)"
          else empty end
      elif $format == "codex-rollout" and $record.type == "event_msg"
          and ($record.payload.type == "item_completed" or $record.payload.type == "item_started") then
        $record.payload.item as $native
        | $native | native_item_text | if . == null then $raw | flat else . end
      elif $format == "codex-rollout" and $record.type == "event_msg" and $record.payload.type == "agent_message" then
        "[assistant] \($v.payload.message | cut)"
      elif $format == "codex-rollout" and
          ($record.type == "session_meta" or $record.type == "turn_context"
           or ($record.type == "event_msg" and (["task_started", "task_complete", "turn_complete", "turn_aborted", "token_count", "context_compacted", "user_message", "agent_reasoning"] | index($record.payload.type)) != null)) then empty
      elif $format == "codex-rollout" then $raw | flat
      elif $transcript then empty
      else $raw | flat end) as $text
    | {text: $text, id: (if $format == "codex-rollout" then $record | item_identity else null end),
       native: ($record.type == "event_msg")} ] as $content
    | [$content[] | . as $candidate
        | select(.id == null or (.native | not)
          or (any($content[]; .id == $candidate.id and (.native | not)) | not))
        | del(.native)] as $preferred
    | [($preferred | reduce .[] as $item ({seen: $seen_items, out: []};
          if $item.id != null and any(.seen[]; .id == $item.id and .text == $item.text) then .
          else .out += [$item] | if $item.id != null then .seen += [$item] else . end end) | .out)[-8:][]] as $shown
    # 既存の本文8項目に合わせ、通知したidentityと本文の組だけを直近8件残す。
    | {text: ($shown | map(.text) | join("\n")), items: (($seen_items + [$shown[] | select(.id != null)])[-8:])}' 2>/dev/null) || rendered='{"text":"","items":[]}'
  if [ "$format" = codex-rollout ]; then
    printf '%s\t%s\t%s\t%s\n' "$from" "$end" "$size" "$(jq -c '.items' <<<"$rendered")"
  fi
  jq -r '.text | select(length > 0)' <<<"$rendered"
}

# sg_added_map [--codex-rollout] [--seen-items <JSON>] <key> <path> <前回の位置> ...: {key: {text, end, size, from}} の JSON を出す
# (end・size は読めなければ null)。
sg_added_map() {
  local m='{}' out head format= seen='{}' items
  if [ "${1:-}" = --codex-rollout ]; then format=codex-rollout; shift; fi
  if [ "${1:-}" = --seen-items ]; then seen=$2; shift 2; fi
  while [ $# -ge 3 ]; do
    items=$(jq -c --arg key "$1" '.[$key].items // []' <<<"$seen")
    out=$(sg_added "$2" "$3" "$format" "$items")
    head=${out%%$'\n'*}
    [[ "$out" == *$'\n'* ]] && out=${out#*$'\n'} || out=
    m=$(jq -c --arg k "$1" --arg v "$out" --arg h "$head" \
      '($h | split("\t")) as $fields | ($fields[:3] | map(tonumber? // null)) as $n
       | . + {($k): {text: $v, from: $n[0], end: $n[1], size: $n[2]}}
       | if $fields[3] != null then .[$k].items = ($fields[3] | fromjson) else . end' <<<"$m") || return 1
    shift 3
  done
  printf '%s\n' "$m"
}

# sg_added_jq: sg_added_map の 1 項目を事実の文にする jq の定義。
SG_ADDED_JQ='
def added_fact($a):
  if $a.size == null then "無い"
  elif ($a.text // "") != "" then "前回の確認から追加された内容の末尾"
    + (if $a.size > $a.end then " (書きかけの行は次回に示す)" else "" end) + ":\n"
    + ($a.text | split("\n") | map("    " + .) | join("\n"))
  elif $a.end > $a.from then "前回の確認から \($a.end - $a.from) バイト追記されたが、示せる本文が無い (推論・メタデータなど)"
  elif $a.size > $a.end then "前回の確認から書きかけの 1 行だけが追記された (\($a.size - $a.end) バイト)"
  else "前回の確認から追加なし" end;
'

sg_disable() {
  mkdir -p "$SG_ROOT" && : >"$SG_ROOT/disabled" && echo "stall-guard: disabled ($SG_ROOT/disabled)"
}

sg_main() {
  local cli=claude
  if [ "${1:-}" = --cli ]; then cli=${2:-}; shift 2 || return 0; fi
  case $cli in claude | codex) ;; *) echo "stall-guard: unknown --cli: $cli" >&2; return 1 ;; esac
  local sub=${1:-}
  [ $# -gt 0 ] && shift
  if [ "$sub" = disable ]; then sg_disable; return; fi
  # shellcheck source=/dev/null
  . "$SG_HOOK_DIR/lib/stall-guard-$cli.sh" || return 0
  "${cli}_main" "$sub" "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  sg_main "$@"
  exit $?
fi
