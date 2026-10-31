#!/bin/bash
# PostToolUse (Bash): 外向きの書き込み後に取得した事実だけを短く通知する。
# 本文は再注入しない。意図した内容との照合は AGENTS.md の作業手順に従う。
# 実際に実行される呼び出しだけを検出し (構文は本物の解析器に任せる: lib/shell_commands.py)、push は送信先の ref を照合する。

input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# python の bin 名は環境で変わる(python3 / python)。能力で解決する
py_bin=$(command -v python3 || command -v python) || py_bin=""

notify() {
  local message=$1
  # 解析器が無く簡易判定に戻したときは、その旨を添える (検出漏れの可能性を利用者が判断できるように)。
  [ -n "${notice:-}" ] && message="$message (呼び出しの検出: $notice)"
  jq -n --arg m "$message" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
  exit 0
}

# 確認できなかったことを知らせて終える (同じ種類の通知は 10 分に 1 回)
notify_throttled() {
  local stamp="${XDG_STATE_HOME:-$HOME/.local/state}/agent-guards/notice-$1"
  if [ -z "$(find "$stamp" -mmin -10 2>/dev/null)" ] && mkdir -p "${stamp%/*}" 2>/dev/null && : >"$stamp"; then
    notify "$2"
  fi
  exit 0
}
# python が使えないときは、確認していないことを知らせる
skip_unchecked() {
  notify_throttled no-python-readback "[readback] $1ため、push・gh の書き込みがあったかを確認していない。起動できる python3 を PATH に入れること"
}
[ -n "$py_bin" ] || skip_unchecked "python が見つからない"
# 引数 --shell powershell (Codex on Windows) は検出処理へそのまま渡す。
result=$(printf '%s' "$input" | "$py_bin" "$here/lib/detect-invocation.py" "$@" gh git)
status=$?
if [ "$status" -ne 0 ] && ! "$py_bin" -c '' >/dev/null 2>&1; then
  skip_unchecked "python を起動できない ($py_bin。Microsoft Store の別名など)"
fi
[ "$status" -eq 0 ] || notify "[readback] 呼び出しの検出処理 (hooks/lib/detect-invocation.py) が異常終了した (終了コード $status)。push・gh の書き込みがあったかは確認していない。"
{ IFS= read -r verdict; IFS= read -r notice; } <<<"$result"
calls=$(printf '%s\n' "$result" | sed '1,2d')
case "$verdict" in
  ok) ;;
  undecidable) notify "[readback] コマンドを解析できず、push・gh の書き込みがあったかを確認していない ($calls)。" ;;
  *) notify_throttled unreadable-readback "[readback] 呼び出しの検出処理 (hooks/lib/detect-invocation.py) の出力を読めず、push・gh の書き込みがあったかを確認していない。" ;;
esac
if [ -z "$calls" ]; then
  # 解析器が使えず構文木を読めなかった・締切を超えた等で検出が完全でないときは、見つからなかったことも知らせる
  [ -n "$notice" ] && notify "[readback] push・gh の書き込みは見つからなかったが、検出は完全ではない。"
  exit 0
fi

push_call=$(printf '%s' "$calls" | grep -E '^git( -[^ ]+ [^ ]+)* push( |$)' | head -1)
gh_call=$(printf '%s' "$calls" | grep -E '^gh (pr|issue) (create|edit|comment)( |$)' | head -1)

if [ -n "$push_call" ]; then
  { read -r dir; read -r remote; read -r src; read -r dst; } < <(printf '%s' "$push_call" | "$py_bin" "$here/lib/parse-push.py")

  # hook はシェル変数を展開できない。未展開のまま突き合わせると別リポジトリ・別ブランチを
  # 見て誤警告する。誤警告は hook を無視する習慣を作るので、解決できない時点で止める。
  case "$dir$remote$src$dst" in
    *'$'* | *'`'* | *'~'*)
      notify "[readback] push 先に未展開の変数・パスがあるため、送信先を照合できなかった ($push_call)。"
      ;;
  esac

  if [ -n "$dir" ]; then
    cd "$dir" 2>/dev/null || notify "[readback] git -C の指定先 ($dir) に移動できず、送信先を照合できなかった。"
  else
    # codex は CLAUDE_PROJECT_DIR を持たないため hook 入力の cwd を先に使う
    hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
    cd "${hook_cwd:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null || notify "[readback] 作業ディレクトリに移動できず、送信先を照合できなかった。"
  fi

  case "$dst" in
    '' | HEAD) dst=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) ;;
  esac
  [ -z "$src" ] && src=HEAD
  [ -z "$dst" ] && notify "[readback] git push の宛先ブランチを特定できなかった。"

  local_sha=$(git rev-parse "$src" 2>/dev/null)
  remote_sha=$(git ls-remote "$remote" "refs/heads/$dst" 2>/dev/null | cut -f1)

  [ -z "$remote_sha" ] && notify "[readback] $remote/$dst の SHA を取得できなかった。"
  [ "$local_sha" = "$remote_sha" ] && notify "[readback] $remote/$dst = $remote_sha (ローカル $src と一致)。"
  notify "[readback] $remote/$dst は $remote_sha で、ローカル $src の $local_sha と一致しない。"
fi

if [ -z "$gh_call" ]; then
  # push・gh の書き込みの判定を済ませた後に、検出が完全でなかったことを知らせる (通知は 10 分に 1 回へ間引いてある)
  [ -n "$notice" ] && notify "[readback] push・gh の書き込みは見つからなかったが、検出は完全ではない。"
  exit 0
fi

url=$(printf '%s' "$input" | grep -o 'https://github.com/[^"\\ ]*/\(pull\|issues\)/[0-9]*' | tail -1)
[ -z "$url" ] && notify "[readback] 外向きの書き込みの対象 URL を特定できなかった。"

# pr/issue view の body は親本文であり、投稿したコメントではない。
case "$gh_call" in
  gh\ pr\ comment* | gh\ issue\ comment*) notify "[readback] $url のコメント本文は未取得。" ;;
esac

case "$url" in
  */pull/*) gh pr view "$url" --json body --jq '.body' >/dev/null 2>&1 ;;
  *) gh issue view "$url" --json body --jq '.body' >/dev/null 2>&1 ;;
esac
if [ "$?" -ne 0 ]; then
  notify "[readback] $url の本文の取得に失敗。"
fi

notify "[readback] $url の本文を取得した。意図した内容との一致は未判定。"
