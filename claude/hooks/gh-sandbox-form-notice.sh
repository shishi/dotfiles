#!/bin/bash
# PreToolUse (Bash) hook: sandbox 除外に一致しない形で gh を呼ぼうとした時点で注意書きを入れる。
#
# settings.json の sandbox.excludedCommands "gh:*" は、gh がコマンド位置にある形にしか一致しない。
# 一致しないと sandbox 内で走り、macOS では keychain が遮断されて、トークンが有効でも
# 「The token in ... is invalid」「To re-authenticate, run: gh auth login」と出る。文言は失効時と
# 同一で出力からは区別できず、失効と誤診する事故が繰り返し起きた。
#
# 対象 (実測で sandbox 内に落ちた形): env 経由・シェルの -c 経由・xargs 経由・コマンド置換の
# 中の gh。検出は detect-wrapped-gh.py。
#
# 対象外 (実測で sandbox 外に出た形)。一致する理由が形ごとに違うので、まとめて
# 「コマンド位置」とは説明しない:
#   - `gh ...`, `FOO=1 gh ...`   前置代入は読み飛ばされ、gh がコマンド位置に立つ
#   - パイプ・`&&` の後ろ         コマンドラインは部分コマンドに分解してから照合される
#   - `nohup gh ...`, `command gh ...`, `nice gh ...`
#       照合前にラッパが剥がされる (gh はコマンド位置には立っていない)。実装が剥がすのは
#       timeout / time / nice / stdbuf / nohup / command / builtin だが、実測したのは
#       nohup / command / nice の 3 つで、残りは未実測。
#
# 取りこぼしを拾い直す後段は無い。誤診を止める仕組みはこの hook だけで、しかも警告するだけの
# 非ブロッキングなので、取りこぼしはそのまま誤診になる。
#
# 事後に出力を見て誤診を止める形 (PostToolUse hook) は成立しない。PostToolUse は Bash が
# 非 0 で終了した呼び出しでは起動せず、認証エラーで落ちる本命のケースを拾えないため。
#
# block はしない。GH_TOKEN 等でトークンを環境変数から渡す呼び出しは keychain を必要とせず、
# 包まれた形のままで正常に動く。コマンド文字列からは keychain が要るかを判定できないため、
# 判断材料を出すに留める。

input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

notify() {
  jq -n --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
  exit 0
}

calls=$(printf '%s' "$input" | python3 "$here/../../agent-shared/hooks/lib/detect-wrapped-gh.py" 2>/dev/null)
detector_status=$?

# 検出器が動かないまま黙ると、警告が出ないことを「安全な形」と誤読する。拾い直す後段は
# 無いので、壊れたことを表に出す。
# ただし gh に触れない呼び出しにまで出すと、壊れている間ずっと全 Bash 呼び出しに警告が付く。
# 真の対象は必ず gh を含むので、payload に gh がある場合だけ報告する (python3 不在でも
# 判定できるよう grep で見る)。
if [ "$detector_status" -ne 0 ] \
  && printf '%s' "$input" | grep -qE '(^|[^A-Za-z0-9_-])gh([^A-Za-z0-9_-]|$)'; then
  notify "[gh-sandbox] gh の呼び出し形の検出器 (hooks/lib/detect-wrapped-gh.py) が動作しなかった。この Bash 呼び出しについて、包まれた gh の警告は出ていない (安全と判定されたわけではない)。gh を使う変更なら、gh を直接コマンド位置に書いているか自分で確認すること。検出器の復旧も要る。"
fi

[ -z "$calls" ] && exit 0

read -r -d '' msg <<EOF
[gh-sandbox] この形の gh は sandbox 除外 (excludedCommands の "gh:*") に一致せず、sandbox 内で走る。macOS では keychain が遮断され、トークンが有効でも「The token in ... is invalid」「To re-authenticate, run: gh auth login」を返す。文言は失効時と同一で、出力からは区別できない。

該当した呼び出し (解析後のトークン列であり、元の表記そのままではない):
${calls}

- keychain のトークンを使う呼び出しなら、gh を直接コマンド位置に書く形へ書き換える (env / シェルの -c / xargs / コマンド置換で包まない)。実測で sandbox 外に出るのは \`gh ...\`、\`FOO=1 gh ...\`、パイプや \`&&\` の後ろ、\`nohup gh ...\`、\`command gh ...\`、\`nice gh ...\`。実装上は timeout / time / stdbuf / builtin も照合前に剥がされる対象だが未実測なので、その形を使うなら 1 回確かめること
- GH_TOKEN などトークンを環境変数で渡しているなら keychain は要らないので、この形のままでよい
EOF

notify "$msg"
