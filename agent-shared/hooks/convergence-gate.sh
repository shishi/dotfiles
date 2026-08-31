#!/usr/bin/env bash
# PreToolUse gate: 収束しない反復を機械的に止める。
#
#  A) 変更を挟まず同じコマンドを repeat_threshold 回目 → deny。
#     「何を変えたから結果が変わるか」を proceed で宣言した場合だけ
#     proceed_ttl の間その反復を許可する。ファイル変更(Write/Edit/apply_patch)
#     はカウンタをリセットするので、編集を挟む正常な red→green 反復は止めない。
#  B) レビュー系 skill の発動はユーザー指示 1 回あたり review_budget 周まで
#     → 超過は deny。自己解除は無い。残指摘の採否と理由を列挙して報告して停止する。
#  C) 同一ファイルへの編集はユーザー指示 1 回あたり churn_free 回まで。
#     超過は deny。rework の宣言(1 ファイル churn_max_rework 回まで、各
#     +churn_step)で延長でき、それも尽きたら報告して停止する。
#     「毎回なにか変えながら同じ場所を永遠にこね続ける」を有限にする層で、
#     多数のファイルへ広がる長い作業は制限しない。
#
# UserPromptSubmit でそのセッションの全カウンタ・全予算をリセットする
# (ユーザーが介入した = human-in-the-loop が回った)。総量の上限は置かない。
#
# カバーしない経路(fail-open 側): session_id の無い入力、このゲートが
# 配線されていないツール(Read 等)、state の手動削除。削除による迂回は
# 規約違反として扱う。
#
# 使い方:
#   引数なし: stdin の hook JSON(PreToolUse / UserPromptSubmit)を判定
#   proceed <command|hash> <理由>: その反復を proceed_ttl の間だけ許可
#   rework <path> <理由>: そのファイルの編集予算を +churn_step(churn_max_rework 回まで)
set -u

repeat_threshold=3
review_budget=2
proceed_ttl=600
churn_free="${CONVERGE_GATE_CHURN_FREE:-12}"
churn_step=4
churn_max_rework=2
# 前回のレビュー以降にこれだけ編集が進んでいれば「同じ作業の再レビュー」では
# なく新しいマイルストーンとみなし、レビュー周回の数え直しを許す
milestone_edits="${CONVERGE_GATE_MILESTONE_EDITS:-15}"

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

cmd_rework() {
  local path="${1:-}" reason="${2:-}" key f count rest
  if [ -z "$path" ] || [ "${#reason}" -lt 10 ]; then
    echo "usage: convergence-gate.sh rework <path> <何が分かった/次の編集で何が変わるか 1 行>" >&2
    exit 2
  fi
  resolve_state_dir ""
  prepare_state_dir || {
    echo "state dir を用意できない: $state_dir" >&2
    exit 1
  }
  key=$(hash_key "$path")
  f="$state_dir/churnok.$key"
  count=0
  [ -f "$f" ] && IFS=$'\t' read -r count rest <"$f"
  case "$count" in "" | *[!0-9]*) count=0 ;; esac
  if [ "$count" -ge "$churn_max_rework" ]; then
    echo "rework の上限(${churn_max_rework} 回)。この反復は自己判断では続行できない。現状・試したこと・選択肢をユーザーへ報告して停止せよ。" >&2
    exit 1
  fi
  printf '%s\t%s\n' "$((count + 1))" "$reason" >"$f" || exit 1
  echo "宣言を記録: このファイルの編集予算 +${churn_step}($((count + 1))/${churn_max_rework})"
}

check_churn() { # $1=path。予算超過なら deny(戻らない)
  local key f okf count ext rest allowed
  key=$(hash_key "$1")
  f="$state_dir/churn.$key"
  count=0
  [ -f "$f" ] && IFS= read -r count <"$f"
  case "$count" in "" | *[!0-9]*) count=0 ;; esac
  count=$((count + 1))
  ext=0
  okf="$state_dir/churnok.$key"
  [ -f "$okf" ] && IFS=$'\t' read -r ext rest <"$okf"
  case "$ext" in "" | *[!0-9]*) ext=0 ;; esac
  allowed=$((churn_free + churn_step * ext))
  if [ "$count" -gt "$allowed" ]; then
    if [ "$ext" -ge "$churn_max_rework" ]; then
      deny "[収束ゲート] 同一ファイルへの編集が延長込みの上限(${allowed} 回)に達した: $1
これ以上の自己解除手段は無い。現状・試したこと・残る選択肢をユーザーへ報告して停止し、指示を待て(ユーザーの次の入力で予算はリセットされる)。"
    fi
    deny "[収束ゲート] 同一ファイルへの編集がユーザー指示 1 回あたりの予算(${allowed} 回)を超えた: $1
同じ場所をこね続ける反復は、毎回変更していても収束の証拠にならない。この反復で何が分かり、次の編集で何が変わるのかを宣言してから再実行せよ(1 ファイル ${churn_max_rework} 回まで、各 +${churn_step} 回):
bash ~/.agent-shared/hooks/convergence-gate.sh rework '$1' '<何が分かった/次の編集で何が変わるか 1 行>'
宣言できないなら、現状・試したこと・選択肢をユーザーへ報告して停止せよ。"
  fi
  echo "$count" >"$f"
  return 0
}

if [ "${1:-}" = "proceed" ]; then
  shift
  cmd_proceed "$@"
  exit 0
fi
if [ "${1:-}" = "rework" ]; then
  shift
  cmd_rework "$@"
  exit 0
fi

input=$(cat)
# 予算(レビュー・churn・editsall)は worktree 単位の共有プールで、session を
# キーにしない。subagent や codex 単独実行が session を替えても同じ予算に当たる。
# session は同一コマンド反復カウンタ(エージェント固有の意味を持つ)だけに使う。
session_raw=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session_raw=""
sess=$(sanitize_session "$session_raw") || sess=""
hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || hook_cwd=""
resolve_state_dir "$hook_cwd"

# --- ユーザー入力 = human-in-the-loop。この worktree の全カウンタ・全予算をリセット ---
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null) || event=""
if [ "$event" = "UserPromptSubmit" ]; then
  if [ -d "$state_dir" ] && [ ! -L "$state_dir" ] && [ -O "$state_dir" ]; then
    find "$state_dir" -maxdepth 1 -type f -delete 2>/dev/null
  fi
  exit 0
fi

# --- B) レビュー反復予算 ---
skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null) || skill=""
case "$skill" in
  review-gate | codex-review | code-review | spec-scope-review | security-review | *:code-review | *:requesting-code-review)
    prepare_state_dir || exit 0
    f="$state_dir/review"
    count=0
    [ -f "$f" ] && IFS= read -r count <"$f"
    case "$count" in "" | *[!0-9]*) count=0 ;; esac
    edits_total=0
    [ -f "$state_dir/editsall" ] && IFS= read -r edits_total <"$state_dir/editsall"
    case "$edits_total" in "" | *[!0-9]*) edits_total=0 ;; esac
    mark=""
    [ -f "$state_dir/reviewmark" ] && IFS= read -r mark <"$state_dir/reviewmark"
    case "$mark" in *[!0-9]*) mark="" ;; esac
    # 前回レビュー以降に十分な実装が進んでいれば、同じ作業の再レビューではなく
    # 新しいマイルストーンなので周回を数え直す
    if [ -n "$mark" ] && [ $((edits_total - mark)) -ge "$milestone_edits" ]; then
      count=0
    fi
    if [ "$count" -ge "$review_budget" ]; then
      deny "[収束ゲート] レビュー反復がユーザー指示 1 回あたりの予算(${review_budget} 周)を超えた。
レビュー指摘は採用命令ではない。指摘を全部飲んで再レビューする反復は、反復のたびに完了条件が遠ざかる規約違反である。
残りの指摘を 1 件ずつ「採用 / 不採用 + 理由 1 行」で列挙してユーザーへ報告し、指示を待て。この上限を自己解除する手段は無い。"
    fi
    echo $((count + 1)) >"$f"
    echo "$edits_total" >"$state_dir/reviewmark"
    exit 0
    ;;
esac

bump_edits() {
  local t=0
  [ -f "$state_dir/editsall" ] && IFS= read -r t <"$state_dir/editsall"
  case "$t" in "" | *[!0-9]*) t=0 ;; esac
  echo $((t + 1)) >"$state_dir/editsall"
}

path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

# --- A) 変更を挟まない同一コマンド反復 ---
if [ -n "$path" ]; then
  # ファイル編集は状態を変える。全セッションのコマンド反復カウンタをリセットし、
  # 同一ファイルの churn を数える
  prepare_state_dir || exit 0
  rm -f "$state_dir"/cnt.* 2>/dev/null
  check_churn "$path"
  bump_edits
  exit 0
fi
[ -n "$cmd" ] || exit 0

case "$cmd" in
  *"*** Begin Patch"* | *apply_patch*)
    prepare_state_dir || exit 0
    rm -f "$state_dir"/cnt.* 2>/dev/null
    while IFS= read -r line; do
      p="${line#\*\*\* Add File: }"
      p="${p#\*\*\* Update File: }"
      if [ -n "$p" ]; then
        check_churn "$p"
        bump_edits
      fi
    done < <(LC_ALL=C grep -E '^\*\*\* (Add|Update) File: ' <<<"$cmd")
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
    deny "[収束ゲート] 何も変えずに同じコマンドの ${count} 回目。結果が変わる根拠が無い。
- 同じ失敗を 2 回見たら、次を打つ前に原因仮説を 1 行で更新せよ
- ${repeat_threshold} 回試して新しい情報が無いなら、続行せず現状・試したこと・選択肢をユーザーへ報告して停止せよ
- ファイルを変更すればカウンタはリセットされる。変更したうえで結果が変わる根拠があるなら、宣言してから再実行せよ($((proceed_ttl / 60)) 分間有効):
bash ~/.agent-shared/hooks/convergence-gate.sh proceed '$h' '<何を変えた/なぜ結果が変わるか 1 行>'"
  fi
fi
echo "$count" >"$f"
exit 0
