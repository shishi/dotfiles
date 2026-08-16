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

# セパレータ後も実行位置
assert_denied "after and-and denied" "cd /tmp && /usr/bin/git push origin master"
assert_denied "after pipe denied" "true | git.exe push --force origin main"

# 環境変数プレフィックス付き実行
assert_denied "env prefix denied" "GIT_DIR=/tmp/x git push --force origin main"

# 言及は実行位置ではない: 誤爆させない
assert_allowed "mention as argument allowed" "echo git push --force"
assert_allowed "quoted mention allowed" "echo 'git push --force origin master'"
assert_allowed "commit message mention allowed" "git commit -m 'do not git push --force to master'"
assert_allowed "word containing git allowed" "legitpush origin master"
assert_allowed "digit-suffixed name allowed" "gitx push origin master"

# 正常系が巻き添えにならないこと
assert_allowed "exe form normal push allowed" "git.exe push origin main"
assert_allowed "path form normal push allowed" "/usr/bin/git push origin feature/x"
assert_allowed "non-push git subcommand allowed" "git status"
assert_allowed "branch named master-ish allowed" "git push origin masterful"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
