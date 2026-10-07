#!/bin/bash
# PostToolUse (Bash): 外向きの書き込み後に取得した事実だけを短く通知する。
# 本文は再注入しない。意図した内容との照合は AGENTS.md の作業手順に従う。
# コマンド位置の呼び出しだけを検出し、push は送信先の ref を照合する。

input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# python の bin 名は環境で変わる(python3 / python)。能力で解決する
py_bin=$(command -v python3 || command -v python) || py_bin=""

notify() {
  jq -n --arg m "$1" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
  exit 0
}

[ -n "$py_bin" ] || exit 0
calls=$(printf '%s' "$input" | "$py_bin" "$here/lib/detect-invocation.py" gh git 2>/dev/null)
[ -z "$calls" ] && exit 0

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

  [ -z "$dst" ] && dst=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -z "$src" ] && src=HEAD
  [ -z "$dst" ] && notify "[readback] git push の宛先ブランチを特定できなかった。"

  local_sha=$(git rev-parse "$src" 2>/dev/null)
  remote_sha=$(git ls-remote "$remote" "refs/heads/$dst" 2>/dev/null | cut -f1)

  [ -z "$remote_sha" ] && notify "[readback] $remote/$dst の SHA を取得できなかった。"
  [ "$local_sha" = "$remote_sha" ] && notify "[readback] $remote/$dst = $remote_sha (ローカル $src と一致)。"
  notify "[readback] $remote/$dst は $remote_sha で、ローカル $src の $local_sha と一致しない。"
fi

[ -z "$gh_call" ] && exit 0

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
