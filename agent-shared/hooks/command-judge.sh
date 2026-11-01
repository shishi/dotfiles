#!/usr/bin/env bash
# Bash 実行前に、コマンドを独立した判定役の AI に判定させる。判定基準は command-judge-prompt.md にあり、
# エージェント自身の作業を続けられなくする操作と、外部へ投稿する本文をファイルから読ませる操作を止める。
#
#   command-judge.sh [--cli claude|codex] --record-prompt   UserPromptSubmit: 利用者の最新メッセージを保存する
#   command-judge.sh [--cli claude|codex]                   PreToolUse(Bash): 判定して該当すれば止める
#
# コマンドの語を照合したり構文解析したりはしない。何が起きるかの判断は判定役に任せ、
# このスクリプトはコマンド・作業エージェントが述べた目的・利用者の最新メッセージを渡して結果を適用する。
#
# 判定できないときも黙って通さない。判定役を動かせない状態 (codex が無い、ログイン切れ等) は
# 全コマンドに共通なので、利用者に警告して通す。止めると、ガード自身がエージェントの作業を止めてしまう。
# 判定役は動いたがそのコマンドの結果を得られないときは、Claude は利用者に確認させ、Codex は止める
# (Codex の PreToolUse は "ask" を受け付けず、hook の失敗としてコマンドを通すため)。
set -o pipefail

cli=claude
mode=judge
bad_args=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --cli) cli=${2:-}; shift; [ "$#" -gt 0 ] && shift ;;
    --record-prompt) mode=record; shift ;;
    *) bad_args="未知の引数 $1"; shift ;;
  esac
done
case "$cli" in claude|codex) ;; *) bad_args="--cli の値 '$cli' が claude でも codex でもない"; cli=claude ;; esac

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
state_dir="${COMMAND_JUDGE_STATE_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/command-judge-${UID:-user}}"
safe_ttl_seconds=86400
judge_timeout_seconds=25
# 判定役が失敗したときに、判定役そのものが動くかを確かめる問いの締切。実測では約 4 秒で答える。
probe_timeout_seconds=12
# 判定役が問いにも答えなかったら、この間は判定を試さずに警告して通す。止まっている判定役を毎回待たせないため。
down_retry_minutes=1
notice_interval_minutes=10

json_string() {
  if command -v jq >/dev/null 2>&1; then
    jq -Rn --arg s "$1" '$s'
  else
    # jq が無いときだけ使う。メッセージは固定文なので最小限のエスケープで足りる。
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\r\t' '   ')"
  fi
}

decide() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
    "$1" "$(json_string "$2")"
  exit 0
}

# 同じ原因の警告は notice_interval_minutes に 1 回へ間引く。自分の状態ディレクトリを確かめられなければ毎回出す
# (共有の /tmp で他人が置いた symlink を書き換えないため)。
warn() {
  local stamp="$state_dir/notice-$cli-$1"
  if [ -d "$state_dir" ] && [ ! -L "$state_dir" ] && [ -O "$state_dir" ] && [ ! -L "$stamp" ]; then
    [ -n "$(find "$stamp" -mmin -"$notice_interval_minutes" 2>/dev/null)" ] && exit 0
    : >"$stamp" 2>/dev/null
  fi
  printf '{"systemMessage":%s}\n' "$(json_string "[command-judge] $2")"
  exit 0
}

# 判定役を動かせない: 警告して通す。
unjudged() {
  warn "$1" "$2ため、コマンドを判定せずに通した。直すまで、再起動などエージェント自身の作業を止める操作や、本文をファイルで渡す投稿も止まらない。"
}

# このコマンドだけ判定結果を得られない: Claude は確認、Codex は止める。
undecided() {
  if [ "$cli" = codex ]; then
    decide deny "危険な操作かを判定できなかったため止めた: $1。一時的な失敗のこともあるので、まず同じコマンドを 1 回実行し直してよい。続けて止まるなら、判定しやすい形 (短く、目的が分かる形) に分けるか、利用者に実行を依頼すること"
  fi
  decide ask "危険な操作かを判定できなかったため、実行してよいか確認する: $1"
}

# 判定役を codex exec で動かす。標準入力を問いとして渡し、答えを標準出力に出す。
run_codex() {
  env -u OPENAI_BASE_URL -u OPENAI_API_KEY -u CODEX_API_KEY COMMAND_JUDGE_ACTIVE=1 \
    "$py_bin" -I "$hook_dir/lib/run-judge.py" "$1" "$judge_cwd" \
    codex exec --ignore-user-config --ephemeral --ignore-rules -s read-only --skip-git-repo-check \
    -m gpt-6-luna -c model_reasoning_effort=high -c approval_policy=never -c project_doc_max_bytes=0 \
    --disable shell_tool --disable unified_exec --disable view_image --disable apps --disable plugins \
    -c 'web_search="disabled"' -
}

# このコマンドの判定結果を得られなかった。判定役が簡単な問いに答えるかを確かめ、答えなければ
# ログイン切れ・利用枠切れ・通信断など全コマンドに共通の障害として警告して通す。答えるなら原因は
# このコマンドにあるので、書き換えや再実行を含めて判定できるまで undecided にする。
judge_failed() {
  local answer
  answer=$(printf 'Reply with exactly: OK' | run_codex "$probe_timeout_seconds" 2>/dev/null) &&
    [ "$(printf '%s' "$answer" | tr -d '[:space:]')" = OK ] && undecided "$1"
  # 判定と問いを待った後の時刻を書く。hook を始めた時刻だと、待った分だけ判定を省く時間が短くなる。
  date +%s >"$down_stamp" 2>/dev/null
  unjudged judge-down "判定役の codex exec が簡単な問いにも答えない (直前の失敗: $1。codex login status・利用枠・通信を確認すること)"
}

prepare_state_dir() {
  umask 077
  mkdir -p "$state_dir/prompts" "$state_dir/safe" "$state_dir/judge-cwd" 2>/dev/null || return 1
  [ -d "$state_dir" ] && [ ! -L "$state_dir" ] && [ -O "$state_dir" ] || return 1
  chmod 700 "$state_dir" 2>/dev/null || return 1
}

valid_session() {
  case "$1" in ""|*[!A-Za-z0-9._-]*) return 1 ;; esac
  [ "${#1}" -le 128 ]
}

# 一時ファイルに書いてから置き換え、読み手が書きかけの内容を見ないようにする。
write_atomic() {
  local path=$1 tmp
  tmp=$(mktemp "$state_dir/.tmp.XXXXXX") || return 1
  if cat >"$tmp" && chmod 600 "$tmp" && mv -f -- "$tmp" "$path"; then
    return 0
  fi
  rm -f -- "$tmp" 2>/dev/null
  return 1
}

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    "$py_bin" -I -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  fi
}

record_failed() {
  printf '{"systemMessage":%s}\n' "$(json_string "[command-judge] 利用者のメッセージを記録できなかった ($1)。$2")"
  exit 0
}

# python は Windows の Microsoft Store の別名のように、見つかっても起動できないことがあるため、起動できるものを選ぶ。
find_python() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -I -c '' >/dev/null 2>&1; then
      py_bin=$candidate
      return 0
    fi
  done
  return 1
}

# 秘密情報らしき文字列があれば 0、無ければ 1、gitleaks が無い・失敗したら 2。
has_secret() {
  command -v gitleaks >/dev/null 2>&1 || return 2
  gitleaks stdin --no-banner --redact --exit-code 3 -l error >/dev/null 2>&1
  case $? in 0) return 1 ;; 3) return 0 ;; *) return 2 ;; esac
}

if [ "$mode" = record ]; then
  # 判定役自身の Codex セッションの入力は記録しない。
  [ -z "${COMMAND_JUDGE_ACTIVE:-}" ] || exit 0
  blocked="このターンは、依頼した再起動などの操作も判定役が依頼として扱えず止まる。"
  command -v jq >/dev/null 2>&1 || record_failed "jq が見つからない" "$blocked"
  input=$(cat)
  session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session=""
  valid_session "$session" || record_failed "セッション ID を読めなかった" "$blocked"
  prepare_state_dir || record_failed "状態ディレクトリ $state_dir を用意できなかった" "$blocked"
  # 先に前のメッセージを消す。記録に失敗しても、前のターンの依頼を今の依頼として使わないため。
  prompt_path="$state_dir/prompts/$session"
  if ! rm -f -- "$prompt_path" 2>/dev/null; then
    { : >"$prompt_path"; } 2>/dev/null && record_failed "前のメッセージを消せず、空にした" "$blocked"
    record_failed "前のメッセージを消せなかった" "前のターンの依頼が、このターンの依頼として判定役に渡る可能性がある。$prompt_path を消すこと。"
  fi
  # 別のエージェントが委譲で起動したセッションの入力は、利用者の依頼ではないので記録しない。
  [ -z "${AGENT_DELEGATED_SESSION:-}" ] || exit 0
  prompt=$(printf '%s' "$input" | jq -j '.prompt // ""' 2>/dev/null)
  # Claude のセッションでは、利用者のメッセージは判定役 (OpenAI) へ初めて渡る。秘密情報らしき文字列を含むなら保存しない。
  omitted=""
  if [ "$cli" = claude ]; then
    printf '%s' "$prompt" | has_secret
    case $? in
      0) omitted="秘密情報らしき文字列を含む" ;;
      2) omitted="gitleaks で秘密情報を検査できない" ;;
    esac
    [ -z "$omitted" ] || prompt="(利用者のメッセージは${omitted}ため省略した)"
  fi
  printf '%s' "$prompt" | write_atomic "$prompt_path" || record_failed "書き込みに失敗した" "$blocked"
  # gitleaks を使えないときは、実行前の判定でも検査できず「判定せずに通した」と警告するので、ここでは知らせない。
  case "$omitted" in
    ""|gitleaks*) ;;
    *) record_failed "${omitted}ため、判定役へ渡さない" "$blocked" ;;
  esac
  exit 0
fi

# 判定役の codex がツールを使おうとしても、判定の連鎖を起こさない (判定役はツールを無効にして起動する)。
[ -z "${COMMAND_JUDGE_ACTIVE:-}" ] || decide deny "判定役はコマンドを実行しない"

[ -z "$bad_args" ] || unjudged bad-args "hook の登録の引数が正しくない ($bad_args)"
command -v jq >/dev/null 2>&1 || unjudged no-jq "jq が見つからない"
find_python || unjudged no-python "起動できる python が見つからない"

input=$(cat)
# Codex は argv 配列や cmd の欄で渡すことがあるため、引用した 1 行のコマンドに直して判定役へ渡す。
command=$(printf '%s' "$input" | jq -ej '.tool_input | (.command // .cmd) |
  if type == "array" then map(tostring) | @sh elif type == "string" then . else error end' 2>/dev/null) ||
  unjudged input "フックの入力からコマンドを読めなかった"
[ -n "$command" ] || exit 0
purpose=$(printf '%s' "$input" | jq -j '.tool_input.description // "" | tostring' 2>/dev/null) || purpose=""
[ -n "$purpose" ] || purpose="(not provided)"
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session=""

prepare_state_dir || unjudged state-dir "状態ディレクトリ $state_dir を安全に用意できなかった"

# 同じ文字列でもシェルで意味が変わるため、判定役に渡し、キャッシュの鍵にも含める。
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) [ "$cli" = codex ] && shell="PowerShell (Windows)" || shell="Git Bash (Windows)" ;;
  *) shell="POSIX シェル ($(uname -s 2>/dev/null))" ;;
esac
shell="$shell / エージェント: $cli"

# 判定基準を変えたら、それまでの安全判定は使わない。目的の説明が変われば判定役が得る情報も変わるため鍵に含める。
# 利用者のメッセージは含めない: 安全と判定したものは、利用者の依頼に関係なく安全と判定している。
key=$({ cat "$hook_dir/command-judge-prompt.md" && printf '\0%s\0%s\0%s' "$shell" "$command" "$purpose"; } | hash_stdin) &&
  [ -n "$key" ] || unjudged hash "判定のキャッシュの鍵を計算できなかった"
safe_path="$state_dir/safe/$key"
now=$(date +%s)
if [ -f "$safe_path" ] && [ ! -L "$safe_path" ] && IFS= read -r cached_at <"$safe_path"; then
  case "$cached_at" in
    ""|*[!0-9]*) ;;
    *) [ $((now - cached_at)) -ge 0 ] && [ $((now - cached_at)) -le "$safe_ttl_seconds" ] && exit 0 ;;
  esac
fi

user_message="(none)"
if valid_session "$session" && [ -f "$state_dir/prompts/$session" ] && [ ! -L "$state_dir/prompts/$session" ]; then
  user_message=$(cat "$state_dir/prompts/$session") || user_message="(none)"
  [ -n "$user_message" ] || user_message="(none)"
fi

# 節の区切りを入力から推測できないようにし、データ側から節を閉じて指示を足せないようにする。
nonce=$(od -An -tx1 -N8 /dev/urandom 2>/dev/null | tr -d ' \n')
[ -n "$nonce" ] || nonce="$now$$$RANDOM"
section() {
  printf '\n<<<%s %s>>>\n%s\n<<<END %s %s>>>\n' "$1" "$nonce" "$2" "$1" "$nonce"
}
data=$(section SHELL "$shell" && section COMMAND "$command" && section PURPOSE "$purpose")

# Claude のセッションでは、コマンドは別の提供元 (OpenAI) へ初めて渡る。秘密情報らしき文字列を含むなら送らない。
# 利用者のメッセージは記録時に検査済み。Codex のセッションでは同じ内容が既に Codex のモデルに渡っている。
if [ "$cli" = claude ]; then
  printf '%s' "$data" | has_secret
  case $? in
    0) decide ask "コマンドか目的の説明に秘密情報らしき文字列があり、判定役 (codex) へ送らなかった。実行してよいか確認する" ;;
    2) unjudged gitleaks "送信前の秘密情報の検査 (gitleaks) を実行できない" ;;
  esac
fi
data="$data$(section USER "$user_message")"

# 判定役は両 CLI 共通で codex exec にする。Claude Desktop から起動した子の claude -p は認証できないため。
# モデルは応答時間を優先して gpt-6-luna にし、推論は high にする (low では変数を経由した再起動を見逃した)。
# 送信先は既定の OpenAI に固定し (--ignore-user-config で config.toml の接続先も読まない)、認証は利用者が
# codex login で選んだもの (CODEX_HOME の auth.json) だけを使う。環境変数の API キーへは切り替えない。
judge_cwd="$state_dir/judge-cwd"
down_stamp="$state_dir/judge-down-$cli"
# 経過は秒で比べる (BSD の find -mmin は分に切り上げるため、1 分以内の判定に使えない)。
if [ -f "$down_stamp" ] && [ ! -L "$down_stamp" ] && IFS= read -r down_at <"$down_stamp"; then
  case "$down_at" in
    ""|*[!0-9]*) ;;
    *) [ $((now - down_at)) -ge 0 ] && [ $((now - down_at)) -lt $((down_retry_minutes * 60)) ] &&
      unjudged judge-down "判定役の codex exec が直前の確認で簡単な問いにも答えなかった (codex login status・利用枠・通信を確認すること)" ;;
  esac
fi
output=$({ cat "$hook_dir/command-judge-prompt.md" && printf '%s' "$data"; } | run_codex "$judge_timeout_seconds")
status=$?
case "$status" in
  0) ;;
  124) judge_failed "判定役が ${judge_timeout_seconds} 秒以内に答えなかった" ;;
  127) unjudged no-codex "判定役に使う codex が見つからない" ;;
  *) judge_failed "判定役の codex exec が終了コード $status で失敗した" ;;
esac

verdict=$(printf '%s' "$output" | jq -R -s -c '
  split("\n") | map(fromjson? | select(type == "object" and
    ([.danger, .user_requested, .body_from_file] | all(type == "boolean")))) | last // empty
' 2>/dev/null)
[ -n "$verdict" ] || judge_failed "判定役の出力から判定結果の JSON を読み取れなかった"

reason=$(jq -r '.reason // "" | tostring | sub("[。.[:space:]]+$"; "")' <<<"$verdict")
if [ "$(jq -r .body_from_file <<<"$verdict")" = true ]; then
  decide deny "外部へ投稿する本文を、実行前からあるファイルから読ませているため止めた: ${reason}。sandbox の有無で一時ディレクトリが変わると、同じパスで別の残骸ファイルが読まれても投稿は失敗しない。本文をコマンドの中に書いて標準入力から渡し (パスには - を指定)、再実行すること"
fi
danger=$(jq -r .danger <<<"$verdict")
if [ "$danger" = false ]; then
  # 利用者のメッセージに関係なく安全と判定したものだけを再利用する。
  printf '%s\n' "$now" | write_atomic "$safe_path" || true
  exit 0
fi
[ "$(jq -r .user_requested <<<"$verdict")" = true ] && exit 0
decide deny "エージェント自身の作業を続けられなくなる操作と判定したため止めた: ${reason}。必要な操作なら、利用者にこのターンで明示的に依頼してもらってから実行し直すこと"
