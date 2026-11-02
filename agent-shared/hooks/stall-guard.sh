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
