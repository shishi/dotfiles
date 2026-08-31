#!/usr/bin/env bash
# PreToolUse gate: 収束しない反復を機械的に止める。
#
#  A) 変更を挟まず同じコマンドを repeat_threshold 回目 → deny。
#     「何を変えたから結果が変わるか」を proceed で宣言した場合だけ
#     proceed_ttl の間その反復を許可する。ファイル変更(Write/Edit/apply_patch)
#     はカウンタをリセットするので、編集を挟む正常な red→green 反復は止めない。
#  B) レビュー系 skill の発動は 1 セッション review_budget 周まで → 超過は deny。
#     自己解除は無い。残指摘の採否と理由を列挙してユーザーへ報告して停止する。
#
# カバーしない経路(fail-open 側): session_id の無い入力、単一の codex exec
# 内部で完結する反復、state の手動削除。削除による迂回は規約違反として扱う。
#
# 使い方:
#   引数なし: stdin の PreToolUse JSON を判定
#   proceed <command|hash> <理由>: その反復を proceed_ttl の間だけ許可
set -u

repeat_threshold=3
review_budget=2
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

deny() { # $1=理由
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

cmd_proceed() {
  local target="${1:-}" reason="${2:-}" key
  if [ -z "$target" ] || [ "${#reason}" -lt 10 ]; then
    echo "usage: convergence-gate.sh proceed <command|hash> <何を変えた/なぜ結果が変わるか 1 行>" >&2
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
  echo "宣言を記録: $((proceed_ttl / 60)) 分間この反復を許可"
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
session_raw=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
sess=$(sanitize_session "$session_raw") || exit 0
hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || hook_cwd=""
resolve_state_dir "$hook_cwd"

# --- B) レビュー反復予算 ---
skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null) || skill=""
case "$skill" in
  review-gate | codex-review | code-review | spec-scope-review | security-review | *:code-review)
    prepare_state_dir || exit 0
    f="$state_dir/review.$sess"
    count=0
    [ -f "$f" ] && IFS= read -r count <"$f"
    case "$count" in "" | *[!0-9]*) count=0 ;; esac
    if [ "$count" -ge "$review_budget" ]; then
      deny "[収束ゲート] レビュー反復が 1 セッションの予算(${review_budget} 周)を超えた。
レビュー指摘は採用命令ではない。指摘を全部飲んで再レビューする反復は、反復のたびに完了条件が遠ざかる規約違反である。
残りの指摘を 1 件ずつ「採用 / 不採用 + 理由 1 行」で列挙してユーザーへ報告し、指示を待て。この上限を自己解除する手段は無い。"
    fi
    echo $((count + 1)) >"$f"
    exit 0
    ;;
esac

path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

# --- A) 変更を挟まない同一コマンド反復 ---
if [ -n "$path" ]; then
  # ファイル編集は状態を変える。反復カウンタをリセットする
  rm -f "$state_dir/cnt.$sess."* 2>/dev/null
  exit 0
fi
[ -n "$cmd" ] || exit 0

case "$cmd" in
  *"*** Begin Patch"* | *apply_patch*)
    rm -f "$state_dir/cnt.$sess."* 2>/dev/null
    exit 0
    ;;
esac

prepare_state_dir || exit 0
h=$(hash_key "$cmd")
f="$state_dir/cnt.$sess.$h"
count=0
[ -f "$f" ] && IFS= read -r count <"$f"
case "$count" in "" | *[!0-9]*) count=0 ;; esac
count=$((count + 1))
if [ "$count" -ge "$repeat_threshold" ]; then
  if ! has_valid_proceed "$h"; then
    deny "[収束ゲート] 何も変えずに同じコマンドの ${count} 回目。結果が変わる根拠が無い。
- 同じ失敗を 2 回見たら、次を打つ前に原因仮説を 1 行で更新せよ
- ${repeat_threshold} 回試して新しい情報が無いなら、続行せず現状・試したこと・選択肢をユーザーへ報告して停止せよ
- ファイルを変更すればカウンタはリセットされる。変更したうえで結果が変わる根拠があるなら、宣言してから再実行せよ($((proceed_ttl / 60)) 分間有効):
bash ~/.agents/hooks/convergence-gate.sh proceed '$h' '<何を変えた/なぜ結果が変わるか 1 行>'"
  fi
fi
echo "$count" >"$f"
exit 0
