#!/usr/bin/env bash
# inject-memory.sh の単体テスト。fake HOME を組み立てて hook を直接叩く。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/inject-memory.sh"
# テンプレートを渡さない mktemp -d は BSD 版が TMPDIR を無視して固定の
# darwin user temp dir を使うため、sandbox 下で mkdtemp が落ちる。テンプレートで
# TMPDIR 配下を明示する(GNU / BSD どちらも受け付ける)。
tmproot="${TMPDIR:-/tmp}"; tmproot="${tmproot%/}"
TMP=$(mktemp -d "${tmproot}/inject-memory.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
# ghq は root を物理パスで返すため、cwd 側も物理パスに揃える。macOS の /tmp は
# /private/tmp への symlink なので、揃えないと (d)(f) の ghq 相対判定が前方一致で外れる。
TMP=$(cd "$TMP" && pwd -P)
PASS=0; FAIL=0

# GHQ_ROOT は実環境の値が fake HOME の ghq.root を上書きしてしまうため落とす
# (Claude Code のセッション env には GHQ_ROOT が入っている)
run_hook() { # $1=cwd [$2=memory_dir]
  if [ $# -ge 2 ]; then
    printf '{"cwd":"%s"}' "$1" | env -u GHQ_ROOT HOME="$TMP/home" bash "$HOOK" "$2"
  else
    printf '{"cwd":"%s"}' "$1" | env -u GHQ_ROOT HOME="$TMP/home" bash "$HOOK"
  fi
}
assert_contains() { # $1=desc $2=haystack $3=needle
  if printf '%s' "$2" | grep -qF -- "$3"; then PASS=$((PASS+1)); echo "ok: $1"
  else FAIL=$((FAIL+1)); echo "NG: $1 (missing: $3)"; fi
}
assert_not_contains() { # $1=desc $2=haystack $3=needle
  if printf '%s' "$2" | grep -qF -- "$3"; then FAIL=$((FAIL+1)); echo "NG: $1 (unexpected: $3)"
  else PASS=$((PASS+1)); echo "ok: $1"; fi
}
assert_empty() { # $1=desc $2=output
  if [ -z "$2" ]; then PASS=$((PASS+1)); echo "ok: $1"
  else FAIL=$((FAIL+1)); echo "NG: $1 (expected empty output)"; fi
}

mkdir -p "$TMP/home"

# (c) memory ディレクトリ不在 -> 空出力・exit 0
out=$(run_hook "$TMP"); rc=$?
assert_empty "(c) no memory dir -> empty output" "$out"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (c) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (c) exit code $rc"; fi

# 記憶を用意
mkdir -p "$TMP/home/.claude/memory/projects"
printf '# Memory Index\n- [t](t.md) — INDEX-HOOK-LINE\n' > "$TMP/home/.claude/memory/MEMORY.md"

# (b) プロジェクト記憶なし -> 索引と slug 行のみ
out=$(run_hook "$TMP")
assert_contains "(b) index injected" "$out" "INDEX-HOOK-LINE"
assert_contains "(b) slug line present" "$out" "現在のプロジェクト slug:"

# (a)(d-1) origin あり -> remote slug
mkdir -p "$TMP/repo-ssh" && git -C "$TMP/repo-ssh" init -q -b main
git -C "$TMP/repo-ssh" remote add origin git@github.com:shishi/dotfiles.git
printf 'REMOTE-SLUG-MEMORY\n' > "$TMP/home/.claude/memory/projects/github.com-shishi-dotfiles.md"
out=$(run_hook "$TMP/repo-ssh")
assert_contains "(a)(d) remote slug from ssh origin" "$out" "REMOTE-SLUG-MEMORY"

# (e) https 形式でも同一 slug
mkdir -p "$TMP/repo-https" && git -C "$TMP/repo-https" init -q -b main
git -C "$TMP/repo-https" remote add origin https://github.com/shishi/dotfiles
out=$(run_hook "$TMP/repo-https")
assert_contains "(e) https origin -> same slug" "$out" "REMOTE-SLUG-MEMORY"

# (d-2)(f) remote なし + ghq root 配下 -> ghq 相対 slug = remote slug
HOME="$TMP/home" git config --global ghq.root "$TMP/ghq"
mkdir -p "$TMP/ghq/github.com/shishi/dotfiles"
git -C "$TMP/ghq/github.com/shishi/dotfiles" init -q -b main
out=$(run_hook "$TMP/ghq/github.com/shishi/dotfiles")
assert_contains "(d)(f) ghq-relative slug matches remote slug" "$out" "REMOTE-SLUG-MEMORY"

# (d-3) remote も ghq も無し -> path-slug
mkdir -p "$TMP/plain"
pslug=$(printf '%s' "$TMP/plain" | tr ':/\\' '-')
printf 'PATH-SLUG-MEMORY\n' > "$TMP/home/.claude/memory/projects/${pslug}.md"
out=$(run_hook "$TMP/plain")
assert_contains "(d) path-slug fallback" "$out" "PATH-SLUG-MEMORY"

# (g) 引数で記憶ディレクトリを指定できる
mkdir -p "$TMP/altmem"
printf '# Memory Index\n- ALT-DIR-MEMORY\n' > "$TMP/altmem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/altmem")
assert_contains "(g) explicit MEMORY_DIR arg" "$out" "ALT-DIR-MEMORY"

# (h) 壊れた symlink -> 警告 1 行
# Windows git-bash の ln -s はコピー動作になる環境があるため、本物の symlink が
# 作れた場合のみ検証する(junction の実機検証は Task 9 のデプロイ確認で行う)
ln -s "$TMP/no-such-target" "$TMP/broken-link" 2>/dev/null || true
if [ -L "$TMP/broken-link" ]; then
  out=$(run_hook "$TMP" "$TMP/broken-link"); rc=$?
  assert_contains "(h) broken link warns" "$out" "personal-memory-warning"
  if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (h) exit 0"
  else FAIL=$((FAIL+1)); echo "NG: (h) exit code $rc"; fi
else
  echo "skip: (h) symlinks unavailable on this host"
fi

# git repo な記憶ディレクトリの準備ヘルパ
# gpgsign は実ユーザーの設定を継承すると gpg-agent 依存で commit が落ちるので切る
GITC="git -c user.name=t -c user.email=t@t -c commit.gpgsign=false"
make_repo_mem() { # $1=path
  mkdir -p "$1"
  git -C "$1" init -q -b main
  printf '# Memory Index\n- REPO-MEMORY\n' > "$1/MEMORY.md"
  git -C "$1" add MEMORY.md
  $GITC -C "$1" commit -qm init
}

# (i) main・clean な git repo -> 注入される
make_repo_mem "$TMP/repomem"
out=$(run_hook "$TMP" "$TMP/repomem")
assert_contains "(i) healthy git repo injects" "$out" "REPO-MEMORY"

# --- fatal(注入しない)と degraded(⚠ 付きで注入する)の区別 ---
# fatal: HEAD の内容自体が「注入してよい記憶」でない状態。
# degraded: HEAD は健全で、他エージェントの書き込みが進行中なだけの状態。注入は
#   snapshot 経由で commit 済み内容しか読まないため、注入を続けても編集途中は掴まない。
# degraded 行の目印は「最後の commit 時点」(fatal の personal-memory-warning と排他)。

# (j) main 以外のブランチ -> fatal(スキップ + 復旧手順の提示)
make_repo_mem "$TMP/branchmem"
git -C "$TMP/branchmem" switch -qc consolidation/2026-07-12
printf 'BRANCH-DRAFT-LINE\n' >> "$TMP/branchmem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/branchmem")
assert_contains "(j) non-main branch is fatal" "$out" "personal-memory-warning"
assert_not_contains "(j) body not injected" "$out" "REPO-MEMORY"
# fatal は worktree の内容自体を信用しない判定なので、案内した復旧手順が worktree の
# 編集を読ませないことまで確認する(手順の文言だけでは「読ませていない」を表現できない)
recipe=$(printf '%s' "$out" | sed -n 's/.*`\(git -C .*show main:MEMORY.md\)`.*/\1/p')
recovered=$(eval "$recipe" 2>&1)
assert_contains "(j) recovery command yields the main content" "$recovered" "REPO-MEMORY"
assert_not_contains "(j) recovery command does not yield the worktree edit" "$recovered" "BRANCH-DRAFT-LINE"
# 索引以外を読む形も記憶 repo を指していなければ、cwd の repo の同名パスを読んでしまう
assert_contains "(j) the generalized form also targets the memory repo" "$out" "も \`git -C"

# (j3) パスに空白を含む記憶 repo -> fatal の復旧コマンドがそのまま実行できる
#      案内された手順は読み手がコピペする前提なので、出力から抜き出して実際に走らせる
make_repo_mem "$TMP/spaced mem"
git -C "$TMP/spaced mem" switch -qc consolidation/2026-07-12
out=$(run_hook "$TMP" "$TMP/spaced mem")
recipe=$(printf '%s' "$out" | sed -n 's/.*`\(git -C .*show main:MEMORY.md\)`.*/\1/p')
recovered=$(eval "$recipe" 2>&1)
assert_contains "(j3) recovery command for a spaced path is runnable" "$recovered" "REPO-MEMORY"

# (j2) merge 進行中(branch は main のまま)-> fatal
make_repo_mem "$TMP/mergemem"
: > "$TMP/mergemem/.git/MERGE_HEAD"
out=$(run_hook "$TMP" "$TMP/mergemem")
assert_contains "(j2) merge in progress is fatal" "$out" "rebase/merge"
assert_not_contains "(j2) body not injected" "$out" "REPO-MEMORY"

# (j4) rebase 中断中 -> rebase/merge として報告される
#      rebase 中は HEAD が detached になり branch が "HEAD" と読めるため、branch 判定を
#      先に評価すると「ブランチが main ではない (HEAD)」になり実態が伝わらない
make_repo_mem "$TMP/rebasemem"
git -C "$TMP/rebasemem" switch -q --detach main
mkdir "$TMP/rebasemem/.git/rebase-merge"
out=$(run_hook "$TMP" "$TMP/rebasemem")
assert_contains "(j4) interrupted rebase is reported as rebase/merge" "$out" "rebase/merge が進行中"
assert_not_contains "(j4) interrupted rebase is not reported as a branch problem" "$out" "ブランチが main ではない"

# (j5) commit が 1 つも無い記憶 repo -> 実態どおり報告し、失敗する復旧手順を案内しない
#      unborn branch では rev-parse --abbrev-ref HEAD が exit 128 で "HEAD" を返すため
#      branch 判定に落ちると誤診し、main ref が無いので show main: も失敗する
mkdir -p "$TMP/unbornmem"
git -C "$TMP/unbornmem" init -q -b main
printf '# Memory Index\n- REPO-MEMORY\n' > "$TMP/unbornmem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/unbornmem")
# 「commit が無い」と「object / ref が壊れている」は git から区別できないため断定しない
assert_contains "(j5) unresolvable HEAD is reported without asserting emptiness" "$out" "commit を解決できない"
assert_not_contains "(j5) no recovery command that would fail" "$out" "show main:MEMORY.md"
assert_not_contains "(j5) body not injected" "$out" "REPO-MEMORY"

# (p3) ref を失った repo -> unborn と同じ扱いで、記憶が空だと断定しない
#      ref ファイル消失は symbolic-ref が成功するため本物の unborn と区別できない
make_repo_mem "$TMP/lostrefmem"
rm -f "$TMP/lostrefmem/.git/refs/heads/main" "$TMP/lostrefmem/.git/packed-refs"
# reftable backend では loose ref も packed-refs も無く上の rm が no-op になる。前提が
# 成立したかを先に確かめ、成立していなければ skip する(偽の NG と区別できないため)
if git -C "$TMP/lostrefmem" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo "skip: (p3) ref backend keeps HEAD resolvable after removing loose refs"
else
  out=$(run_hook "$TMP" "$TMP/lostrefmem")
  assert_contains "(p3) lost ref does not claim the memory is empty" "$out" "commit を解決できない"
  assert_not_contains "(p3) no recovery command that would fail" "$out" "show main:MEMORY.md"
fi

# (p1) HEAD に索引が無く worktree にだけある -> 無言で終わらせない
#      注入は snapshot 経由なので索引は出せないが、黙って終わると「記憶なしで走っている」
#      ことが誰にも分からない
mkdir -p "$TMP/untrackedidx"
git -C "$TMP/untrackedidx" init -q -b main
printf 'x\n' > "$TMP/untrackedidx/other.md"
git -C "$TMP/untrackedidx" add other.md
$GITC -C "$TMP/untrackedidx" commit -qm init
printf '# Memory Index\n- REPO-MEMORY\n' > "$TMP/untrackedidx/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/untrackedidx")
assert_contains "(p1) uncommitted index warns instead of skipping silently" "$out" "commit 済みの索引が読めません"
# 警告に行動が入っていないと、CLAUDE.md の「警告があればその手順に従う」が行き止まりになる
assert_contains "(p1) the warning states what to do" "$out" "未 commit の下書きとして Read"
assert_not_contains "(p1) uncommitted index is not injected" "$out" "REPO-MEMORY"

# (p4) 索引が未 commit で、かつ別セッションが書き込み中 -> 下書きを読ませる前に lock を伝える
#      書き込み途中の worktree を掴む可能性があるため、lock の事実を落としてはいけない
mkdir -p "$TMP/untrackedlockidx"
git -C "$TMP/untrackedlockidx" init -q -b main
printf 'x\n' > "$TMP/untrackedlockidx/other.md"
git -C "$TMP/untrackedlockidx" add other.md
$GITC -C "$TMP/untrackedlockidx" commit -qm init
printf '# Memory Index\n- REPO-MEMORY\n' > "$TMP/untrackedlockidx/MEMORY.md"
mkdir "$TMP/untrackedlockidx/.git/memory-write.lock"
out=$(run_hook "$TMP" "$TMP/untrackedlockidx")
assert_contains "(p4) uncommitted index under a lock reports the lock" "$out" "write lock あり"
assert_not_contains "(p4) uncommitted index under a lock is not injected" "$out" "REPO-MEMORY"
# 何も注入していない経路なので、注入内容についての文を混ぜてはいけない
assert_not_contains "(p4) does not claim anything was injected" "$out" "以下は最後の commit 時点の内容"

# (p2) .git はあるが git repo として読めない -> 「commit が無い」と誤診しない
mkdir -p "$TMP/brokenmem"
printf 'gitdir: /nonexistent/path\n' > "$TMP/brokenmem/.git"
printf '# Memory Index\n- REPO-MEMORY\n' > "$TMP/brokenmem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/brokenmem")
assert_contains "(p2) unreadable repo is reported as unreadable" "$out" "git repo として読めない"
assert_not_contains "(p2) unreadable repo is not called commit-less" "$out" "commit がまだ無い"

# (j6) fatal かつ main に索引が無い -> 失敗する読み取りコマンドを案内しない
#      ref の存在だけでは「案内した手順が動く」を担保できない
make_repo_mem "$TMP/nomainidx"
git -C "$TMP/nomainidx" rm -q --cached MEMORY.md
$GITC -C "$TMP/nomainidx" commit -qm "drop index"
git -C "$TMP/nomainidx" switch -qc consolidation/2026-07-12
out=$(run_hook "$TMP" "$TMP/nomainidx")
assert_contains "(j6) missing index on main is fatal" "$out" "personal-memory-warning"
assert_not_contains "(j6) no recovery command that would fail" "$out" "show main:MEMORY.md"

# (k) dirty worktree -> degraded(注入は続ける)
make_repo_mem "$TMP/dirtymem"
printf 'DIRTY-DRAFT-LINE\n' >> "$TMP/dirtymem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/dirtymem")
assert_contains "(k) dirty worktree still injects" "$out" "REPO-MEMORY"
assert_contains "(k) dirty worktree is labeled degraded" "$out" "⚠ 記憶 repo の worktree が dirty"
assert_contains "(k) dirty worktree states the content is committed-only" "$out" "最後の commit 時点"
assert_not_contains "(k) dirty worktree is not fatal" "$out" "personal-memory-warning"

# (n) snapshot 読み: dirty な worktree の未 commit 編集は注入されない。
#     degraded 注入が HEAD 固定であることを (k) の draft 行の不在で直接検証する。
assert_not_contains "(n) uncommitted edit is not injected" "$out" "DIRTY-DRAFT-LINE"

# (l) write lock あり -> degraded + lock 取得からの経過時間
make_repo_mem "$TMP/lockmem"
mkdir "$TMP/lockmem/.git/memory-write.lock"
out=$(run_hook "$TMP" "$TMP/lockmem")
assert_contains "(l) locked repo still injects" "$out" "REPO-MEMORY"
assert_contains "(l) fresh lock is labeled degraded" "$out" "⚠ 記憶 repo に write lock あり"
assert_contains "(l) fresh lock is reported as in-progress" "$out" "書き込み進行中"
assert_not_contains "(l) fresh lock is not fatal" "$out" "personal-memory-warning"

# (l2) 10 分以上残存した lock -> stale の可能性を添える
make_repo_mem "$TMP/oldlockmem"
mkdir "$TMP/oldlockmem/.git/memory-write.lock"
stamp=$(date -v-15M +%Y%m%d%H%M.%S 2>/dev/null || date -d '15 minutes ago' +%Y%m%d%H%M.%S)
touch -t "$stamp" "$TMP/oldlockmem/.git/memory-write.lock"
out=$(run_hook "$TMP" "$TMP/oldlockmem")
assert_contains "(l2) stale lock still injects" "$out" "REPO-MEMORY"
assert_contains "(l2) stale lock is labeled degraded" "$out" "⚠ 記憶 repo の write lock が"
assert_contains "(l2) stale lock is flagged as possibly stale" "$out" "stale の可能性"
assert_contains "(l2) stale lock reports elapsed minutes" "$out" "15 分"

# (l2b) 閾値の境界: ちょうど 10 分で stale 側、9 分は書き込み進行中側
#       CLAUDE.md が「10 分以上」と書いているため、境界がどちら側かを固定する
make_repo_mem "$TMP/tenlockmem"
mkdir "$TMP/tenlockmem/.git/memory-write.lock"
stamp=$(date -v-10M +%Y%m%d%H%M.%S 2>/dev/null || date -d '10 minutes ago' +%Y%m%d%H%M.%S)
touch -t "$stamp" "$TMP/tenlockmem/.git/memory-write.lock"
out=$(run_hook "$TMP" "$TMP/tenlockmem")
assert_contains "(l2b) lock at exactly 10 min is stale" "$out" "stale の可能性"
assert_contains "(l2b) lock at exactly 10 min reports 10 min" "$out" "10 分前から残存"

make_repo_mem "$TMP/ninelockmem"
mkdir "$TMP/ninelockmem/.git/memory-write.lock"
stamp=$(date -v-9M +%Y%m%d%H%M.%S 2>/dev/null || date -d '9 minutes ago' +%Y%m%d%H%M.%S)
touch -t "$stamp" "$TMP/ninelockmem/.git/memory-write.lock"
out=$(run_hook "$TMP" "$TMP/ninelockmem")
assert_contains "(l2b) lock at 9 min is in-progress" "$out" "9 分前に取得・書き込み進行中"
assert_not_contains "(l2b) lock at 9 min is not stale" "$out" "stale の可能性"

# (l3) lock の mtime が読めない -> 経過時間なしの degraded に落ちる(注入は続ける)
make_repo_mem "$TMP/nostatmem"
mkdir "$TMP/nostatmem/.git/memory-write.lock"
mkdir -p "$TMP/stub"
printf '#!/bin/sh\nexit 1\n' > "$TMP/stub/stat"
chmod +x "$TMP/stub/stat"
out=$(printf '{"cwd":"%s"}' "$TMP" | env -u GHQ_ROOT HOME="$TMP/home" PATH="$TMP/stub:$PATH" bash "$HOOK" "$TMP/nostatmem")
assert_contains "(l3) unreadable lock mtime still injects" "$out" "REPO-MEMORY"
assert_contains "(l3) unreadable lock mtime is labeled degraded" "$out" "⚠ 記憶 repo に write lock あり(取得時刻は不明)"
assert_contains "(l3) unreadable lock mtime states the content is committed-only" "$out" "最後の commit 時点"
assert_not_contains "(l3) unreadable lock mtime omits elapsed time" "$out" "分前"

# (l4) 現在時刻が数値として読めない -> 経過時間なしの degraded(注入と exit 0 を守る)
#      算術展開に非数値が入ると set -u が hook を落とし、注入も警告も消える経路の回帰テスト
make_repo_mem "$TMP/nodatemem"
mkdir "$TMP/nodatemem/.git/memory-write.lock"
mkdir -p "$TMP/datestub"
printf '#!/bin/sh\necho unknown\n' > "$TMP/datestub/date"
chmod +x "$TMP/datestub/date"
out=$(printf '{"cwd":"%s"}' "$TMP" | env -u GHQ_ROOT HOME="$TMP/home" PATH="$TMP/datestub:$PATH" bash "$HOOK" "$TMP/nodatemem"); rc=$?
assert_contains "(l4) unreadable clock still injects" "$out" "REPO-MEMORY"
assert_contains "(l4) unreadable clock reports unknown lock age" "$out" "取得時刻は不明"
assert_not_contains "(l4) unreadable clock omits elapsed time" "$out" "分前"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (l4) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (l4) exit code $rc"; fi

# (l5) lock の mtime が未来 -> 負の経過時間を表示せず「不明」に落ちる
make_repo_mem "$TMP/futurelockmem"
mkdir "$TMP/futurelockmem/.git/memory-write.lock"
stamp=$(date -v+15M +%Y%m%d%H%M.%S 2>/dev/null || date -d '15 minutes' +%Y%m%d%H%M.%S)
touch -t "$stamp" "$TMP/futurelockmem/.git/memory-write.lock"
out=$(run_hook "$TMP" "$TMP/futurelockmem")
assert_contains "(l5) future lock mtime still injects" "$out" "REPO-MEMORY"
assert_contains "(l5) future lock mtime reports unknown lock age" "$out" "取得時刻は不明"
assert_not_contains "(l5) future lock mtime omits elapsed time" "$out" "分前"

# (l6) GNU 系 stat(-f は filesystem 情報を返し %m はマウントポイント)でも経過時間が出る
#      2 形式を `A || B` で合成すると非数値が exit 0 で採用され stale 検知が死ぬ。守るのは
#      「数値だけを採用する」不変条件で、試行順は結果を変えないためアサートしない
make_repo_mem "$TMP/gnustatmem"
mkdir "$TMP/gnustatmem/.git/memory-write.lock"
stamp=$(date -v-15M +%Y%m%d%H%M.%S 2>/dev/null || date -d '15 minutes ago' +%Y%m%d%H%M.%S)
touch -t "$stamp" "$TMP/gnustatmem/.git/memory-write.lock"
mkdir -p "$TMP/gnustub"
# stub は実 stat に依存させない(実 stat の方言に引きずられると検証したい順序依存が
# ホストごとに変わる)。GNU の「-c は数値・-f は非数値」という性質だけを再現する。
lock_epoch_expect=$(( $(date +%s) - 900 ))
printf '#!/bin/sh\ncase "$1" in\n  -f) echo "/" ;;\n  -c) echo %s ;;\n  *) exit 1 ;;\nesac\n' \
  "$lock_epoch_expect" > "$TMP/gnustub/stat"
chmod +x "$TMP/gnustub/stat"
out=$(printf '{"cwd":"%s"}' "$TMP" | env -u GHQ_ROOT HOME="$TMP/home" PATH="$TMP/gnustub:$PATH" bash "$HOOK" "$TMP/gnustatmem")
assert_contains "(l6) GNU-style stat still yields elapsed minutes" "$out" "15 分前から残存"

# (l7) lock と dirty が同時 -> 両方を伝える(stale lock を除去してよいか判断できるように)
make_repo_mem "$TMP/lockdirtymem"
mkdir "$TMP/lockdirtymem/.git/memory-write.lock"
printf 'DIRTY-DRAFT-LINE\n' >> "$TMP/lockdirtymem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/lockdirtymem")
assert_contains "(l7) lock+dirty reports the lock" "$out" "write lock あり"
assert_contains "(l7) lock+dirty also reports uncommitted changes" "$out" "未 commit の変更あり"
assert_not_contains "(l7) lock+dirty does not inject the uncommitted edit" "$out" "DIRTY-DRAFT-LINE"

# (o) worktree で MEMORY.md が消えた dirty repo -> degraded(commit 済み本文を注入)
make_repo_mem "$TMP/delmem"
rm "$TMP/delmem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/delmem")
assert_contains "(o) deleted MEMORY.md injects the committed copy" "$out" "REPO-MEMORY"
assert_contains "(o) deleted MEMORY.md is labeled degraded" "$out" "⚠ 記憶 repo の worktree が dirty"
assert_not_contains "(o) deleted MEMORY.md is not fatal" "$out" "personal-memory-warning"

# (m) 未 push の ahead commit -> 注入する + 警告行を添える
git init -q --bare "$TMP/mem-origin.git"
make_repo_mem "$TMP/aheadmem"
git -C "$TMP/aheadmem" remote add origin "$TMP/mem-origin.git"
git -C "$TMP/aheadmem" push -q -u origin main
printf '\n- new line\n' >> "$TMP/aheadmem/MEMORY.md"
git -C "$TMP/aheadmem" add MEMORY.md
$GITC -C "$TMP/aheadmem" commit -qm ahead
out=$(run_hook "$TMP" "$TMP/aheadmem")
assert_contains "(m) ahead still injects" "$out" "REPO-MEMORY"
assert_contains "(m) ahead warning line" "$out" "未 push"
# 未 push 警告は degraded ではない。CLAUDE.md は degraded を「⚠ 記憶 repo」で始まる行と
# 定義しているため、ahead 警告がその目印を踏まないことが両者を区別できる条件になる。
assert_not_contains "(m) ahead warning is not a degraded marker" "$out" "⚠ 記憶 repo"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
