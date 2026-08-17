#!/usr/bin/env bash
# gh-sandbox-form-notice.sh の単体テスト。tool_input JSON を stdin 経由で渡し、
# 注入 (additionalContext 付き JSON 出力) / 沈黙 (無出力) を検証する。
#
# 危険側・安全側の区別は推測ではなく実測に基づく。判定は $TMPDIR で行う
# (sandbox 内は Claude Code のセッション temp、外は shell の TMPDIR)。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/gh-sandbox-form-notice.sh"
PASS=0; FAIL=0

run_hook() { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$HOOK"; }
context_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

assert_notified() { # $1=desc $2=command
  out=$(run_hook "$2"); rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$(context_of "$out")" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_silent() { # $1=desc $2=command
  out=$(run_hook "$2"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

# 実測で sandbox 内に落ちた形。keychain が遮断され「token is invalid」を誤報告する。
assert_notified "env 経由" "env FOO=1 gh auth status"
assert_notified "env (代入なし)" "env gh auth status"
assert_notified "bash -c 経由" "bash -c 'gh auth status'"
assert_notified "sh -c 経由" "sh -c \"gh auth status\""
assert_notified "xargs 経由" "echo status | xargs gh auth"

# 実測で sandbox 外に出た形。ここで注入すると無意味な警告になり、hook を無視する習慣を作る。
assert_silent "直接呼び出し" "gh auth status"
assert_silent "パイプで絞る" "gh auth status | tail -2"
assert_silent "&& の後ろ" "true && gh auth status"
assert_silent "nohup 経由" "nohup gh auth status"
assert_silent "env 代入のみ (env コマンドなし)" "FOO=1 gh auth status"
# 照合前に剥がされるラッパ。command / nice は実測で sandbox 外に出た。timeout は
# 剥がし対象として実装に含まれるが、このマシンに未インストールで未実測。
assert_silent "command 経由" "command gh auth status"
assert_silent "nice 経由" "nice gh auth status"
assert_silent "timeout 経由" "timeout 30 gh auth status"

# 同じラッパでも、オプションの付き方で取りこぼさないこと。gh がコマンド位置に無い点は同じ。
assert_notified "env -i" "env -i gh auth status"
assert_notified "env -u NAME" "env -u GHQ_ROOT gh auth status"
assert_notified "絶対パスの env" "/usr/bin/env FOO=1 gh auth status"
assert_notified "空白入りの代入値" "env FOO=\"a b\" gh auth status"
assert_notified "xargs -n 1" "echo status | xargs -n 1 gh auth"
assert_notified "xargs -I {}" "echo 1 | xargs -I {} gh issue view {}"
# BSD xargs (macOS 既定) の -J は次のトークンを食う。実測で sandbox 内に落ちる。
assert_notified "xargs -J (BSD)" "echo 1 | xargs -J % gh auth status"
# GNU xargs の -i / -l / -e は optional arg で、分離した次のトークンは食わない。
# 食うものとして読み飛ばすと gh をコマンド語と認識できなくなる。
assert_notified "xargs -i (optional arg)" "echo 1 | xargs -i gh issue view {}"
assert_notified "xargs -e (optional arg)" "echo 1 | xargs -e gh auth status"
# env -S / --split-string の引数はコマンド行そのもの。読み飛ばさず中身を見る必要がある。
assert_notified "env -S" "env -S 'gh auth status'"
assert_notified "env --split-string=" "env --split-string='gh auth status'"
# c を含む結合オプション。
assert_notified "bash -cx" "bash -cx 'gh auth status'"
# 入れ子ラップ。内側も同じ規則で見ないと素通りする。
assert_notified "入れ子 (シェル -c の中の env)" "bash -c 'env FOO=1 gh auth status'"
# コマンド置換。実測で sandbox 内に落ちる。二重引用符の中でも置換は起きる。
assert_notified "コマンド置換" "X=\$(gh auth status)"
# プロセス置換もサブシェルで走る。実測で sandbox 内。
assert_notified "プロセス置換" "cat <(gh auth status)"
# 置換の中では、剥がされるラッパも効かない (置換そのものが sandbox 内)。
assert_notified "置換の中のラッパ" "X=\$(nice gh auth status)"
# シェルのオプションが分離した引数を取る形。-c を見失うと取りこぼす。
assert_notified "シェル -o pipefail -c" "bash -o pipefail -c 'gh auth status'"
assert_notified "シェル -euo pipefail -c" "bash -euo pipefail -c 'gh auth status'"
# runner が起動する先がシェルの入れ子。
assert_notified "xargs から シェル -c" "echo 1 | xargs -I{} bash -c 'gh issue view {}'"
assert_notified "env から シェル -c" "env FOO=1 bash -c 'gh pr list'"
# BSD の必須引数オプション。読み飛ばさないとコマンド語を取り違える。
assert_notified "env -P" "env -P /opt/bin gh pr list"
# optional arg を required 扱いすると gh を食う。
assert_notified "xargs --max-lines" "echo 1 | xargs --max-lines gh pr list"
assert_notified "二重引用符内のコマンド置換" "echo \"\$(gh api /user)\""
assert_notified "バッククォート" "X=\`gh auth status\`"

# gh を呼んでいない誤検出。文字列として言及しただけで発火すると、無意味な警告として
# hook 全体を無視する習慣を作る。
# 注入本文に該当呼び出しが載ること。additionalContext が空でないことしか見ないと、
# 変数展開の壊れ (例: ${calls} を $calls と書いて後続語まで変数名に飲まれる) を素通しする。
ctx=$(context_of "$(run_hook "env FOO=1 gh auth status")")
if printf '%s' "$ctx" | grep -qF "gh auth status" && printf '%s' "$ctx" | grep -qF "macOS"; then
  PASS=$((PASS+1)); echo "ok: 注入本文に該当呼び出しと OS 条件が載る"
else
  FAIL=$((FAIL+1)); echo "NG: 注入本文に該当呼び出しと OS 条件が載る (ctx=$ctx)"
fi

assert_silent "env の出力を grep" "env | grep gh"
assert_silent "xargs だが gh はコマンドでない" "ls | xargs grep gh"
assert_silent "gh と無関係" "echo hello"
assert_silent "commit message で言及しただけ" "git commit -m \"fix(hooks): bash -c 'gh auth status' が sandbox に落ちる\""
assert_silent "検索パターンとして言及しただけ" "rg 'env FOO=1 gh' claude/hooks/"
assert_silent "ssh -c は sh -c ではない" "ssh -c aes256-gcm@openssh.com host gh"
assert_silent "シェル -c だが gh を呼ばない" "bash -c 'echo gh'"
# -c がシェルのオプションではなく、後続スクリプトの引数である形。
assert_silent "-c はスクリプトの引数" "bash script.sh -c 'gh auth status'"
# 単引用符の中では置換が起きないので、gh は実行されない。
assert_silent "単引用符内の置換らしき文字列" "git commit -m 'see \$(gh auth status)'"
# ヒアドキュメント本文はコマンドではない。commit message で gh の呼び出し形をバッククォートや
# \$() で引用するのは日常的に起きるので、ここで発火すると警告を無視する習慣を作る。
assert_silent "ヒアドキュメント内のバッククォート" "$(printf 'git commit -F - <<%sEOF%s\n`bash -c '"'"'gh auth status'"'"'` について\nEOF' "'" "'")"
assert_silent "ヒアドキュメント内の \$()" "$(printf 'git commit -F - <<%sEOF%s\n\$(gh auth status) について\nEOF' "'" "'")"

# 検出器が壊れたときに黙ると、警告が出ないことを「安全な形」と誤読する。
# PostToolUse 側は非 0 終了で起動しないため後段の拾い直しも無い。
# mktemp の既定パスは sandbox 内から書けないことがあるため TMPDIR 配下を明示する
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gh-sandbox-form-notice-test.XXXXXX") || { echo "NG: 一時ディレクトリを作れない"; exit 1; }
cp "$HOOK" "$tmp/"   # lib/ を持たせない = 検出器を読み込めない状態
out=$(jq -n '{tool_name:"Bash",tool_input:{command:"env FOO=1 gh auth status"}}' | bash "$tmp/$(basename "$HOOK")")
rm -rf "$tmp"
if printf '%s' "$(context_of "$out")" | grep -qF "検出器"; then
  PASS=$((PASS+1)); echo "ok: 検出器が動かないときは黙らず報告する"
else
  FAIL=$((FAIL+1)); echo "NG: 検出器が動かないときは黙らず報告する"
fi

# ただし検出器が壊れていても、gh に触れない呼び出しにまで警告を出すとただのノイズになる。
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gh-sandbox-form-notice-test.XXXXXX") || { echo "NG: 一時ディレクトリを作れない"; exit 1; }
cp "$HOOK" "$tmp/"
out=$(jq -n '{tool_name:"Bash",tool_input:{command:"ls -l /tmp"}}' | bash "$tmp/$(basename "$HOOK")")
rm -rf "$tmp"
if [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "ok: 検出器が壊れても gh 無関係なら黙る"
else
  FAIL=$((FAIL+1)); echo "NG: 検出器が壊れても gh 無関係なら黙る"
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
