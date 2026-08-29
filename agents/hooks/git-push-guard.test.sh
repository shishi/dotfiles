#!/usr/bin/env bash
# git-push-guard.sh の単体テスト。tool_input JSON を stdin 経由で渡し、
# deny / ask (permissionDecision付きJSON出力) / allow (無出力) を検証する。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/git-push-guard.sh"
PASS=0; FAIL=0
FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/git-push-guard.XXXXXX") || exit 1
APPROVAL_DIR="$FIXTURE_ROOT/approvals"
mkdir "$APPROVAL_DIR" || exit 1
trap 'rm -rf -- "$FIXTURE_ROOT"' EXIT

run_guard() { # $1=command $2=cwd(optional) $3=session(optional)
  jq -n --arg c "$1" --arg cwd "${2:-}" --arg session "${3:-no-approval}" \
    '{tool_input:{command:$c},cwd:$cwd,session_id:$session}' | \
    GIT_PUSH_GUARD_APPROVAL_DIR="$APPROVAL_DIR" GIT_PUSH_GUARD_CLIENT=claude bash "$HOOK"
}

run_codex_guard() { # $1=command $2=cwd(optional) $3=session(optional)
  jq -n --arg c "$1" --arg cwd "${2:-}" --arg session "${3:-no-approval}" \
    '{tool_input:{command:$c},cwd:$cwd,session_id:$session}' | \
    GIT_PUSH_GUARD_APPROVAL_DIR="$APPROVAL_DIR" GIT_PUSH_GUARD_CLIENT=codex bash "$HOOK"
}

record_approval() { # $1=prompt $2=session
  jq -n --arg prompt "$1" --arg session "$2" \
    '{prompt:$prompt,session_id:$session}' | \
    GIT_PUSH_GUARD_APPROVAL_DIR="$APPROVAL_DIR" bash "$HOOK" --record-approval
}

assert_denied() { # $1=desc $2=command
  out=$(run_guard "$2" "${3:-}"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = "deny" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_asked() { # $1=desc $2=command $3=cwd(optional)
  out=$(run_guard "$2" "${3:-}"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = "ask" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_allowed() { # $1=desc $2=command
  out=$(run_guard "$2" "${3:-}"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_codex_asks_approval() { # $1=desc $2=command $3=cwd(optional)
  local out rc decision
  out=$(run_codex_guard "$2" "${3:-}"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = "ask" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc decision=$decision out=$out)"
  fi
}

assert_explicitly_approved() { # $1=desc $2=prompt $3=command $4=session $5=client
  local out rc
  record_approval "$2" "$4" || true
  if [ "${5:-codex}" = codex ]; then
    out=$(run_codex_guard "$3" "" "$4"); rc=$?
  else
    out=$(run_guard "$3" "" "$4"); rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_prompt_not_approved() { # $1=desc $2=prompt $3=session $4=command(optional)
  local out rc decision
  record_approval "$2" "$3" || true
  out=$(run_codex_guard "${4:-git push origin main}" "" "$3"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = ask ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_codex_denied() { # $1=desc $2=command
  local out rc decision
  out=$(run_codex_guard "$2" "${3:-}"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = "deny" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_codex_allowed() { # $1=desc $2=command
  local out rc
  out=$(run_codex_guard "$2" "${3:-}"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$out)"
  fi
}

assert_denied "force push to main denied" "git push --force origin main"
assert_denied "force push to master denied" "git push --force origin master"
assert_denied "delete main denied" "git push origin --delete main"
assert_denied "delete master refspec denied" "git push origin :master"
assert_denied "force push to heads/main DWIM ref denied" "git push --force origin heads/main"
assert_denied "delete heads/main DWIM ref denied" "git push origin :heads/main"
assert_denied "delete heads/main option form denied" "git push origin --delete heads/main"
assert_asked "normal push to master asks" "git push origin master"
assert_asked "normal push to main asks" "git push origin main"
assert_codex_asks_approval "Codex normal push to main asks for user authorization" "git push origin main"
assert_explicitly_approved "Codex accepts an explicit Japanese main push instruction" \
  "mainにpushして" "git push origin main" "approved-main" codex
assert_explicitly_approved "Claude accepts the same explicit main push instruction" \
  "mainにpushしてください" "git push origin main" "approved-main-claude" claude
assert_explicitly_approved "Codex accepts an explicit English master push instruction" \
  "Please push to master" "git push origin master" "approved-master" codex
assert_explicitly_approved "Codex accepts a space-separated master push shorthand" \
  "master push" "git push origin master" "approved-master-space-codex" codex
assert_explicitly_approved "Claude accepts a space-separated master push shorthand" \
  "master push" "git push origin master" "approved-master-space-claude" claude
assert_explicitly_approved "Codex accepts a particle-separated master push shorthand" \
  "masterにpush" "git push origin master" "approved-master-particle-codex" codex
assert_explicitly_approved "Claude accepts a particle-separated master push shorthand" \
  "masterにpush" "git push origin master" "approved-master-particle-claude" claude
record_approval "mainにpushして" "branch-scoped"
branch_scoped_out=$(run_codex_guard "git push origin master" "" "branch-scoped")
if [ "$(printf '%s' "$branch_scoped_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = ask ]; then
  PASS=$((PASS+1)); echo "ok: explicit approval is scoped to the named branch"
else
  FAIL=$((FAIL+1)); echo "NG: explicit approval is scoped to the named branch (out=$branch_scoped_out)"
fi
one_shot_out=$(run_codex_guard "git push origin main" "" "approved-main")
if [ "$(printf '%s' "$one_shot_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = ask ]; then
  PASS=$((PASS+1)); echo "ok: explicit approval is consumed by one push"
else
  FAIL=$((FAIL+1)); echo "NG: explicit approval is consumed by one push (out=$one_shot_out)"
fi
record_approval "mainにはpushしないで" "negative-main"
negative_out=$(run_codex_guard "git push origin main" "" "negative-main")
if [ "$(printf '%s' "$negative_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = ask ]; then
  PASS=$((PASS+1)); echo "ok: negative user instruction does not authorize a push"
else
  FAIL=$((FAIL+1)); echo "NG: negative user instruction does not authorize a push (out=$negative_out)"
fi
record_approval "mainをforce pushして" "force-wording"
force_wording_out=$(run_codex_guard "git push origin main" "" "force-wording")
if [ "$(printf '%s' "$force_wording_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = ask ]; then
  PASS=$((PASS+1)); echo "ok: destructive wording does not leave a normal-push approval"
else
  FAIL=$((FAIL+1)); echo "NG: destructive wording does not leave a normal-push approval (out=$force_wording_out)"
fi
record_approval "mainにpushして" "superseded"
record_approval "まずテストを実行して" "superseded"
superseded_out=$(run_codex_guard "git push origin main" "" "superseded")
if [ "$(printf '%s' "$superseded_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = ask ]; then
  PASS=$((PASS+1)); echo "ok: a later user prompt invalidates an unused approval"
else
  FAIL=$((FAIL+1)); echo "NG: a later user prompt invalidates an unused approval (out=$superseded_out)"
fi
assert_explicitly_approved "one prompt can authorize normal pushes to both protected branches" \
  "mainとmasterにpushして" "git push origin main; git push origin master" "approved-both" codex
assert_prompt_not_approved "a question is not explicit authorization" \
  "mainにpushしてもいい？" "question-main"
assert_prompt_not_approved "a concatenated identifier is not explicit authorization" \
  "masterpush" "concatenated-master" "git push origin master"
assert_prompt_not_approved "quoted wording in a test request is not authorization" \
  "『mainにpushして』という文言をテストして" "quoted-main"
assert_prompt_not_approved "denial phrased with 言っていない is not authorization" \
  "mainにpushしてと言っていない" "not-said-main"
assert_prompt_not_approved "a Japanese prohibition is not authorization" \
  "mainにpushしてはいけない" "prohibited-main"
assert_prompt_not_approved "a repetition request is not authorization" \
  "次の文字列をそのまま復唱して: mainにpushして" "repeat-main"
assert_prompt_not_approved "an explanation request is not authorization" \
  "Explain the phrase: please push to main" "explain-main"
assert_prompt_not_approved "a later line cannot turn quoted text into authorization" \
  $'次の文字列をそのまま復唱して:\nmainにpushして' "multiline-main"
record_approval "mainにpushして" "force-cannot-consume"
force_with_token_out=$(run_codex_guard "git push --force origin main" "" "force-cannot-consume")
if [ "$(printf '%s' "$force_with_token_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ]; then
  PASS=$((PASS+1)); echo "ok: explicit normal-push approval cannot authorize a protected force push"
else
  FAIL=$((FAIL+1)); echo "NG: explicit normal-push approval cannot authorize a protected force push (out=$force_with_token_out)"
fi
printf '%s main\n' "$(( $(date +%s) - 601 ))" > "$APPROVAL_DIR/expired-main"
expired_out=$(run_codex_guard "git push origin main" "" "expired-main")
if [ "$(printf '%s' "$expired_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = ask ]; then
  PASS=$((PASS+1)); echo "ok: explicit approval expires after at most 600 seconds"
else
  FAIL=$((FAIL+1)); echo "NG: explicit approval expires after at most 600 seconds (out=$expired_out)"
fi
assert_codex_denied "Codex force push to main remains unconditionally denied" "git push --force origin main"
assert_codex_denied "Codex deletion of main remains unconditionally denied" "git push origin --delete main"
assert_codex_allowed "Codex force push to a feature branch needs no guard approval" "git push --force origin feature/x"
assert_asked "force-if-includes alone is not a force update" "git push --force-if-includes origin main"
assert_allowed "force push to feature allowed" "git push --force origin feature/x"
assert_allowed "force refspec to feature allowed" "git push origin +HEAD:feature/x"
assert_allowed "delete feature allowed" "git push origin --delete feature/x"
assert_allowed "delete feature refspec allowed" "git push origin :feature/x"
assert_allowed "tag named main is not the protected branch" "git push origin tag main"
assert_allowed "forced tag named main is not the protected branch" "git push --force origin tag main"
assert_allowed "force push of all tags does not imply a protected branch update" "git push --force --tags origin"
assert_allowed "fully qualified nested heads/main branch is not protected main" \
  "git push --force origin HEAD:refs/heads/heads/main"
assert_denied "mirror denied because protected impact is unknown" "git push --mirror origin"
assert_asked "all asks because protected refs may be included" "git push --all origin"
assert_denied "force all denied because protected refs may be included" "git push --force --all origin"
assert_denied "force branches alias denied because protected refs may be included" "git push --force --branches origin"
assert_denied "deny outranks an earlier ask in the same command" "git push origin main; git push --force origin main"
assert_denied "unscoped prune denied because protected refs may be deleted" "git push --prune origin"
assert_allowed "feature-scoped prune allowed" "git push --prune origin 'refs/heads/feature/*:refs/heads/archive/*'"
assert_denied "protected wildcard prune denied" "git push --prune origin 'refs/heads/*:refs/heads/*'"
assert_allowed "unrelated command allowed" "echo hello"

# --- named bypass corpus ---
# 実行形態を変えるだけでガードを抜けられないこと。裸の `git` だけを見ていると
# 全部素通りする経路なので、形態ごとに 1 ケースずつ残す。

# 実行形態: exe 拡張子・POSIX 絶対パス・Windows 絶対パス・相対パス
assert_asked "exe form asks" "git.exe push origin master"
assert_denied "posix path form denied" "/usr/bin/git push --force origin main"
# スペースを含むパスはクォートされている形だけを見る。クォート無しの
# `C:/Program Files/.../git.exe` はシェルが `C:/Program` を探して失敗し、git は
# 実行されない (実測) ので、ガードが通しても危険はない。
assert_asked "windows path form asks" "'C:/Program Files/Git/bin/git.exe' push origin master"
assert_denied "windows backslash path denied" "'C:\\Program Files\\Git\\bin\\git.exe' push --force origin main"
assert_asked "scoop path form asks" "C:/Users/shishi/scoop/apps/git/current/bin/git.exe push origin master"
assert_denied "relative path form denied" "./git push --force origin main"

# コマンド置換の内部も実行位置
assert_denied "dollar-paren substitution denied" "echo \$(git push --force origin main)"
assert_asked "backtick substitution asks" "echo \`git push origin master\`"
assert_denied "nested substitution denied" "echo \$(echo \$(git push --force origin main))"

# refspec 変形。leading + は force push と同じ効果を持つ
assert_asked "head-colon-master asks" "git push origin HEAD:master"
assert_denied "leading plus master denied" "git push origin +master"
assert_denied "leading plus refspec master denied" "git push origin +HEAD:master"

# セパレータ後も実行位置。空白で囲まれた形しか試さないと、区切りをトークンとして
# 認識できていない実装を通す。shlex は既定では空白でしか分割せず `/tmp;` のように
# 区切りが前の語へ癒着するので、空白なしと改行を必ず含める。
assert_asked "after and-and asks" "cd /tmp && /usr/bin/git push origin master"
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
assert_asked "refs/heads/master asks" "git push origin refs/heads/master"
assert_asked "head to refs/heads/master asks" "git push origin HEAD:refs/heads/master"
assert_denied "plus refs/heads/master denied" "git push origin +refs/heads/master"
assert_denied "bundled -uf denied" "git push -uf origin main"
assert_asked "joined short push-option containing f is not force" "git push -ofast origin master"
assert_asked "joined short push-option containing d is not delete" "git push -odelete=false origin main"
assert_denied "short -f denied" "git push -f origin main"
assert_denied "short -fu denied" "git push -fu origin main"
assert_allowed "short -d feature allowed" "git push -d origin feature/x"
assert_allowed "short -dv feature allowed" "git push -dv origin feature/x"

# eval は builtin なのでラッパ表には現れないが、引数は 1 本のコマンド行なので
# sh -c と同じく再帰スキャンの対象にする。
assert_denied "eval force denied" "eval \"git push --force origin master\""
assert_asked "eval master asks" "eval 'git push origin master'"
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
assert_asked "uppercase master asks" "git push origin MASTER"
assert_asked "mixed case master asks" "git push origin Master"
assert_asked "uppercase refspec master asks" "git push origin HEAD:Master"

# herestring はシェルにコマンド行を渡す。リダイレクトとして捨てると走査に届かない。
assert_denied "herestring denied" "bash <<<'git push --force origin master'"
# `su <user> -c <cmd>`: -c を待たずに最初の非オプションを取ると、ユーザ名を
# コマンド行と誤認して本体を見落とす。
assert_denied "su with user denied" "su someuser -c 'git push --force origin master'"
# オプションは -c の前後どちらにも来る
assert_denied "option before -c denied" "bash -x -c 'git push --force origin master'"
assert_denied "option after -c denied" "bash -c -x 'git push --force origin master'"
assert_denied "long option before -c denied" "bash --norc -c 'git push --force origin master'"
# 短オプションは束ねられ、-c は次の引数を取るので束ねの末尾にしか来ない。
# `bash -lc` はエージェント実行系の定番形なので、完全一致だけ見ると穴になる。
assert_denied "bundled -lc denied" "bash -lc 'git push --force origin master'"
assert_denied "bundled -ec denied" "sh -ec 'git push --force origin main'"
assert_asked "bundled -xc asks" "bash -xc 'git push origin master'"
assert_asked "wrapper then bundled -lc asks" "env bash -lc 'git push origin master'"
# MSYS は単独の /c を Windows パスへ書き換えるため、Git Bash の定石は //c
assert_denied "cmd //c denied" "cmd //c 'git push --force origin master'"
assert_asked "cmd //k asks" "cmd //k 'git push origin master'"
assert_denied "cmd split command arguments denied" "cmd //c git push --force origin main"
assert_denied "PowerShell split command arguments denied" "powershell -Command git push --force origin main"
assert_denied "pwsh split command arguments denied" "pwsh -Command git push --force origin main"
# -c より前のリダイレクトはファイル出力であって、シェルへ渡すコマンド行ではない
assert_denied "redirect before -c denied" "bash >/tmp/log -c 'git push --force origin master'"

# git は大小文字違いのサブコマンドを警告付きで受け入れて実行する (実測:
# "You called a Git command named 'Push' ... Continuing under the assumption
# that you meant 'push'")。したがって `git Push --force` は実際に force push する。
assert_denied "mixed case subcommand denied" "git Push --force origin master"
assert_denied "upper case subcommand denied" "git PUSH --force origin main"
assert_asked "mixed case subcommand to master asks" "git Push origin master"
# `-x<cmd>` の値密着形も git の parse-options が受け付ける
assert_denied "exec joined short form denied" "git rebase -x'git push --force origin master' main"

# --- 暗黙のpush先 ---
# hook入力のcwdから現在ブランチを解決し、明示refspecと同じポリシーを適用する。
mkdir "$FIXTURE_ROOT/main" "$FIXTURE_ROOT/feature" || exit 1
git init -q "$FIXTURE_ROOT/main" || exit 1
git init -q "$FIXTURE_ROOT/feature" || exit 1
git -C "$FIXTURE_ROOT/main" symbolic-ref HEAD refs/heads/main || exit 1
git -C "$FIXTURE_ROOT/feature" symbolic-ref HEAD refs/heads/feature/x || exit 1
git -C "$FIXTURE_ROOT/main" remote add feature "$FIXTURE_ROOT/feature" || exit 1
assert_asked "implicit main push asks" "git push" "$FIXTURE_ROOT/main"
assert_denied "implicit main force push denied" "git push --force" "$FIXTURE_ROOT/main"
assert_denied "a positional repository overrides --repo without becoming a refspec" \
  "git push --force --repo=origin feature" "$FIXTURE_ROOT/main"
assert_denied "push option value cannot hide an implicit protected force push" \
  "git push --force --recurse-submodules on-demand origin" "$FIXTURE_ROOT/main"
assert_asked "push option value cannot hide an implicit protected normal push" \
  "git push --recurse-submodules check origin" "$FIXTURE_ROOT/main"
assert_denied "negated recurse option does not consume the remote" \
  "git push --force --no-recurse-submodules origin main" "$FIXTURE_ROOT/feature"
assert_denied "receive-pack option value cannot hide an implicit protected force push" \
  "git push --force --receive-pack helper origin" "$FIXTURE_ROOT/main"
assert_denied "exec option value cannot hide an implicit protected force push" \
  "git push --force --exec helper origin" "$FIXTURE_ROOT/main"
assert_denied "push-option value cannot hide an implicit protected force push" \
  "git push --force --push-option value origin" "$FIXTURE_ROOT/main"
assert_denied "abbreviated receive-pack value cannot hide a protected force push" \
  "git push --force --receive helper origin" "$FIXTURE_ROOT/main"
assert_denied "abbreviated exec value cannot hide a protected force push" \
  "git push --force --ex helper origin" "$FIXTURE_ROOT/main"
assert_denied "abbreviated push-option value cannot hide a protected force push" \
  "git push --force --push value origin" "$FIXTURE_ROOT/main"
assert_denied "abbreviated repo option still lets a positional repository override it" \
  "git push --force --rep=origin feature" "$FIXTURE_ROOT/main"
assert_denied "separated abbreviated repo value is not mistaken for the positional repository" \
  "git push --force --rep origin feature" "$FIXTURE_ROOT/main"
assert_asked "HEAD from main asks" "git push origin HEAD" "$FIXTURE_ROOT/main"
assert_denied "forced HEAD from main denied" "git push --force origin HEAD" "$FIXTURE_ROOT/main"
assert_denied "forced at shorthand from main denied" "git push --force origin @" "$FIXTURE_ROOT/main"
assert_allowed "implicit feature push allowed" "git push" "$FIXTURE_ROOT/feature"
assert_allowed "implicit feature force push allowed" "git push --force" "$FIXTURE_ROOT/feature"
assert_allowed "HEAD from feature allowed" "git push origin HEAD" "$FIXTURE_ROOT/feature"
assert_allowed "forced HEAD from feature allowed" "git push --force origin HEAD" "$FIXTURE_ROOT/feature"
assert_denied "force branches alias from feature denies possible protected impact" \
  "git push --force --branches origin" "$FIXTURE_ROOT/feature"
assert_denied "git -C uses the target repository for implicit force classification" \
  "git -C '$FIXTURE_ROOT/main' push --force" "$FIXTURE_ROOT/feature"
assert_denied "git --git-dir uses the target repository for implicit force classification" \
  "git --git-dir='$FIXTURE_ROOT/main/.git' push --force" "$FIXTURE_ROOT/feature"
assert_denied "pushd before an implicit force push makes the destination fail closed" \
  "pushd '$FIXTURE_ROOT/main' >/dev/null && git push --force" "$FIXTURE_ROOT/feature"
assert_denied "pushd before an implicit normal push fails closed" \
  "pushd '$FIXTURE_ROOT/main' >/dev/null && git push" "$FIXTURE_ROOT/feature"
# 引用符の中の "cd " でも push 先の解決を諦める。これは承知の上の誤検知で、
# commit message が cd に触れているだけで feature への push が落ちる。
# 代わりに払っているものが下の eval のケースで、そちらを閉じる手段が
# 現状これしかない。誤検知を消す変更を入れるなら、まず eval を閉じること。
assert_denied "a quoted cd is treated as a real one (accepted false positive)" \
  'git commit -m "fix cd handling" && git push' "$FIXTURE_ROOT/feature"
# eval は引数をコマンドとして実行するので、引用符の中の cd は実際に cwd を動かす。
# トークナイザには eval への 1 引数として見えるため segment_cwd_unknown は 0 のまま。
# 上の部分文字列判定だけがこれを捕まえる。実測: 判定を外すと deny から allow に変わる。
assert_denied "eval can hide a cd, so the substring test must keep failing closed" \
  "eval 'cd $FIXTURE_ROOT/main' && git push" "$FIXTURE_ROOT/feature"
# 捕まるのは `cd ` の綴りだけ。`eval 'pushd <repo>'` と `eval 'chdir <repo>'` は
# 実測で今も allow(既知の未修正の穴)。ここを deny にするには、eval の分岐から
# 入れ子で起きた cwd 変化を外へ伝播させる必要があり、部分文字列リストを
# 増やす方向では誤検知だけが増える。テストにしていないのは、赤いままの
# アサーションを常設するとスイートが警報として機能しなくなるため。
# 本物の cd はコマンド位置に立つので、セグメント単位の追跡でも捕まる(二重の防御)。
assert_denied "a real cd before an implicit normal push still fails closed" \
  "cd '$FIXTURE_ROOT/main' && git push" "$FIXTURE_ROOT/feature"
assert_denied "env -C before an implicit force push makes cwd unknown" \
  "env -C '$FIXTURE_ROOT/main' git push --force" "$FIXTURE_ROOT/feature"
assert_denied "cwd uncertainty is preserved through eval" \
  "pushd '$FIXTURE_ROOT/main' >/dev/null; eval 'git push --force'" "$FIXTURE_ROOT/feature"

# 暗黙pushは現在ブランチ名だけでは決まらない。Git設定が複数refまたは別名の
# upstream/refspecを選ぶ場合も、実際のpush先で分類する。
git -C "$FIXTURE_ROOT/feature" config push.default matching
assert_asked "matching push may include protected refs" "git push" "$FIXTURE_ROOT/feature"
assert_denied "forced matching push may update protected refs" "git push --force" "$FIXTURE_ROOT/feature"
git -C "$FIXTURE_ROOT/feature" config push.default upstream
git -C "$FIXTURE_ROOT/feature" config branch.feature/x.remote origin
git -C "$FIXTURE_ROOT/feature" config branch.feature/x.merge refs/heads/main
assert_asked "upstream main asks from feature branch" "git push" "$FIXTURE_ROOT/feature"
assert_denied "forced upstream main denied from feature branch" "git push --force" "$FIXTURE_ROOT/feature"
git -C "$FIXTURE_ROOT/feature" config --unset-all branch.feature/x.merge
git -C "$FIXTURE_ROOT/feature" config --unset-all branch.feature/x.remote
git -C "$FIXTURE_ROOT/feature" config --unset-all push.default
git -C "$FIXTURE_ROOT/feature" config remote.origin.push refs/heads/feature/x:refs/heads/main
assert_asked "configured protected push refspec asks" "git push origin" "$FIXTURE_ROOT/feature"
assert_denied "forced configured protected push refspec denied" "git push --force origin" "$FIXTURE_ROOT/feature"
git -C "$FIXTURE_ROOT/feature" config --replace-all remote.origin.push refs/heads/feature/x:refs/heads/archive/x
assert_allowed "configured non-protected push refspec allowed" "git push origin" "$FIXTURE_ROOT/feature"
assert_allowed "forced configured non-protected push refspec allowed" "git push --force origin" "$FIXTURE_ROOT/feature"
git -C "$FIXTURE_ROOT/feature" config --unset-all remote.origin.push
git -C "$FIXTURE_ROOT/feature" remote add origin "$FIXTURE_ROOT/main"
git -C "$FIXTURE_ROOT/feature" config remote.origin.push refs/heads/feature/x:refs/heads/main
assert_asked "sole remote push refspec is honored without an explicit remote" "git push" "$FIXTURE_ROOT/feature"
assert_denied "sole remote force refspec is honored without an explicit remote" "git push --force" "$FIXTURE_ROOT/feature"
git -C "$FIXTURE_ROOT/feature" config --unset-all remote.origin.push
git -C "$FIXTURE_ROOT/feature" config remote.origin.mirror true
assert_denied "configured mirror push is always denied" "git push origin" "$FIXTURE_ROOT/feature"
assert_denied "sole configured mirror remote is always denied" "git push" "$FIXTURE_ROOT/feature"
# remote が 1 個のときだけ解決していると、fork 構成 (origin + upstream) で
# remote が空のまま mirror 判定と remote.*.push 判定を丸ごと飛ばす。git 自身は
# 他に手掛かりが無ければ origin へ push するので、そこを見ないと素通りする。
git init -q "$FIXTURE_ROOT/fork" || exit 1
git -C "$FIXTURE_ROOT/fork" symbolic-ref HEAD refs/heads/feature/x || exit 1
git -C "$FIXTURE_ROOT/fork" remote add origin "$FIXTURE_ROOT/main" || exit 1
git -C "$FIXTURE_ROOT/fork" remote add upstream "$FIXTURE_ROOT/main" || exit 1
git -C "$FIXTURE_ROOT/fork" config remote.origin.mirror true || exit 1
assert_denied "a mirror origin is denied even when a second remote exists" \
  "git push" "$FIXTURE_ROOT/fork"
git -C "$FIXTURE_ROOT/fork" config --unset-all remote.origin.mirror || exit 1
git -C "$FIXTURE_ROOT/fork" config remote.origin.push '+refs/heads/main:refs/heads/main' || exit 1
assert_denied "a protected force refspec on origin is denied when a second remote exists" \
  "git push" "$FIXTURE_ROOT/fork"
git -C "$FIXTURE_ROOT/fork" config --unset-all remote.origin.push || exit 1
assert_allowed "a plain fork layout push is still allowed" "git push" "$FIXTURE_ROOT/fork"
git -C "$FIXTURE_ROOT/feature" config --unset-all remote.origin.mirror
assert_denied "command-local matching force fails closed" \
  "git -c push.default=matching push --force" "$FIXTURE_ROOT/feature"
assert_denied "command-local protected force refspec fails closed" \
  "git -c remote.origin.push=+refs/heads/main:refs/heads/main push origin" "$FIXTURE_ROOT/feature"
assert_denied "command-local mirror setting fails closed" \
  "git -c remote.origin.mirror=true push origin" "$FIXTURE_ROOT/feature"
assert_denied "unknown config cannot turn a normal command into mirror push after approval" \
  "PUSH_MIRROR=true git --config-env=remote.origin.mirror=PUSH_MIRROR push origin" "$FIXTURE_ROOT/feature"
assert_denied "unknown config cannot inject a destructive protected refspec" \
  "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.push GIT_CONFIG_VALUE_0=+refs/heads/master:refs/heads/master git push origin" \
  "$FIXTURE_ROOT/feature"
# alias を挟むと push は再帰で再分類される。--config-env はその再帰へ渡らないと
# 「設定が読めない」という事実が失われ、mirror を仕込んだ push が素通りする。
assert_denied "an alias cannot hide an unresolvable command-local config" \
  "FOO=true git -c alias.p=push --config-env=remote.origin.mirror=FOO p origin" \
  "$FIXTURE_ROOT/feature"
assert_denied "autocorrect cannot hide an unresolvable command-local config" \
  "FOO=true git -c help.autocorrect=immediate --config-env=remote.origin.mirror=FOO puush origin" \
  "$FIXTURE_ROOT/feature"
# --config-env の空白形は等号形と別経路(次引数を待つ)を通る。等号形のテストでは
# こちらの伝播を殺せない。
assert_denied "an alias cannot hide an unresolvable command-local config (separated form)" \
  "FOO=true git -c alias.p=push --config-env remote.origin.mirror=FOO p origin" \
  "$FIXTURE_ROOT/feature"
# --exec の値は入れ子のコマンド行として別途走査される。その走査が segment_* の
# グローバルを初期状態で上書きするため、外側で確定していた「設定が読めない」
# 「cwd が動いた」が消える。push 引数に入れ子コマンドを 1 つ足すだけで保護が外れる。
assert_denied "a nested --exec scan cannot clear an unresolvable command-local config" \
  "FOO=true git -c alias.p=push --config-env=remote.origin.mirror=FOO p --exec='git version' origin" \
  "$FIXTURE_ROOT/feature"
assert_denied "command-local Git alias cannot hide a protected force push" \
  "git -c alias.p=push p --force origin main" "$FIXTURE_ROOT/feature"
git -C "$FIXTURE_ROOT/feature" config alias.p push
assert_denied "configured Git alias cannot hide a protected force push" \
  "git p --force origin master" "$FIXTURE_ROOT/feature"
git -C "$FIXTURE_ROOT/feature" config --unset-all alias.p
git config --file "$FIXTURE_ROOT/foreign-gitconfig" alias.p push
assert_denied "an alternate global config cannot inject an uninspected push alias" \
  "GIT_CONFIG_GLOBAL='$FIXTURE_ROOT/foreign-gitconfig' git -c help.autocorrect=never p --force origin master" \
  "$FIXTURE_ROOT/feature"
assert_denied "config-env Git alias cannot hide a protected force push" \
  "PUSH_ALIAS=push git --config-env=alias.p=PUSH_ALIAS p --force origin master" "$FIXTURE_ROOT/feature"
assert_denied "unrelated config-env does not suppress a known Git alias" \
  "FOO=x git -c alias.p=push --config-env=foo.bar=FOO p --force origin master" "$FIXTURE_ROOT/feature"
assert_denied "GIT_CONFIG_COUNT alias cannot hide a protected force push" \
  "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.p GIT_CONFIG_VALUE_0=push git p --force origin master" \
  "$FIXTURE_ROOT/feature"
assert_denied "environment alias config survives an env and shell wrapper" \
  "env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.p GIT_CONFIG_VALUE_0=push bash -c 'git p --force origin master'" \
  "$FIXTURE_ROOT/feature"
assert_denied "Git autocorrect cannot turn a typo into a protected force push" \
  "git -c help.autocorrect=immediate psuh --force origin master" "$FIXTURE_ROOT/feature"
# argv ではなくデータ経由でシェルに渡る形。塞ぐと `echo 'git push --force'` の
# 許可と正面衝突する。
assert_allowed "piped into shell is out of scope" "echo 'git push --force origin master' | bash"

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
assert_asked "exe form normal main push asks" "git.exe push origin main"
assert_allowed "path form normal push allowed" "/usr/bin/git push origin feature/x"
assert_allowed "non-push git subcommand allowed" "git status"
assert_allowed "branch named master-ish allowed" "git push origin masterful"
assert_asked "multiline normal flow asks" "git checkout master
git push origin main"
assert_asked "subshell normal push asks" "(cd /tmp && git push origin main)"
assert_allowed "grep for push allowed" "git log --grep push"
assert_asked "redirect at end asks" "git push origin main > /tmp/log"
assert_asked "protected destination asks regardless of source" "git push origin master:main"
assert_allowed "shell running a script allowed" "bash /tmp/deploy.sh"
assert_allowed "shell script with option allowed" "bash -x /tmp/deploy.sh"
assert_allowed "bundled -lc unrelated allowed" "bash -lc 'git status'"
assert_asked "long option does not hide protected destination" "git push --follow-tags origin main"
assert_asked "loop with normal protected push asks" "for r in origin backup; do git push \$r main; done"
assert_allowed "if with unrelated command allowed" "if [ -d .git ]; then git status; fi"
assert_allowed "submodule foreach unrelated allowed" "git submodule foreach 'git status'"
assert_allowed "process substitution unrelated allowed" "diff <(git show a) <(git show b)"
assert_allowed "exec equals unrelated allowed" "git rebase --exec='git status' main"
assert_asked "pipe to tee keeps protected decision" "git push origin main 2>&1 | tee /tmp/log"
assert_allowed "clean -x -d allowed" "git clean -x -d /tmp"

# heredoc の本文は引用符の外の改行と区別できないため、コマンド位置として判定される。
# fail-closed 側なので受け入れる。ここで固定しておかないと、誤爆に見えて実装を
# 緩める方向へ直される。
assert_denied "heredoc body is treated as a command" "cat > /tmp/notes.md <<EOF
git push --force origin master
EOF"

# --- fail-open の回帰 ---
# grep へパイプで流すと、grep -q が最初の一致で終了した瞬間に書き込み中の printf が
# EPIPE を受け、pipefail がパイプライン全体を非 0 にする。判定が「危険なので deny」
# ではなく「一致しなかった」に化ける。発火には複数行かつパイプバッファ超えが要る
# ので、小さい入力のテストでは永久に検出できない。
#
# 入力はファイル経由で渡す。Windows のコマンドライン長上限 (約 32KB) により、
# jq --arg では 200KB を渡せず jq 自身が落ちて「無出力 = allow」と区別できない。
assert_denied_file() { # $1=desc $2=file
  out=$(jq -n --rawfile c "$2" '{tool_input:{command:$c}}' | bash "$HOOK"); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$decision" = "deny" ]; then
    PASS=$((PASS+1)); echo "ok: $1"
  else
    FAIL=$((FAIL+1)); echo "NG: $1 (rc=$rc out=$(printf '%s' "$out" | head -c 80))"
  fi
}
BIGTMP="$(mktemp -d)"
{ printf 'git push --force origin master "unclosed\n'; head -c 200000 /dev/zero | tr '\0' 'x'; } > "$BIGTMP/unparsable"
assert_denied_file "huge multiline input still denied (fallback)" "$BIGTMP/unparsable"
{ printf 'git push --force origin master\n'; head -c 200000 /dev/zero | tr '\0' 'x'; } > "$BIGTMP/parsable"
assert_denied_file "huge multiline input still denied (fast path)" "$BIGTMP/parsable"
rm -rf "$BIGTMP"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
