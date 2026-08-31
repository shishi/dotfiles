#!/usr/bin/env bash
# PreToolUse gate: テストコードの「追加」を検出し、依頼された結果との対応を
# justify で 1 行宣言するまで deny する。
#
# 過剰かどうかの判断は機械的にできないため、しない。判断はエージェントに
# 残したまま、宣言を transcript に強制的に残すのがこのゲートの目的である。
# 検出パターンは実際に使われているスタック(TS/JS・python・bash・汎用 test
# ディレクトリ)に限定する。検出できない経路(heredoc リダイレクト等)は
# fail-open であり、そこを使った迂回は規約違反として扱う。
#
# 使い方:
#   引数なし: stdin の PreToolUse JSON を判定(Write/Edit/MultiEdit と
#             apply_patch を含む Bash に対応)
#   justify <path> <理由>: <path> へのテスト追加を TTL の間だけ許可
set -u

ttl_seconds=900

# justify はエージェントの sandbox 内、hook 本体は sandbox 外で走る。両者から
# 同じ path で見えて書けるのは作業 repo の .git 配下だけ(/tmp や TMPDIR は
# sandbox 内外で食い違うか read-only)。repo 外の cwd では TMPDIR に落ちるが、
# その場合 justify と hook が別 dir を見て通らないことがある(repo 内で使う前提)。
state_dir=""
resolve_state_dir() { # $1=cwd(空なら PWD)
  local gitdir
  if [ -n "${OVERENG_GATE_STATE_DIR:-}" ]; then
    state_dir="$OVERENG_GATE_STATE_DIR"
    return 0
  fi
  gitdir=$(git -C "${1:-$PWD}" rev-parse --absolute-git-dir 2>/dev/null) || gitdir=""
  if [ -n "$gitdir" ]; then
    state_dir="$gitdir/agent-gates"
  else
    state_dir="${TMPDIR:-/tmp}/agent-gates-${UID:-user}"
  fi
}

# JS/TS のテストブロック(直後に文字列リテラルが続く形だけ。regex.test(str) や
# 散文中の it "..." を誤検出しないよう、先行文字に . と英数字を許さない)、
# python の def test_、ruby/RSpec の行頭 it/describe/context(散文と区別する
# ため行頭限定)。
marker_re='(^|[^[:alnum:]_.$])(it|test|describe)(\.(each|only|skip|todo|concurrent))?[[:space:]]*\([[:space:]]*["'\''`]|^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_|^[[:space:]]*(it|describe|context)[[:space:]]+["'\'']'

hash_key() { # $1=path 文字列(deny メッセージの表記と一字一句同じものを使う)
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

is_test_path() { # $1=path
  local base
  case "$1" in
    */tests/*|tests/*|*/test/*|test/*|*/__tests__/*|__tests__/*|*/spec/*|spec/*) return 0 ;;
  esac
  base="${1##*/}"
  case "$base" in
    *_test.*|*.test.*|*_spec.*|*.spec.*|test_*.*|conftest.py) return 0 ;;
  esac
  return 1
}

marker_count() { # stdin -> マーカー行数
  LC_ALL=C grep -Ec "$marker_re" || true
}

# justify で通せるのはユーザー指示 1 回あたり test_file_budget ファイルまで。
# 予算は worktree 単位の共有プール(session をキーにしない)。subagent や
# codex 単独実行が session を替えても同じ予算に当たり、リセットは
# convergence-gate が UserPromptSubmit で行う。
# 宣言を積み増して「テストを増やす→落ちる→また増やす」を永遠に続ける経路を
# 物理的に塞ぐ。広い正当な作業(複数モジュールへ各 1 テストファイル)は
# この枠内に収まる想定で、超えたら報告して指示を待つ。
test_file_budget="${OVERENG_GATE_FILE_BUDGET:-5}"
# ケース予算はテストブロック(it / test / def test_ 等)の増加数の累計。
# 1 個ずつ足しても一括で足しても同じ数字に当たる
test_case_budget="${OVERENG_GATE_CASE_BUDGET:-20}"
allow_within_budget() { # $1=path $2=マーカー増分。予算内なら exit 0、超過なら deny
  local f key n delta cf cases
  prepare_state_dir || exit 0
  delta="${2:-0}"
  case "$delta" in "" | *[!0-9]*) delta=0 ;; esac
  cf="$state_dir/cases"
  cases=0
  [ -f "$cf" ] && IFS= read -r cases <"$cf"
  case "$cases" in "" | *[!0-9]*) cases=0 ;; esac
  if [ $((cases + delta)) -gt "$test_case_budget" ]; then
    deny_case_budget "$1"
  fi
  f="$state_dir/testbudget"
  key=$(hash_key "$1")
  if [ ! -f "$f" ] || ! LC_ALL=C grep -qx "$key" "$f" 2>/dev/null; then
    n=0
    [ -f "$f" ] && n=$(wc -l <"$f" | tr -d ' ')
    if [ "$n" -ge "$test_file_budget" ]; then
      deny_budget "$1"
    fi
    echo "$key" >>"$f"
  fi
  echo $((cases + delta)) >"$cf"
  exit 0
}

deny_case_budget() { # $1=path
  jq -n --arg r "[過剰テストゲート] ユーザー指示 1 回あたりのテストケース追加予算(${test_case_budget} ブロック)を使い切った: $1 への追加は通せない。
エッジケースは「現実に起こりうる / 壊れると高くつく / 明示的にスコープ内」のどれかを満たすものだけに絞り、それでも超えるなら残りの候補を列挙してユーザーへ報告し、指示を待て。この上限を自己解除する手段は無い。" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

deny_budget() { # $1=path
  jq -n --arg r "[過剰テストゲート] ユーザー指示 1 回あたりのテスト追加予算(${test_file_budget} ファイル)を使い切った: $1 は通せない。
テストを増やす→落ちる→検証をやり直す→また増やす、という反復は、反復のたびに完了条件が遠ざかる規約違反である。
これ以上のテスト追加が本当に依頼された結果の証明に必要なら、追加したい対象と理由を列挙してユーザーへ報告し、指示を待て。この上限を自己解除する手段は無い。" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

has_valid_justification() { # $1=path
  local f epoch rest now
  f="$state_dir/$(hash_key "$1")"
  [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] || return 1
  IFS=$'\t' read -r epoch rest <"$f" || return 1
  case "$epoch" in "" | *[!0-9]*) return 1 ;; esac
  now=$(date +%s) || return 1
  [ $((now - epoch)) -ge 0 ] && [ $((now - epoch)) -le "$ttl_seconds" ]
}

deny() { # $1=path
  local rule
  rule="[過剰テストゲート] テストコードの追加を検出: $1
テストは検証手段であって成果物ではない。依頼された挙動を証明する最小のテストだけ追加する。
- 仮定上の edge case は「現実に起こりうる / 壊れると高くつく / 明示的にスコープ内」のいずれも無ければテストにしない
- レビュー指摘・coverage・網羅感は、それ自体では追加の理由にならない
- 新しいテスト基盤を作るより既存テストの修正・再利用を優先する
- 停止条件: 元の失敗を再現した / 修正がその再現を通った / 直接関係する既存テストが通った / 未確認の具体的リスクが無い — 揃ったら追加をやめる
この追加が依頼された結果の証明に必要なら、次を実行してから同じ書き込みを再実行せよ(path は一字一句このまま):
bash ~/.agents/hooks/overengineering-gate.sh justify '$1' '<依頼された挙動とこのテストの対応を 1 行>'
宣言は $((ttl_seconds / 60)) 分間そのファイルに有効。別経路(heredoc 等)でこのゲートを迂回する書き込みは規約違反である。"
  jq -n --arg r "$rule" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

cmd_justify() {
  local path="${1:-}" reason="${2:-}"
  if [ -z "$path" ] || [ "${#reason}" -lt 10 ]; then
    echo "usage: overengineering-gate.sh justify <path> <依頼された挙動とテストの対応を 1 行>" >&2
    exit 2
  fi
  resolve_state_dir ""
  prepare_state_dir || {
    echo "state dir を用意できない: $state_dir" >&2
    exit 1
  }
  printf '%s\t%s\n' "$(date +%s)" "$reason" >"$state_dir/$(hash_key "$path")" || exit 1
  echo "宣言を記録: $path($((ttl_seconds / 60)) 分間有効)"
}

if [ "${1:-}" = "justify" ]; then
  shift
  cmd_justify "$@"
  exit 0
fi

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || hook_cwd=""
resolve_state_dir "$hook_cwd"

if [ -n "$path" ]; then
  # Write は content(旧値 = 既存ファイル全文)、Edit/MultiEdit は
  # new_string(旧値 = old_string)。増分だけを見るので削除・修正は通る。
  new_content=$(printf '%s' "$input" | jq -r \
    '.tool_input.content // .tool_input.new_string // ([.tool_input.edits[]?.new_string] | join("\n"))' \
    2>/dev/null) || exit 0
  if printf '%s' "$input" | jq -e '.tool_input.content' >/dev/null 2>&1; then
    old_content=""
    [ -f "$path" ] && old_content=$(cat "$path" 2>/dev/null || true)
  else
    old_content=$(printf '%s' "$input" | jq -r \
      '.tool_input.old_string // ([.tool_input.edits[]?.old_string] | join("\n"))' \
      2>/dev/null) || old_content=""
  fi
  new_n=$(marker_count <<<"$new_content")
  old_n=$(marker_count <<<"$old_content")
  gate=0
  [ "$new_n" -gt "$old_n" ] && gate=1
  # 中身がまだ無い新規テストファイル(scaffold)も作成時点で捕まえる
  if [ ! -f "$path" ] && is_test_path "$path"; then gate=1; fi
  [ "$gate" = 1 ] || exit 0
  has_valid_justification "$path" && allow_within_budget "$path" "$((new_n - old_n))"
  deny "$path"
fi

if [ -n "$cmd" ]; then
  case "$cmd" in
    *"*** Begin Patch"* | *apply_patch*) ;;
    *) exit 0 ;;
  esac
  added=$(LC_ALL=C grep -E '^\+' <<<"$cmd" | sed 's/^+//')
  removed=$(LC_ALL=C grep -E '^-' <<<"$cmd" | sed 's/^-//')
  new_n=$(marker_count <<<"$added")
  old_n=$(marker_count <<<"$removed")
  gate_path=""
  while IFS= read -r line; do
    p="${line#\*\*\* Add File: }"
    if is_test_path "$p"; then
      gate_path="$p"
      break
    fi
  done < <(LC_ALL=C grep -E '^\*\*\* Add File: ' <<<"$cmd")
  if [ -z "$gate_path" ] && [ "$new_n" -gt "$old_n" ]; then
    # マーカー増分をファイル単位に厳密帰属させず、パッチ先頭の対象 path を
    # 宣言キーにする(deny メッセージがその path を提示するので一致は保てる)
    gate_path=$(LC_ALL=C grep -E '^\*\*\* (Add|Update) File: ' <<<"$cmd" | head -1 | sed 's/^\*\*\* \(Add\|Update\) File: //')
    [ -n "$gate_path" ] || gate_path="apply_patch"
  fi
  [ -n "$gate_path" ] || exit 0
  delta=$((new_n - old_n))
  [ "$delta" -ge 0 ] || delta=0
  has_valid_justification "$gate_path" && allow_within_budget "$gate_path" "$delta"
  deny "$gate_path"
fi

exit 0
