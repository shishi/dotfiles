#!/usr/bin/env bash
# PreToolUse gate: 変更を挟まない同一コマンド反復を警告する。
#
# 同じコマンドを repeat_threshold 回実行したら additionalContext を返す。
# コマンドの成否は判定せず、続行や停止の判断はエージェントに残す。
# proceed の宣言は proceed_ttl の間そのコマンドの警告を抑制する。
# Claude の Write/Edit・Bash 内の apply_patch と Codex の直接 apply_patch は
# 全セッションの反復カウンタをリセットする。
# UserPromptSubmit は worktree のカウンタと宣言をリセットする。
#
# カバーしない経路(fail-open 側): session_id の無い入力、このゲートが
# 配線されていないツール(Read 等)、state の手動削除。削除による迂回は
# 規約違反として扱う。
#
# 使い方:
#   引数なし: stdin の hook JSON(PreToolUse / UserPromptSubmit)を判定
#   proceed <command|hash> <理由>: そのコマンドの警告を proceed_ttl の間だけ抑制
set -u

repeat_threshold=3
proceed_ttl=600

# エージェントの sandbox 内(proceed)と sandbox 外(hook)の両方から同じ path で
# 見える場所は作業 repo の .git 配下だけ。
state_dir=""
resolve_state_dir() { # $1=cwd(空なら PWD)
  local gitdir
  if [ -n "${CONVERGE_GATE_STATE_DIR:-}" ]; then
    state_dir="$CONVERGE_GATE_STATE_DIR"
    return 0
  fi
  gitdir=$(git -C "${1:-$PWD}" rev-parse --absolute-git-dir 2>/dev/null) || gitdir=""
  if [ -n "$gitdir" ]; then
    state_dir="$gitdir/agent-gates"
  else
    state_dir="${TMPDIR:-/tmp}/agent-gates-${UID:-user}"
  fi
}

hash_key() { # $1=文字列
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

prepare_state_dir() {
  umask 077
  [ -e "$state_dir" ] || mkdir -p "$state_dir" 2>/dev/null || return 1
  [ -d "$state_dir" ] && [ ! -L "$state_dir" ] && [ -O "$state_dir" ] || return 1
  chmod 700 "$state_dir" 2>/dev/null || return 1
}

sanitize_session() { # $1=session id -> stdout(不正なら空)
  case "$1" in
    "" | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ] || return 1
  printf '%s' "$1"
}

warn() { # $1=警告
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
}

cmd_proceed() {
  local target="${1:-}" reason="${2:-}" key
  if [ -z "$target" ] || [ "${#reason}" -lt 10 ]; then
    echo "usage: convergence-gate.sh proceed <command|hash> <新しい情報/結果が変わる根拠を 1 行>" >&2
    exit 2
  fi
  resolve_state_dir ""
  prepare_state_dir || {
    echo "state dir を用意できない: $state_dir" >&2
    exit 1
  }
  if printf '%s' "$target" | LC_ALL=C grep -Eq '^[0-9a-f]{64}$'; then
    key="$target"
  else
    key=$(hash_key "$target")
  fi
  printf '%s\t%s\n' "$(date +%s)" "$reason" >"$state_dir/ok.$key" || exit 1
  echo "宣言を記録: $((proceed_ttl / 60)) 分間このコマンドの反復警告を抑制"
}

has_valid_proceed() { # $1=cmd hash
  local f epoch rest now
  f="$state_dir/ok.$1"
  [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] || return 1
  IFS=$'\t' read -r epoch rest <"$f" || return 1
  case "$epoch" in "" | *[!0-9]*) return 1 ;; esac
  now=$(date +%s) || return 1
  [ $((now - epoch)) -ge 0 ] && [ $((now - epoch)) -le "$proceed_ttl" ]
}

if [ "${1:-}" = "proceed" ]; then
  shift
  cmd_proceed "$@"
  exit 0
fi
input=$(cat)
# session は同一コマンド反復カウンタに使う。
session_raw=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session_raw=""
sess=$(sanitize_session "$session_raw") || sess=""
hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || hook_cwd=""
resolve_state_dir "$hook_cwd"

# --- ユーザー入力でこの worktree のカウンタと宣言をリセット ---
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null) || event=""
if [ "$event" = "UserPromptSubmit" ]; then
  if [ -d "$state_dir" ] && [ ! -L "$state_dir" ] && [ -O "$state_dir" ]; then
    find "$state_dir" -maxdepth 1 -type f -delete 2>/dev/null
  fi
  exit 0
fi

path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

# --- 変更を挟まない同一コマンド反復 ---
if [ -n "$path" ]; then
  # ファイル編集は状態を変える。全セッションの反復カウンタをリセットする
  prepare_state_dir || exit 0
  rm -f "$state_dir"/cnt.* 2>/dev/null
  exit 0
fi
[ -n "$cmd" ] || exit 0

case "$cmd" in
  *"*** Begin Patch"* | *apply_patch*)
    prepare_state_dir || exit 0
    rm -f "$state_dir"/cnt.* 2>/dev/null
    exit 0
    ;;
esac

[ -n "$sess" ] || exit 0
prepare_state_dir || exit 0
h=$(hash_key "$cmd")
f="$state_dir/cnt.$sess.$h"
count=0
[ -f "$f" ] && IFS= read -r count <"$f"
case "$count" in "" | *[!0-9]*) count=0 ;; esac
count=$((count + 1))
if [ "$count" -ge "$repeat_threshold" ]; then
  if ! has_valid_proceed "$h"; then
    warn "[収束ゲート] 観測されたファイル変更を挟まない同じコマンドの ${count} 回目。
この hook はコマンドの成否や失敗の同一性を判定しない。新しい情報・外部状態の変化があるか評価し、同じ失敗が続いているなら原因仮説を更新せよ。
${repeat_threshold} 回試して新しい情報が無いなら、現状・試したこと・選択肢をユーザーへ報告して停止せよ。
ファイル編集で反復カウンタはリセットされる。続行の根拠があるなら、次の宣言でこのコマンドの警告を $((proceed_ttl / 60)) 分間抑制できる:
bash ~/.agent-shared/hooks/convergence-gate.sh proceed '$h' '<新しい情報/結果が変わる根拠を 1 行>'"
  fi
fi
echo "$count" >"$f"
exit 0
