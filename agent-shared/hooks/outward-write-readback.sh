#!/bin/bash
# PostToolUse (Bash) hook: 外向きの書き込みの直後に、権威ある情報源から実物を取得して
# additionalContext として注入する。
#
# 原則: 「操作が成功した」という信号は「何が実際に置かれたか」の証拠にならない。
# コマンドの exit 0 や返ってきた URL が保証するのは呼び出しが通ったことだけで、内容は保証しない。
# 内容を作った場所と読まれる場所の間にパス・名前・ID を挟むと、そこで別物にすり替わりうる。
#
# 実例 (PR #21220): sandbox の有無で $TMPDIR が別ディレクトリになり、gh が別 PR の残骸ファイルを
# 本文として読んだ。gh はエラーを返さず URL を出力したため、内容を確認しないまま完了報告した。
# 読み返しを実行者の判断に委ねると飛ばされる (同一セッションで 2 回連続した) ため、ここで強制する。
#
# 対象はコマンド位置に現れた呼び出しのみ (detect-invocation.py)。
# push は git -C や refspec を解釈して、実際に送った先を突き合わせる (parse-push.py)。
# 誤ったブランチを見て警告すると hook を無視する習慣を作るため、そこは横着しない。
# 取得に失敗した場合も無音で終わらせず、未確認である事実を明示する。

input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

notify() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.stdin.read()}}))'
  exit 0
}

calls=$(printf '%s' "$input" | python3 "$here/lib/detect-invocation.py" gh git 2>/dev/null)
[ -z "$calls" ] && exit 0

push_call=$(printf '%s' "$calls" | grep -E '^git( -[^ ]+ [^ ]+)* push( |$)' | head -1)
gh_call=$(printf '%s' "$calls" | grep -E '^gh (pr|issue) (create|edit|comment)( |$)' | head -1)

if [ -n "$push_call" ]; then
  { read -r dir; read -r remote; read -r src; read -r dst; } < <(printf '%s' "$push_call" | python3 "$here/lib/parse-push.py")

  # hook はシェル変数を展開できない。未展開のまま突き合わせると別リポジトリ・別ブランチを
  # 見て誤警告する。誤警告は hook を無視する習慣を作るので、解決できない時点で止める。
  case "$dir$remote$src$dst" in
    *'$'* | *'`'* | *'~'*)
      notify "[readback] push 先の指定にシェル変数が含まれており、hook 側では展開できない ($push_call)。どのリポジトリの何をどこへ push したかを自分で確認すること。未確認のまま push 済みと報告しない。"
      ;;
  esac

  if [ -n "$dir" ]; then
    cd "$dir" 2>/dev/null || notify "[readback] git -C の指定先 ($dir) に移動できなかった。push 先を自分で確認すること。未確認のまま push 済みと報告しない。"
  else
    # codex は CLAUDE_PROJECT_DIR を持たないため hook 入力の cwd を先に使う
    hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
    cd "${hook_cwd:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null || true
  fi

  [ -z "$dst" ] && dst=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -z "$src" ] && src=HEAD
  [ -z "$dst" ] && notify "[readback] git push を検出したが、宛先ブランチを特定できなかった。リモートの状態を自分で確認すること。"

  local_sha=$(git rev-parse "$src" 2>/dev/null)
  remote_sha=$(git ls-remote "$remote" "refs/heads/$dst" 2>/dev/null | cut -f1)

  [ -z "$remote_sha" ] && notify "[readback] $remote に $dst が見つからない。push の宛先が意図と違う可能性がある。push 済みとして報告する前に確認すること。"
  [ "$local_sha" = "$remote_sha" ] && notify "[readback] $remote/$dst = $remote_sha (ローカル $src と一致)。"
  notify "[readback] $remote/$dst は $remote_sha で、ローカル $src の $local_sha と一致しない。push 済みとして報告しないこと。別ブランチへ push した、または push が部分的に失敗した可能性がある。"
fi

[ -z "$gh_call" ] && exit 0

url=$(printf '%s' "$input" | grep -o 'https://github.com/[^"\\ ]*/\(pull\|issues\)/[0-9]*' | tail -1)
[ -z "$url" ] && notify "[readback] 外向きの書き込みを検出したが、対象 URL を特定できなかった。報告の前に実物を取得して本文を読むこと。取得していない内容を報告に書かない。"

case "$url" in
  */pull/*) body=$(gh pr view "$url" --json body --jq '.body' 2>&1) ;;
  *) body=$(gh issue view "$url" --json body --jq '.body' 2>&1) ;;
esac

if [ -z "$body" ] || printf '%s' "$body" | grep -qi "^gh: \|HTTP 4\|HTTP 5\|not found"; then
  notify "[readback] $url の本文を自動取得できなかった (gh の認証か権限を確認)。未確認のまま内容を報告しないこと。自分で確認して読むこと。"
fi

notify "[readback] $url に実際に投稿されている本文は以下。これが唯一の正。自分が書いたつもりの内容と一致するか照合し、食い違っていれば報告ではなく修正を先に行うこと。

--- 実物ここから ---
$body
--- 実物ここまで ---"
