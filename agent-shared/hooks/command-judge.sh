#!/usr/bin/env bash
# ツール実行前に、操作を独立した判定役の AI に判定させる。判定基準は command-judge-prompt.md にあり、
# エージェント自身の作業を続けられなくする操作、外部へ投稿する本文をファイルから読ませる操作、
# 処理を根拠のない短い上限で打ち切らせる操作を止め、
# 外部へ軽微でなく取り返しのつかない影響を与える操作や通常の push は、許可が無ければ実行させない。
#
#   command-judge.sh [--cli claude|codex] --record-prompt   UserPromptSubmit: 利用者の発言と会話文脈を保存する
#   command-judge.sh [--cli claude|codex]                   PreToolUse: 判定して該当すれば止める
#
# コマンドの語を照合したり構文解析したりはしない。何が起きるかの判断は判定役に任せ、
# このスクリプトは操作の分類を先に行い、必要な場合だけ会話と承認を照合する。
#
# 判定できないときも黙って通さない。判定役を動かせない状態 (codex が無い、ログイン切れ等) は
# 全コマンドに共通なので、利用者に警告して通す。止めると、ガード自身がエージェントの作業を止めてしまう。
# 判定役は動いたがそのコマンドの結果を得られないときは、Claude は利用者に確認させ、Codex は止める
# (Codex の PreToolUse は "ask" を受け付けず、hook の失敗としてコマンドを通すため)。
#
# ${XDG_STATE_HOME:-$HOME/.local/state}/command-judge/disabled があれば、hook の登録を残したまま何もせずに通す。
# 消せば再び判定する。
set -o pipefail

[ -e "${XDG_STATE_HOME:-$HOME/.local/state}/command-judge/disabled" ] && exit 0

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
# 承認とその後の撤回を欠かさないよう、同じセッションの履歴は時刻・件数・長さで切らない。
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
  warn "$1" "$2ため、操作を判定せずに通した。直すまで、再起動などエージェント自身の作業を止める操作、本文をファイルで渡す投稿、根拠のない短い上限での打ち切り、許可の無い push などの外部への操作も止まらない。"
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
    codex exec --ignore-user-config -c 'openai_base_url=""' --ephemeral --ignore-rules -s read-only --skip-git-repo-check \
    -m gpt-6.1-sol -c model_reasoning_effort=medium -c approval_policy=never -c project_doc_max_bytes=0 \
    -c "model_instructions_file=$(json_string "$hook_dir/command-judge-role.md")" -c skills.include_instructions=false \
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
  mkdir -p "$state_dir/prompts" "$state_dir/permissions" "$state_dir/safe" "$state_dir/judge-cwd" 2>/dev/null || return 1
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
  blocked="このメッセージは判定役に渡らないため、このメッセージで依頼・許可した再起動や push などの操作は、許可の無い操作として扱われる (Claude では確認、Codex では止まる)。"
  lost="このメッセージとそれまでのメッセージで依頼・許可した再起動や push などの操作も、許可の無い操作として扱われる (Claude では確認、Codex では止まる)。必要なら改めて依頼・許可すること。"
  command -v jq >/dev/null 2>&1 || record_failed "jq が見つからない" "$blocked"
  input=$(cat)
  session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session=""
  valid_session "$session" || record_failed "セッション ID を読めなかった" "$blocked"
  prepare_state_dir || record_failed "状態ディレクトリ $state_dir を用意できなかった" "$blocked"
  # メッセージを 1 行 1 件の JSON で残す。書き込みに失敗したら履歴ごと消す:
  # 新しいメッセージを欠いた古い履歴を今の依頼として使わないため。
  prompt_path="$state_dir/prompts/$session"
  previous=""
  if [ -f "$prompt_path" ] && [ ! -L "$prompt_path" ]; then
    previous=$(cat -- "$prompt_path" 2>/dev/null) || previous=""
  fi
  if ! rm -f -- "$prompt_path" 2>/dev/null; then
    { : >"$prompt_path"; } 2>/dev/null && record_failed "前のメッセージを消せず、空にした" "$lost"
    record_failed "前のメッセージを消せなかった" "前のメッセージが、このターンの依頼として判定役に渡る可能性がある。$prompt_path を消すこと。"
  fi
  # 別のエージェントが委譲で起動したセッションの入力は、利用者の依頼ではないので記録しない。
  [ -z "${AGENT_DELEGATED_SESSION:-}" ] || exit 0
  prompt=$(printf '%s' "$input" | jq -j '.prompt // ""' 2>/dev/null)
  assistant_context=""
  if find_python; then
    assistant_context=$(printf '%s' "$input" | "$py_bin" -I "$hook_dir/lib/command-judge-context.py" 2>/dev/null)
    case $? in 0) ;; *) assistant_context="" ;; esac
  fi
  # Claude のセッションでは、利用者のメッセージは判定役 (OpenAI) へ初めて渡る。秘密情報らしき文字列を含むなら保存しない。
  omitted=""
  if [ "$cli" = claude ]; then
    printf '%s' "$prompt" | has_secret
    case $? in
      0) omitted="秘密情報らしき文字列を含む" ;;
      2) omitted="gitleaks で秘密情報を検査できない" ;;
    esac
    # 省略したときは前の履歴も消す。省略したメッセージが前の許可を撤回しているかもしれないため。
    if [ -n "$omitted" ]; then
      prompt="(利用者のメッセージは${omitted}ため省略した)"
      previous=""
      assistant_context=""
    else
      printf '%s' "$assistant_context" | has_secret
      case $? in
        0|2) assistant_context="" ;;
      esac
    fi
  fi
  { printf '%s\n' "$previous" | jq -c 'select(type == "object" and (.at | numbers) and (.text | strings))' 2>/dev/null
    # 本文と文脈は標準入力で渡し、長い発言を引数の長さ制限へ載せない。
    printf '%s\0%s' "$prompt" "$assistant_context" | jq -Rsc --argjson at "$(date +%s)" 'split("\u0000") | {at: $at, text: .[0], assistant_context: .[1]}'
  } | write_atomic "$prompt_path" || {
    rm -f -- "$prompt_path" 2>/dev/null
    record_failed "書き込みに失敗した" "$lost"
  }
  # gitleaks を使えないときは、実行前の判定でも検査できず「判定せずに通した」と警告するので、ここでは知らせない。
  case "$omitted" in
    ""|gitleaks*) ;;
    *) record_failed "${omitted}ため、このメッセージとそれより前のメッセージを判定役へ渡さない" "$lost" ;;
  esac
  exit 0
fi

# 判定役の codex がツールを使おうとしても、判定の連鎖を起こさない (判定役はツールを無効にして起動する)。
[ -z "${COMMAND_JUDGE_ACTIVE:-}" ] || decide deny "判定役はツールを実行しない"

[ -z "$bad_args" ] || unjudged bad-args "hook の登録の引数が正しくない ($bad_args)"
command -v jq >/dev/null 2>&1 || unjudged no-jq "jq が見つからない"
find_python || unjudged no-python "起動できる python が見つからない"

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -ej '.tool_name | select(type == "string" and length > 0)' 2>/dev/null) ||
  unjudged input "フックの入力からツール名を読めなかった"
tool_input=$(printf '%s' "$input" | jq -cS 'if has("tool_input") then .tool_input else error end' 2>/dev/null) ||
  unjudged input "フックの入力からツール入力を読めなかった"
# Codex は argv 配列や cmd の欄で渡すことがあるため、引用した 1 行のコマンドに直して判定役へ渡す。
command=$(printf '%s' "$input" | jq -ej '.tool_input | (.command // .cmd) |
  if type == "array" then map(tostring) | @sh elif type == "string" then . else error end' 2>/dev/null) || {
  [ "$tool_name" != Bash ] || unjudged input "フックの入力からコマンドを読めなかった"
  command=""
}
purpose=$(printf '%s' "$input" | jq -j '.tool_input.description // "" | tostring' 2>/dev/null) || purpose=""
[ -n "$purpose" ] || purpose="(not provided)"
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || session=""

prepare_state_dir || unjudged state-dir "状態ディレクトリ $state_dir を安全に用意できなかった"

# 同じ文字列でもシェルで意味が変わるため、判定役に渡し、キャッシュの鍵にも含める。
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) [ "$cli" = codex ] && shell="PowerShell (Windows)" || shell="Git Bash (Windows)" ;;
  *) shell="POSIX シェル ($(uname -s 2>/dev/null))" ;;
esac
# 作業ディレクトリも渡す。push の宛先など、同じコマンドでも作業場所で外部への影響が変わるため、キャッシュの鍵にも含める。
# Codex はコマンドごとの作業ディレクトリ (workdir) を指定でき、相対パスならセッションの cwd を基準にする。
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty | tostring' 2>/dev/null) || cwd=""
workdir=$(printf '%s' "$input" | jq -r '.tool_input.workdir // empty | tostring' 2>/dev/null) || workdir=""
case "$workdir" in
  "") ;;
  /*|[A-Za-z]:*) cwd=$workdir ;;
  *) cwd="${cwd:+$cwd/}$workdir" ;;
esac
shell="$shell / エージェント: $cli / 作業ディレクトリ: ${cwd:-(不明)}"
# Claude Code の Bash は timeout を指定しない前景の実行をこの既定値で打ち切る。判定役が既定の上限を推測しないよう渡す。
[ "$cli" = claude ] && [ -n "${BASH_DEFAULT_TIMEOUT_MS:-}" ] &&
  shell="$shell / Bash の既定の上限: ${BASH_DEFAULT_TIMEOUT_MS} ms (指定できる最大 ${BASH_MAX_TIMEOUT_MS:-不明} ms)"

now=$(date +%s)
prompt_path="$state_dir/prompts/$session"
if ! valid_session "$session" || [ -n "${AGENT_DELEGATED_SESSION:-}" ]; then
  prompt_path=/dev/null
fi
context_args=(--context)
[ "$cli" != claude ] || context_args+=(--mask)
context_request='{}'
context_digest=
context_manifest='[]'
judge_stop_at=$((now + 137))

context_helper() {
  local remaining=$((judge_stop_at - $(date +%s)))
  [ "$remaining" -gt 0 ] || return 124
  "$py_bin" -I "$hook_dir/lib/run-judge.py" "$remaining" "$judge_cwd" \
    "$py_bin" -I "$hook_dir/lib/command-judge-context.py" "$@"
}

load_context() {
  local next=${1:-'{}'} prepared digest
  context_request=$(printf '%s\0%s' "$context_request" "$next" | jq -Rsc '
    split("\u0000") | map(fromjson) | .[0] as $previous | .[1] as $next
    | if ($next | type) != "object" then error("invalid context request") else $next end
    | .files = (($previous.files // []) + (.files // []) | unique)
    | .records = (($previous.records // []) + (.records // []) | unique)') ||
    undecided "文脈の取得要求を読み取れなかった"
  prepared=$(printf '%s\0%s\0%s' "$input" "$context_request" "$cwd" | jq -Rsc '
    split("\u0000") | (.[0] | fromjson) + {context_request: (.[1] | fromjson), context_cwd: .[2]}') ||
    undecided "文脈の取得入力を用意できなかった"
  assistant_context=$(printf '%s' "$prepared" | context_helper "${context_args[@]}" 2>/dev/null) ||
    undecided "会話文脈を秘密情報を伏せた状態で取得できなかった"
  context_manifest=$(printf '%s\0%s' "$context_manifest" "$assistant_context" | jq -Rsc '
    split("\u0000") | (.[0] | fromjson) + ((.[1] | fromjson).files // []
      | map(select((.sha256 | type) == "string") | {path, sha256})) | unique') ||
    undecided "取得した原文の版を保持できなかった"
  user_message="(none)"
  if [ -f "$prompt_path" ] && [ ! -L "$prompt_path" ]; then
    user_message=$(jq -sc 'map({input: .text, input_context: (.assistant_context // "")})' "$prompt_path" 2>/dev/null) ||
      undecided "利用者の記録を読み取れなかった"
  fi
  model_context=$(printf '%s' "$assistant_context" | jq -c 'if .files then .files |= map(del(.sha256)) else . end') ||
    undecided "モデルへ渡す証拠を用意できなかった"
  context_data="$(section CONTEXT "$model_context")$(section USER "$user_message")"
  digest=$(printf '%s' "$context_data" | hash_stdin)
  [ "$digest" != "$context_digest" ] || undecided "追加で取得できる証拠が変わらず、操作または承認の根拠を確定できなかった"
  context_digest=$digest
}

verify_context_files() {
  [ "$context_manifest" != '[]' ] || return 0
  local status
  printf '%s\0%s\0%s' "$input" "$context_manifest" "$cwd" | jq -Rsc '
    split("\u0000") | (.[0] | fromjson) + {context_files: (.[1] | fromjson), context_cwd: .[2]}' |
    context_helper --verify-files 2>/dev/null
  status=$?
  [ "$status" -eq 0 ] && return 0
  [ "$status" -ne 124 ] || undecided "取得した原文の版を照合する時間を確保できなかった"
  undecided "判定中に取得したファイルの版が変わったか、現在の版を照合できなかったため再判定する必要がある"
}

# 文脈に依存しない安全判定だけを保存するため、会話や経過時間を鍵に含めない。
policy=$(cat "$hook_dir/command-judge-role.md" "$hook_dir/command-judge-prompt.md" "$hook_dir/command-judge-state-prompt.md" "$hook_dir/command-judge-authorization-prompt.md" | hash_stdin)
key=$(printf '%s\0%s\0%s\0%s' "$policy" "$shell" "$tool_name" "$tool_input" | hash_stdin) &&
  [ -n "$key" ] || unjudged hash "判定のキャッシュの鍵を計算できなかった"
safe_path="$state_dir/safe/$key"
if [ -f "$safe_path" ] && [ ! -L "$safe_path" ] && IFS= read -r cached_at <"$safe_path"; then
  case "$cached_at" in
    ""|*[!0-9]*) ;;
    *) [ $((now - cached_at)) -ge 0 ] && [ $((now - cached_at)) -le "$safe_ttl_seconds" ] && exit 0 ;;
  esac
fi

# 節の区切りを入力から推測できないようにし、データ側から節を閉じて指示を足せないようにする。
nonce=$(od -An -tx1 -N8 /dev/urandom 2>/dev/null | tr -d ' \n')
[ -n "$nonce" ] || nonce="$now$$$RANDOM"
section() {
  printf '\n<<<%s %s>>>\n%s\n<<<END %s %s>>>\n' "$1" "$nonce" "$2" "$1" "$nonce"
}
data=$(section SHELL "$shell" && section TOOL_NAME "$tool_name" && section TOOL_INPUT "$tool_input" && section COMMAND "$command" && section PURPOSE "$purpose")

# Claude のセッションでは、ツール入力は別の提供元 (OpenAI) へ初めて渡る。秘密情報らしき文字列を含むなら送らない。
# 利用者のメッセージは記録時に検査済み。Codex のセッションでは同じ内容が既に Codex のモデルに渡っている。
if [ "$cli" = claude ]; then
  printf '%s' "$data" | has_secret
  case $? in
    0) decide ask "ツール入力か目的の説明に秘密情報らしき文字列があり、判定役 (codex) へ送らなかった。実行してよいか確認する" ;;
    2) unjudged gitleaks "送信前の秘密情報の検査 (gitleaks) を実行できない" ;;
  esac
fi

# 判定役は両 CLI 共通で codex exec にする。Claude Desktop から起動した子の claude -p は認証できないため。
# 送信先は既定の OpenAI に固定し (--ignore-user-config で config.toml の接続先も読まない)、認証は利用者が
# codex login で選んだもの (CODEX_HOME の auth.json) だけを使う。環境変数の API キーへは切り替えない。
judge_cwd="$state_dir/judge-cwd"
down_stamp="$state_dir/judge-down-$cli"
JUDGE_LOGIN_INVALID="判定役の codex のログインが無効 (認証エラー 401) で、codex login でログインし直す必要がある"
# 経過は秒で比べる (BSD の find -mmin は分に切り上げるため、1 分以内の判定に使えない)。
# 印は "<時刻> [原因]"。原因が login なら、判定を省く間もログインの無効を伝える。
if [ -f "$down_stamp" ] && [ ! -L "$down_stamp" ] && read -r down_at down_cause <"$down_stamp"; then
  case "$down_at" in
    ""|*[!0-9]*) ;;
    *) if [ $((now - down_at)) -ge 0 ] && [ $((now - down_at)) -lt $((down_retry_minutes * 60)) ]; then
         [ "${down_cause:-}" = login ] && unjudged judge-login "$JUDGE_LOGIN_INVALID"
         unjudged judge-down "判定役の codex exec が直前の確認で簡単な問いにも答えなかった (codex login status・利用枠・通信を確認すること)"
       fi ;;
  esac
fi
run_stage() {
  local stage=$1 prompt_file=$2 payload=$3 status characters
  characters=$({ cat "$prompt_file" && section STAGE "$stage" && printf '%s' "$payload"; } |
    "$py_bin" -I -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8")))') || undecided "判定入力の長さを確認できなかった"
  [ "$characters" -le 1048576 ] || undecided "判定入力が Codex の 1048576 文字の上限を超えたため、必要な原文をさらに絞る必要がある"
  if [ "$cli" = claude ]; then
    printf '%s' "$payload" | has_secret
    case $? in
      0) decide ask "判定に必要な情報に秘密情報らしき文字列があり、判定役へ送らなかった。実行してよいか確認する" ;;
      2) unjudged gitleaks "送信前の秘密情報の検査 (gitleaks) を実行できない" ;;
    esac
  fi
  [ $((judge_stop_at - $(date +%s))) -ge "$judge_timeout_seconds" ] ||
    undecided "hook の実行上限内で、追加の証拠を判定する時間を確保できなかった"
  output=$({ cat "$prompt_file" && section STAGE "$stage" && printf '%s' "$payload"; } | run_codex "$judge_timeout_seconds" 2>/dev/null)
  status=$?
  case "$status" in
    0) ;;
    124) judge_failed "判定役が ${judge_timeout_seconds} 秒以内に答えなかった" ;;
    127) unjudged no-codex "判定役の codex が見つからない" ;;
    77)
      printf '%s login\n' "$(date +%s)" >"$down_stamp" 2>/dev/null
      unjudged judge-login "$JUDGE_LOGIN_INVALID" ;;
    *) judge_failed "判定役の codex exec が終了コード $status で失敗した" ;;
  esac
}

parse_effect() {
  verdict=$(printf '%s' "$output" | jq -Rsc '
    split("\n") | map(fromjson? | select(type == "object" and
      ([.danger, .body_from_file, .external, .short_cutoff, .needs_context, .context_free] | all(type == "boolean")) and
      (.reason | type == "string"))) | last // empty' 2>/dev/null)
  [ -n "$verdict" ] || judge_failed "判定役の出力から効果の判定を読み取れなかった"
}

run_stage effect "$hook_dir/command-judge-prompt.md" "$data"
parse_effect
used_context=false
while [ "$(jq -r .needs_context <<<"$verdict")" = true ]; do
  load_context "$(jq -c '.context_request // {}' <<<"$verdict")"
  run_stage effect-context "$hook_dir/command-judge-prompt.md" "$data$context_data"
  parse_effect
  used_context=true
done

reason=$(jq -r '.reason // "" | tostring | sub("[。.[:space:]]+$"; "")' <<<"$verdict")
if [ "$(jq -r .body_from_file <<<"$verdict")" = true ]; then
  decide deny "外部へ投稿する本文を、実行前からあるファイルから読ませているため止めた: ${reason}。sandbox の有無で一時ディレクトリが変わると、同じパスで別の残骸ファイルが読まれても投稿は失敗しない。本文をツールの引数に直接書くか、コマンドの中に書いて標準入力から渡し (パスには - を指定)、再実行すること"
fi
if [ "$(jq -r .short_cutoff <<<"$verdict")" = true ]; then
  decide deny "処理を、通常の所要時間に余裕のない根拠のない短い上限で打ち切らせるため止めた: ${reason}。上限は実測や外部の制約から余裕を持たせて決め、根拠が無ければ十分に長い上限にするか背景で実行し、その間は出力の内容を読んで目的の結果へ進んでいるかを確かめること (大きさや行数の増加だけでは進捗と扱わない)"
fi
danger=$(jq -r .danger <<<"$verdict")
external=$(jq -r .external <<<"$verdict")
if [ "$danger" = false ] && [ "$external" = false ]; then
  verify_context_files
  if [ "$used_context" = false ] && [ "$(jq -r .context_free <<<"$verdict")" = true ]; then
    printf '%s\n' "$now" | write_atomic "$safe_path" || true
  fi
  exit 0
fi
state_path="$state_dir/permissions/$cli-$session"
state_helper="$hook_dir/lib/command-judge-state.py"
if [ "$prompt_path" = /dev/null ]; then
  permissions='{"facts":[]}'
else
  update=$("$py_bin" -I "$state_helper" prepare "$prompt_path" "$state_path" "$policy" 2>/dev/null) ||
    undecided "承認状態と本人入力の出典を照合できなかった"
  if [ "$(jq '.new_inputs | length' <<<"$update")" -gt 0 ]; then
    run_stage state "$hook_dir/command-judge-state-prompt.md" "$(section UPDATE "$update")"
    answer=$(printf '%s' "$output" | jq -Rsc 'split("\n") | map(fromjson? | select(type == "object" and has("facts"))) | last // empty')
  else
    answer=$(printf '%s' "$update" | jq -c '{facts: .previous}')
  fi
  permissions=$(printf '%s\0%s' "$update" "$answer" | jq -Rsc 'split("\u0000") | {update: (.[0] | fromjson), answer: (.[1] | fromjson)}' |
    "$py_bin" -I "$state_helper" finish "$prompt_path" "$state_path" "$policy" 2>/dev/null) ||
    judge_failed "承認状態の形式・出典または記録の版が一致しなかった"
  printf '%s\n' "$permissions" | write_atomic "$state_path" || undecided "承認状態を保存できなかった"
fi
# 未記録の発言は許可を作れないが、撤回や対象変更を見落とさないため照合する。
authorization_context=$(printf '%s' "$input" | context_helper "${context_args[@]}" --since "$prompt_path" 2>/dev/null) ||
  undecided "現在の会話文脈を取得できなかった"
authorization_data="$data$(section EFFECT "$verdict")$(section PERMISSIONS "$permissions")$(section CONTEXT "$authorization_context")"
run_stage authorize "$hook_dir/command-judge-authorization-prompt.md" "$authorization_data"
parse_authorization() {
  authorization=$(printf '%s' "$output" | jq -Rsc 'split("\n") | map(fromjson? | select(type == "object" and
    ([.user_requested, .needs_context] | all(type == "boolean")) and (.reason | type == "string"))) | last // empty')
  [ -n "$authorization" ] || judge_failed "判定役の出力から承認の判定を読み取れなかった"
}
parse_authorization
context_digest=
while [ "$(jq -r .needs_context <<<"$authorization")" = true ]; do
  load_context "$(jq -c '.context_request // {}' <<<"$authorization")"
  run_stage authorize-context "$hook_dir/command-judge-authorization-prompt.md" "$authorization_data$(section EVIDENCE "$model_context")$(section USER "$user_message")"
  parse_authorization
done
if [ "$prompt_path" != /dev/null ]; then
  printf '%s\n' "$permissions" | "$py_bin" -I "$state_helper" verify "$prompt_path" "$state_path" "$policy" 2>/dev/null ||
    undecided "判定中に本人入力が変わったため、現在の承認を再判定する必要がある"
fi
if [ "$(jq -r .user_requested <<<"$authorization")" = true ]; then
  verify_context_files
  exit 0
fi
if [ "$danger" = true ]; then
  [ "$external" = true ] &&
    decide deny "エージェント自身の作業を続けられなくなる操作と、このマシンの外へ影響する操作を含むと判定したため止めた: ${reason}。必要な操作なら、会話内の既存承認を照合し、不足する場合だけ両方の操作と対象への許可を得ること"
  decide deny "エージェント自身の作業を続けられなくなる操作と判定したため止めた: ${reason}。必要な操作なら、会話内の既存承認を照合し、不足する場合だけこの操作と対象への許可を得ること"
fi
# Claude は利用者に確認させ、その場の許可で実行させる。Codex の PreToolUse は "ask" を受け付けないので止める。
[ "$cli" = codex ] &&
  decide deny "このマシンの外へ影響する操作で、利用者の許可が無いため止めた: ${reason}。利用者にこの操作をしてよいか尋ね、何をどこへ行うかを書いた許可 (例: 「origin へ push してよい」) をもらい、対象 (remote・ブランチなど) をツール入力に明示して実行し直すこと"
decide ask "このマシンの外へ影響する操作のため、実行してよいか確認する: ${reason}"
