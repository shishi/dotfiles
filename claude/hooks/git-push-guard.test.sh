#!/usr/bin/env bash
# git-push-guard.sh の単体テスト。tool_input JSON を stdin 経由で渡し、
# deny (permissionDecision:"deny" 付き JSON 出力) / allow (無出力) を検証する。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/git-push-guard.sh"
PASS=0; FAIL=0

run_guard() { # $1=command
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK"
}

assert_denied() { # $1=desc $2=command
  out=$(run_guard "$2"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = "deny" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_allowed() { # $1=desc $2=command
  out=$(run_guard "$2"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_denied "force push denied" "git push --force origin main"
assert_denied "push to master denied" "git push origin master"
assert_allowed "normal push allowed" "git push origin main"
assert_allowed "unrelated command allowed" "echo hello"

# --- named bypass corpus ---
# 実行形態を変えるだけでガードを抜けられないこと。裸の `git` だけを見ていると
# 全部素通りする経路なので、形態ごとに 1 ケースずつ残す。

# 実行形態: exe 拡張子・POSIX 絶対パス・Windows 絶対パス・相対パス
assert_denied "exe form denied" "git.exe push origin master"
assert_denied "posix path form denied" "/usr/bin/git push --force origin main"
# スペースを含むパスはクォートされている形だけを見る。クォート無しの
# `C:/Program Files/.../git.exe` はシェルが `C:/Program` を探して失敗し、git は
# 実行されない (実測) ので、ガードが通しても危険はない。
assert_denied "windows path form denied" "'C:/Program Files/Git/bin/git.exe' push origin master"
assert_denied "windows backslash path denied" "'C:\\Program Files\\Git\\bin\\git.exe' push --force origin main"
assert_denied "scoop path form denied" "C:/Users/shishi/scoop/apps/git/current/bin/git.exe push origin master"
assert_denied "relative path form denied" "./git push --force origin main"

# コマンド置換の内部も実行位置
assert_denied "dollar-paren substitution denied" "echo \$(git push --force origin main)"
assert_denied "backtick substitution denied" "echo \`git push origin master\`"
assert_denied "nested substitution denied" "echo \$(echo \$(git push --force origin main))"

# refspec 変形。leading + は force push と同じ効果を持つ
assert_denied "head-colon-master denied" "git push origin HEAD:master"
assert_denied "leading plus master denied" "git push origin +master"
assert_denied "leading plus refspec master denied" "git push origin +HEAD:master"

# セパレータ後も実行位置。空白で囲まれた形しか試さないと、区切りをトークンとして
# 認識できていない実装を通す。shlex は既定では空白でしか分割せず `/tmp;` のように
# 区切りが前の語へ癒着するので、空白なしと改行を必ず含める。
assert_denied "after and-and denied" "cd /tmp && /usr/bin/git push origin master"
assert_denied "after pipe denied" "true | git.exe push --force origin main"
assert_denied "semicolon without space denied" "cd /tmp; git push --force origin master"
assert_denied "and-and without space denied" "cd /tmp&&git push --force origin master"
assert_denied "pipe without space denied" "true|git push --force origin main"
assert_denied "subshell denied" "(git push --force origin master)"
assert_denied "newline separated denied" "cd /tmp
git push --force origin master"

# ラッパ経由。コマンド位置が git 以外でも git を実行する
assert_denied "env wrapper denied" "env git push --force origin main"
assert_denied "command builtin denied" "command git push --force origin main"
assert_denied "bash -c denied" "bash -c \"git push --force origin master\""
assert_denied "xargs denied" "echo origin | xargs git push --force"
assert_denied "timeout wrapper denied" "timeout 30 git push --force origin main"

# 隣接した記号は shlex が 1 トークンにまとめる (`);` `)&&` `;(`)。区切りを完全一致で
# 列挙すると、単独の記号しか拾えず結合形が素通りする。
assert_denied "close-paren semicolon denied" "echo \$(date);git push --force origin main"
assert_denied "close-paren and-and denied" "(cd /tmp)&&git push --force origin master"
assert_denied "semicolon open-paren denied" "cd /tmp;(git push --force origin master)"

# refspec の完全修飾形と束ねた短縮オプション。-f を単独で置かないと
# `-[A-Za-z]*f*` のように「f を先頭で食う」パターンの穴を見逃す。
assert_denied "refs/heads/master denied" "git push origin refs/heads/master"
assert_denied "head to refs/heads/master denied" "git push origin HEAD:refs/heads/master"
assert_denied "plus refs/heads/master denied" "git push origin +refs/heads/master"
assert_denied "bundled -uf denied" "git push -uf origin main"
assert_denied "short -f denied" "git push -f origin main"
assert_denied "short -fu denied" "git push -fu origin main"
assert_denied "short -d denied" "git push -d origin feature/x"
assert_denied "short -dv denied" "git push -dv origin feature/x"

# eval は builtin なのでラッパ表には現れないが、引数は 1 本のコマンド行なので
# sh -c と同じく再帰スキャンの対象にする。
assert_denied "eval force denied" "eval \"git push --force origin master\""
assert_denied "eval master denied" "eval 'git push origin master'"
assert_allowed "eval unrelated allowed" "eval 'echo hello'"

# シェルキーワードはコマンド位置に立つがコマンドではない。`do` や `then` が
# コマンド位置を消費すると、その直後の git が引数位置に落ちて素通りする。
# 複数リモート・複数ブランチへの push はループで書かれるので現実的な経路。
assert_denied "for-do loop denied" "for r in origin backup; do git push --force \$r master; done"
assert_denied "if-then denied" "if [ -d .git ]; then git push --force origin master; fi"
assert_denied "while-do denied" "while read b; do git push --force origin \$b; done"
assert_denied "brace group denied" "{ git push --force origin master; }"
assert_denied "exec denied" "exec git push --force origin master"
assert_denied "eval without quotes denied" "eval git push --force origin master"

# 引用された `>` は引数であってリダイレクトではない。リダイレクト先として
# 次のトークンを無条件に捨てると、そこにあるセパレータまで消える。
assert_denied "quoted redirect char then separator denied" "echo '>' && git push --force origin master"

# git 自身がコマンド文字列を取るサブコマンド。引用されると内側が 1 トークンになり
# push の検査に届かない。
assert_denied "submodule foreach quoted denied" "git submodule foreach 'git push --force origin master'"
assert_denied "rebase --exec quoted denied" "git rebase --exec 'git push --force origin master' main"
assert_denied "submodule foreach unquoted denied" "git submodule foreach git push --force origin master"
# `--exec=<cmd>` の結合形も git の parse-options が受け付ける
assert_denied "exec equals form denied" "git rebase --exec='git push --force origin master' main"

# プロセス置換 `<(` `>(` はリダイレクトではなくコマンド位置。記号の結合トークンを
# リダイレクトと判定すると、中で実行される git を「リダイレクト先」として捨てる。
assert_denied "process substitution denied" "diff <(git push --force origin master) /tmp/x"
assert_denied "output process substitution denied" "tee >(git push --force origin master) < /tmp/x"

# コマンド位置に立つがコマンドではない語の残り
assert_denied "function keyword denied" "function f { git push --force origin master; }; f"
assert_denied "path form time denied" "/usr/bin/time git push --force origin master"
assert_denied "su -c denied" "su -c 'git push --force origin master'"

# Windows では ref がファイルとして保存されるので、大文字違いが同じ ref に当たりうる
assert_denied "uppercase master denied" "git push origin MASTER"
assert_denied "mixed case master denied" "git push origin Master"
assert_denied "uppercase refspec master denied" "git push origin HEAD:Master"

# herestring はシェルにコマンド行を渡す。リダイレクトとして捨てると走査に届かない。
assert_denied "herestring denied" "bash <<<'git push --force origin master'"
# `su <user> -c <cmd>`: -c を待たずに最初の非オプションを取ると、ユーザ名を
# コマンド行と誤認して本体を見落とす。
assert_denied "su with user denied" "su someuser -c 'git push --force origin master'"

# Windows/Git Bash の実行ラッパ
assert_denied "winpty wrapper denied" "winpty git push --force origin main"
assert_denied "cmd /c denied" "cmd /c \"git push --force origin master\""
assert_denied "env.exe wrapper denied" "/usr/bin/env.exe git push --force origin main"

# リダイレクトはコマンドを終わらせない。途中に置かれた形で後続の引数を落とさない
assert_denied "redirect before args denied" "git push > /dev/null --force origin master"
assert_denied "fd redirect before args denied" "git push 2>/dev/null --force origin main"

# 実行名の大文字。Windows の PATH 解決は大小文字を区別しない
assert_denied "uppercase exe denied" "GIT.EXE push --force origin main"

# 環境変数プレフィックス付き実行
assert_denied "env prefix denied" "GIT_DIR=/tmp/x git push --force origin main"

# 言及は実行位置ではない: 誤爆させない
assert_allowed "mention as argument allowed" "echo git push --force"
assert_allowed "quoted mention allowed" "echo 'git push --force origin master'"
assert_allowed "commit message mention allowed" "git commit -m 'do not git push --force to master'"
assert_allowed "semicolon inside quotes allowed" "git commit -m 'stop; git push --force'"
assert_allowed "word containing git allowed" "legitpush origin master"
assert_allowed "digit-suffixed name allowed" "gitx push origin master"

# 正常系が巻き添えにならないこと
assert_allowed "exe form normal push allowed" "git.exe push origin main"
assert_allowed "path form normal push allowed" "/usr/bin/git push origin feature/x"
assert_allowed "non-push git subcommand allowed" "git status"
assert_allowed "branch named master-ish allowed" "git push origin masterful"
assert_allowed "multiline normal flow allowed" "git checkout master
git push origin main"
assert_allowed "subshell normal push allowed" "(cd /tmp && git push origin main)"
assert_allowed "grep for push allowed" "git log --grep push"
assert_allowed "redirect at end allowed" "git push origin main > /tmp/log"
assert_allowed "src side master allowed" "git push origin master:main"
assert_allowed "shell running a script allowed" "bash /tmp/deploy.sh"
assert_allowed "long option not a bundle allowed" "git push --follow-tags origin main"
assert_allowed "loop with normal push allowed" "for r in origin backup; do git push \$r main; done"
assert_allowed "if with unrelated command allowed" "if [ -d .git ]; then git status; fi"
assert_allowed "submodule foreach unrelated allowed" "git submodule foreach 'git status'"
assert_allowed "process substitution unrelated allowed" "diff <(git show a) <(git show b)"
assert_allowed "exec equals unrelated allowed" "git rebase --exec='git status' main"
assert_allowed "pipe to tee allowed" "git push origin main 2>&1 | tee /tmp/log"
assert_allowed "clean -x -d allowed" "git clean -x -d /tmp"

# heredoc の本文は引用符の外の改行と区別できないため、コマンド位置として判定される。
# fail-closed 側なので受け入れる。ここで固定しておかないと、誤爆に見えて実装を
# 緩める方向へ直される。
assert_denied "heredoc body is treated as a command" "cat > /tmp/notes.md <<EOF
git push --force origin master
EOF"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
