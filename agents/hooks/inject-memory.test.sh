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

# gpgsign は実ユーザーの設定を継承すると gpg-agent 依存で commit が落ちるので切る。
# fixture の commit はすべてこの設定を通す。
GITC="git -c user.name=t -c user.email=t@t -c commit.gpgsign=false"

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

# MEMORY.md が無い non-Git directory は未導入として無言、MEMORY.md がある non-Git
# directory は正本でないため本文を読まず警告する。
mkdir -p "$TMP/non-git-empty" "$TMP/non-git-memory"
out=$(run_hook "$TMP" "$TMP/non-git-empty"); rc=$?
assert_empty "(q1) non-Git dir without MEMORY.md is silent" "$out"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q1) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q1) exit code $rc"; fi
printf '# Memory Index\n- NON-GIT-SENTINEL\n' > "$TMP/non-git-memory/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/non-git-memory"); rc=$?
assert_contains "(q2) non-Git memory warns" "$out" "personal-memory-warning"
assert_not_contains "(q2) non-Git memory has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q2) non-Git memory body is not injected" "$out" "NON-GIT-SENTINEL"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q2) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q2) exit code $rc"; fi

# 通常 fixture は editable directory ではなく commit snapshot として用意する。
mkdir -p "$TMP/home/.claude/memory/projects" "$TMP/plain"
pslug=$(printf '%s' "$TMP/plain" | tr ':/\\' '-')
printf '# Memory Index\n- [t](t.md) — INDEX-HOOK-LINE\n' > "$TMP/home/.claude/memory/MEMORY.md"
printf 'REMOTE-SLUG-MEMORY\n' > "$TMP/home/.claude/memory/projects/github.com-shishi-dotfiles.md"
printf 'PATH-SLUG-MEMORY\n' > "$TMP/home/.claude/memory/projects/${pslug}.md"
git -C "$TMP/home/.claude/memory" init -q -b main
git -C "$TMP/home/.claude/memory" add MEMORY.md projects
$GITC -C "$TMP/home/.claude/memory" commit -qm init

# (b) プロジェクト記憶なし -> 索引と slug 行のみ
out=$(run_hook "$TMP")
assert_contains "(b) index injected" "$out" "INDEX-HOOK-LINE"
assert_contains "(b) slug line present" "$out" "現在のプロジェクト slug:"

# (a)(d-1) origin あり -> remote slug
mkdir -p "$TMP/repo-ssh" && git -C "$TMP/repo-ssh" init -q -b main
git -C "$TMP/repo-ssh" remote add origin git@github.com:shishi/dotfiles.git
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
out=$(run_hook "$TMP/plain")
assert_contains "(d) path-slug fallback" "$out" "PATH-SLUG-MEMORY"

# (g) 引数で記憶ディレクトリを指定できる
mkdir -p "$TMP/altmem"
printf '# Memory Index\n- ALT-DIR-MEMORY\n' > "$TMP/altmem/MEMORY.md"
git -C "$TMP/altmem" init -q -b main
git -C "$TMP/altmem" add MEMORY.md
$GITC -C "$TMP/altmem" commit -qm init
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
# `⚠` 接頭辞は degraded を組み立てる 1 行でのみ付くため、(k)(l)(l2)(l3)(o) の 5 本で
# 全文言を押さえれば足りる。経過時間の分岐ケース ((l2b)(l4)(l5)) では重複検証しない。

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

# (q3) branch 検査直後に別プロセスが consolidation branch へ切り替えても、固定するのは
# HEAD ではなく main^{commit}。env assignment が shell function の run_hook を経由して
# PATH と実 git の場所を hook process へ渡せることも、この実行形で確認する。
make_repo_mem "$TMP/toctoumem"
printf '# Memory Index\n- MAIN-SNAPSHOT-SENTINEL\n' > "$TMP/toctoumem/MEMORY.md"
git -C "$TMP/toctoumem" add MEMORY.md
$GITC -C "$TMP/toctoumem" commit -qm main-snapshot
git -C "$TMP/toctoumem" switch -qc consolidation/test
printf '# Memory Index\n- CONSOLIDATION-SENTINEL\n' > "$TMP/toctoumem/MEMORY.md"
git -C "$TMP/toctoumem" add MEMORY.md
$GITC -C "$TMP/toctoumem" commit -qm consolidation-snapshot
git -C "$TMP/toctoumem" switch -q main
mkdir -p "$TMP/toctou-stub"
system_git=$(command -v git)
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "$1" = "-C" ] && [ "$2" = "$INJECT_TEST_MEMORY_DIR" ] && [ "$3" = "rev-parse" ] && [ "$4" = "--abbrev-ref" ] && [ "$5" = "HEAD" ]; then' \
  '  branch=$("$INJECT_TEST_SYSTEM_GIT" "$@") || exit $?' \
  '  "$INJECT_TEST_SYSTEM_GIT" -C "$INJECT_TEST_MEMORY_DIR" switch -q consolidation/test || exit $?' \
  '  printf "%s\n" "$branch"' \
  'else' \
  '  exec "$INJECT_TEST_SYSTEM_GIT" "$@"' \
  'fi' > "$TMP/toctou-stub/git"
chmod +x "$TMP/toctou-stub/git"
out=$(PATH="$TMP/toctou-stub:$PATH" INJECT_TEST_SYSTEM_GIT="$system_git" \
  INJECT_TEST_MEMORY_DIR="$TMP/toctoumem" run_hook "$TMP" "$TMP/toctoumem")
assert_contains "(q3) TOCTOU reads the fixed main snapshot" "$out" "MAIN-SNAPSHOT-SENTINEL"
assert_not_contains "(q3) TOCTOU never injects consolidation content" "$out" "CONSOLIDATION-SENTINEL"

# (q4) main commit を固定できない場合は HEAD/worktree へフォールバックしない。
make_repo_mem "$TMP/nomainresolve"
printf '# Memory Index\n- COMMITTED-MAIN-SENTINEL\n' > "$TMP/nomainresolve/MEMORY.md"
git -C "$TMP/nomainresolve" add MEMORY.md
$GITC -C "$TMP/nomainresolve" commit -qm committed-main
printf '\n- WORKTREE-SENTINEL\n' >> "$TMP/nomainresolve/MEMORY.md"
mkdir -p "$TMP/nomainresolve-stub"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "$1" = "-C" ] && [ "$2" = "$INJECT_TEST_MEMORY_DIR" ] && [ "$3" = "rev-parse" ] && [ "$4" = "--verify" ] && [ "$5" = "main^{commit}" ]; then' \
  '  exit 1' \
  'fi' \
  'exec "$INJECT_TEST_SYSTEM_GIT" "$@"' > "$TMP/nomainresolve-stub/git"
chmod +x "$TMP/nomainresolve-stub/git"
out=$(PATH="$TMP/nomainresolve-stub:$PATH" INJECT_TEST_SYSTEM_GIT="$system_git" \
  INJECT_TEST_MEMORY_DIR="$TMP/nomainresolve" run_hook "$TMP" "$TMP/nomainresolve"); rc=$?
assert_contains "(q4) main resolution failure warns" "$out" "personal-memory-warning"
assert_not_contains "(q4) main resolution failure has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q4) committed body is withheld" "$out" "COMMITTED-MAIN-SENTINEL"
assert_not_contains "(q4) worktree body is withheld" "$out" "WORKTREE-SENTINEL"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q4) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q4) exit code $rc"; fi

# (q5) 固定 snapshot の required object 読み取り失敗は、wrapper を出す前に fail closed。
make_repo_mem "$TMP/readfailmem"
printf '# Memory Index\n- OBJECT-READ-SENTINEL\n' > "$TMP/readfailmem/MEMORY.md"
git -C "$TMP/readfailmem" add MEMORY.md
$GITC -C "$TMP/readfailmem" commit -qm object-read
readfail_sha=$(git -C "$TMP/readfailmem" rev-parse main)
mkdir -p "$TMP/readfail-stub"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "$1" = "-C" ] && [ "$2" = "$INJECT_TEST_MEMORY_DIR" ] && [ "$3" = "show" ] && [ "$4" = "$INJECT_TEST_FAIL_OBJECT" ]; then' \
  '  printf "PARTIAL-OBJECT-BODY\n"' \
  '  exit 1' \
  'fi' \
  'exec "$INJECT_TEST_SYSTEM_GIT" "$@"' > "$TMP/readfail-stub/git"
chmod +x "$TMP/readfail-stub/git"
out=$(PATH="$TMP/readfail-stub:$PATH" INJECT_TEST_SYSTEM_GIT="$system_git" \
  INJECT_TEST_MEMORY_DIR="$TMP/readfailmem" INJECT_TEST_FAIL_OBJECT="${readfail_sha}:MEMORY.md" \
  run_hook "$TMP" "$TMP/readfailmem"); rc=$?
assert_contains "(q5) object read failure warns" "$out" "personal-memory-warning"
assert_contains "(q5) object read warning names only the path" "$out" "MEMORY.md"
assert_not_contains "(q5) object read failure has no partial wrapper" "$out" "<personal-memory>"
assert_not_contains "(q5) object body is withheld" "$out" "OBJECT-READ-SENTINEL"
assert_not_contains "(q5) partial failed-read stdout is withheld" "$out" "PARTIAL-OBJECT-BODY"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q5) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q5) exit code $rc"; fi

# (q6) 秘密らしい内容は MEMORY.md / selected project file のどちらにあっても、値や
# 他の正常行を含む本文全体を抑止する。警告へ出してよいのは対象相対 path だけ。
mkdir -p "$TMP/secret-project"
git -C "$TMP/secret-project" init -q -b main
git -C "$TMP/secret-project" remote add origin git@github.com:shishi/dotfiles.git
make_secret_repo() { # $1=path $2=MEMORY body $3=optional project body
  mkdir -p "$1/projects"
  git -C "$1" init -q -b main
  printf '%s\n' "$2" > "$1/MEMORY.md"
  git -C "$1" add MEMORY.md
  if [ -n "$3" ]; then
    printf '%s\n' "$3" > "$1/projects/github.com-shishi-dotfiles.md"
    git -C "$1" add projects/github.com-shishi-dotfiles.md
  fi
  $GITC -C "$1" commit -qm secret-fixture
}

make_secret_repo "$TMP/secret-password" \
  $'# Memory Index\nSAFE-MEMORY-BODY\npassword = this-is-a-dummy-secret' ''
out=$(run_hook "$TMP/secret-project" "$TMP/secret-password")
assert_contains "(q6a) password assignment warns with MEMORY path" "$out" "MEMORY.md"
assert_contains "(q6a) password assignment uses warning wrapper" "$out" "personal-memory-warning"
assert_not_contains "(q6a) password assignment has no memory wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6a) password value is not leaked" "$out" "this-is-a-dummy-secret"
assert_not_contains "(q6a) safe sibling body is also withheld" "$out" "SAFE-MEMORY-BODY"
assert_not_contains "(q6a) secret warning omits absolute memory dir" "$out" "$TMP/secret-password"

make_secret_repo "$TMP/secret-pat" '# Memory Index' \
  $'SAFE-PROJECT-BODY\ngithub_pat_abcdefghijklmnopqrstuvwxyz123456'
out=$(run_hook "$TMP/secret-project" "$TMP/secret-pat")
assert_contains "(q6b) PAT warns with selected project path" "$out" "projects/github.com-shishi-dotfiles.md"
assert_not_contains "(q6b) PAT has no memory wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6b) PAT value is not leaked" "$out" "github_pat_abcdefghijklmnopqrstuvwxyz123456"
assert_not_contains "(q6b) safe project sibling is also withheld" "$out" "SAFE-PROJECT-BODY"

aws_key='AKIA'
aws_key="${aws_key}ABCDEFGHIJKLMNOP"
make_secret_repo "$TMP/secret-aws" \
  $'# Memory Index\n'"$aws_key" ''
out=$(run_hook "$TMP/secret-project" "$TMP/secret-aws")
assert_contains "(q6c) AWS access key warns" "$out" "personal-memory-warning"
assert_not_contains "(q6c) AWS access key has no memory wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6c) AWS access key value is not leaked" "$out" "$aws_key"

private_key_header='-----BEGIN OPENSSH'
private_key_header="${private_key_header} PRIVATE KEY-----"
make_secret_repo "$TMP/secret-key" '# Memory Index' \
  $'SAFE-PROJECT-BODY\n'"$private_key_header"
out=$(run_hook "$TMP/secret-project" "$TMP/secret-key")
assert_contains "(q6d) private key header warns with selected project path" "$out" "projects/github.com-shishi-dotfiles.md"
assert_not_contains "(q6d) private key has no memory wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6d) private key header is not leaked" "$out" "$private_key_header"
assert_not_contains "(q6d) safe project body is withheld" "$out" "SAFE-PROJECT-BODY"

# 引用付き key の JSON/YAML 形式も sensitive assignment として扱う。
quoted_assignment='"to'
quoted_assignment="${quoted_assignment}ken\": \"abcdefgh\""
make_secret_repo "$TMP/secret-quoted-assignment" \
  $'# Memory Index\nSAFE-QUOTED-SIBLING\n'"$quoted_assignment" ''
out=$(run_hook "$TMP/secret-project" "$TMP/secret-quoted-assignment")
assert_contains "(q6g) quoted sensitive assignment warns" "$out" "personal-memory-warning"
assert_contains "(q6g) quoted sensitive assignment names MEMORY path" "$out" "MEMORY.md"
assert_not_contains "(q6g) quoted sensitive assignment has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6g) quoted sensitive value is not leaked" "$out" "abcdefgh"
assert_not_contains "(q6g) quoted assignment withholds sibling body" "$out" "SAFE-QUOTED-SIBLING"

# quote 内の値長には空白も含める。実用的な passphrase を、最初の単語が短いという理由で
# 見逃さない。一方、8 文字未満の明白な placeholder は過検出しない。
spaced_password='"pass'
spaced_password="${spaced_password}word\": \"correct horse battery staple\""
make_secret_repo "$TMP/secret-spaced-password" \
  $'# Memory Index\nSAFE-SPACED-SIBLING\n'"$spaced_password" ''
out=$(run_hook "$TMP/secret-project" "$TMP/secret-spaced-password")
assert_contains "(q6h) spaced quoted password warns" "$out" "personal-memory-warning"
assert_contains "(q6h) spaced quoted password names MEMORY path" "$out" "MEMORY.md"
assert_not_contains "(q6h) spaced quoted password has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6h) spaced quoted password value is not leaked" "$out" "correct horse battery staple"
assert_not_contains "(q6h) spaced quoted password withholds sibling body" "$out" "SAFE-SPACED-SIBLING"

# 開始quoteと同じ文字だけを終了quoteとして扱う。内側の反対quoteは値の一部として許容する。
double_quoted_value="don't reuse this password"
double_quoted_password='"pass'
double_quoted_password="${double_quoted_password}word\": \"${double_quoted_value}\""
make_secret_repo "$TMP/secret-double-quote-apostrophe" \
  $'# Memory Index\nSAFE-DOUBLE-QUOTE-SIBLING\n'"$double_quoted_password" ''
out=$(run_hook "$TMP/secret-project" "$TMP/secret-double-quote-apostrophe")
assert_contains "(q6j) apostrophe inside double-quoted password warns" "$out" "personal-memory-warning"
assert_not_contains "(q6j) apostrophe password has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6j) apostrophe password value is not leaked" "$out" "$double_quoted_value"
assert_not_contains "(q6j) apostrophe password withholds sibling body" "$out" "SAFE-DOUBLE-QUOTE-SIBLING"

single_quoted_value='say "never" again'
single_quoted_password='"pass'
single_quoted_password="${single_quoted_password}word\": '${single_quoted_value}'"
make_secret_repo "$TMP/secret-single-quote-double" \
  $'# Memory Index\nSAFE-SINGLE-QUOTE-SIBLING\n'"$single_quoted_password" ''
out=$(run_hook "$TMP/secret-project" "$TMP/secret-single-quote-double")
assert_contains "(q6k) double quote inside single-quoted password warns" "$out" "personal-memory-warning"
assert_not_contains "(q6k) single-quoted password has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6k) single-quoted password value is not leaked" "$out" "$single_quoted_value"
assert_not_contains "(q6k) single-quoted password withholds sibling body" "$out" "SAFE-SINGLE-QUOTE-SIBLING"

short_placeholder='"pass'
short_placeholder="${short_placeholder}word\": \"not set\""
make_secret_repo "$TMP/short-placeholder" \
  $'# Memory Index\n'"$short_placeholder" ''
out=$(run_hook "$TMP/secret-project" "$TMP/short-placeholder")
assert_contains "(q6i) short placeholder remains injectable" "$out" "not set"
assert_not_contains "(q6i) short placeholder does not warn" "$out" "personal-memory-warning"

short_single_placeholder='"pass'
short_single_placeholder="${short_single_placeholder}word\": 'not set'"
make_secret_repo "$TMP/short-single-placeholder" \
  $'# Memory Index\n'"$short_single_placeholder" ''
out=$(run_hook "$TMP/secret-project" "$TMP/short-single-placeholder")
assert_contains "(q6l) short single-quoted placeholder remains injectable" "$out" "not set"
assert_not_contains "(q6l) short single-quoted placeholder does not warn" "$out" "personal-memory-warning"

# 通常文中の token / private key は assignment でなければ誤検出しない。
make_secret_repo "$TMP/clean-prose" \
  $'# Memory Index\nA token budget is not a credential.' \
  'Document the private key rotation procedure without storing key material.'
out=$(run_hook "$TMP/secret-project" "$TMP/clean-prose")
assert_contains "(q6e) clean token prose is injected" "$out" "A token budget is not a credential."
assert_contains "(q6e) clean private-key prose is injected" "$out" "private key rotation procedure"
assert_not_contains "(q6e) clean prose does not warn" "$out" "personal-memory-warning"

# 検査 command 自体の失敗も本文を出さない。
make_repo_mem "$TMP/scanfailmem"
printf '# Memory Index\n- SCAN-FAIL-SENTINEL\n' > "$TMP/scanfailmem/MEMORY.md"
git -C "$TMP/scanfailmem" add MEMORY.md
$GITC -C "$TMP/scanfailmem" commit -qm scan-failure
mkdir -p "$TMP/scanfail-stub"
printf '#!/bin/sh\nexit 2\n' > "$TMP/scanfail-stub/grep"
chmod +x "$TMP/scanfail-stub/grep"
out=$(PATH="$TMP/scanfail-stub:$PATH" run_hook "$TMP" "$TMP/scanfailmem"); rc=$?
assert_contains "(q6f) scan failure warns" "$out" "personal-memory-warning"
assert_contains "(q6f) scan failure names the path" "$out" "MEMORY.md"
assert_not_contains "(q6f) scan failure has no memory wrapper" "$out" "<personal-memory>"
assert_not_contains "(q6f) scan failure withholds body" "$out" "SCAN-FAIL-SENTINEL"
assert_not_contains "(q6f) scan warning omits absolute memory dir" "$out" "$TMP/scanfailmem"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q6f) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q6f) exit code $rc"; fi

# (q7) selected project の存在確認自体が壊れた場合、正常な不存在へ畳まず fail closed。
make_secret_repo "$TMP/project-probe-fail" \
  $'# Memory Index\nPROBE-MEMORY-SENTINEL' 'PROBE-PROJECT-SENTINEL'
probe_sha=$(git -C "$TMP/project-probe-fail" rev-parse main)
probe_path='projects/github.com-shishi-dotfiles.md'
mkdir -p "$TMP/project-probe-stub"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "$1" = "-C" ] && [ "$2" = "$INJECT_TEST_MEMORY_DIR" ]; then' \
  '  if [ "$3" = "cat-file" ] && [ "$4" = "-e" ] && [ "$5" = "$INJECT_TEST_PROJECT_OBJECT" ]; then exit 2; fi' \
  '  if [ "$3" = "ls-tree" ] && [ "$4" = "--name-only" ] && [ "$5" = "$INJECT_TEST_SNAPSHOT" ] && [ "$6" = "--" ] && [ "$7" = "$INJECT_TEST_PROJECT_PATH" ]; then exit 2; fi' \
  'fi' \
  'exec "$INJECT_TEST_SYSTEM_GIT" "$@"' > "$TMP/project-probe-stub/git"
chmod +x "$TMP/project-probe-stub/git"
out=$(PATH="$TMP/project-probe-stub:$PATH" INJECT_TEST_SYSTEM_GIT="$system_git" \
  INJECT_TEST_MEMORY_DIR="$TMP/project-probe-fail" \
  INJECT_TEST_PROJECT_OBJECT="${probe_sha}:${probe_path}" INJECT_TEST_SNAPSHOT="$probe_sha" \
  INJECT_TEST_PROJECT_PATH="$probe_path" run_hook "$TMP/secret-project" "$TMP/project-probe-fail"); rc=$?
assert_contains "(q7) project probe failure warns" "$out" "personal-memory-warning"
assert_contains "(q7) project probe warning names selected path" "$out" "$probe_path"
assert_not_contains "(q7) project probe failure has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q7) project probe failure withholds MEMORY body" "$out" "PROBE-MEMORY-SENTINEL"
assert_not_contains "(q7) project probe failure withholds project body" "$out" "PROBE-PROJECT-SENTINEL"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q7) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q7) exit code $rc"; fi

# (q8) required index の存在確認も tri-state とし、Git異常を通常の不存在と区別する。
make_repo_mem "$TMP/index-probe-fail"
index_probe_sha=$(git -C "$TMP/index-probe-fail" rev-parse main)
mkdir -p "$TMP/index-probe-stub"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "$1" = "-C" ] && [ "$2" = "$INJECT_TEST_MEMORY_DIR" ]; then' \
  '  if [ "$3" = "cat-file" ] && [ "$4" = "-e" ] && [ "$5" = "$INJECT_TEST_INDEX_OBJECT" ]; then exit 2; fi' \
  '  if [ "$3" = "ls-tree" ] && [ "$4" = "--name-only" ] && [ "$5" = "$INJECT_TEST_SNAPSHOT" ] && [ "$6" = "--" ] && [ "$7" = "MEMORY.md" ]; then exit 2; fi' \
  'fi' \
  'exec "$INJECT_TEST_SYSTEM_GIT" "$@"' > "$TMP/index-probe-stub/git"
chmod +x "$TMP/index-probe-stub/git"
out=$(PATH="$TMP/index-probe-stub:$PATH" INJECT_TEST_SYSTEM_GIT="$system_git" \
  INJECT_TEST_MEMORY_DIR="$TMP/index-probe-fail" \
  INJECT_TEST_INDEX_OBJECT="${index_probe_sha}:MEMORY.md" INJECT_TEST_SNAPSHOT="$index_probe_sha" \
  run_hook "$TMP" "$TMP/index-probe-fail"); rc=$?
assert_contains "(q8) index probe error is distinguished from absence" "$out" "存在確認に失敗"
assert_contains "(q8) index probe warning names MEMORY path" "$out" "MEMORY.md"
assert_not_contains "(q8) index probe error has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q8) index probe error withholds body" "$out" "REPO-MEMORY"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q8) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q8) exit code $rc"; fi

# (q9) status が失敗したら partial stdout を dirty state と誤認せず、本文出力前に fail closed。
make_secret_repo "$TMP/status-fail" \
  $'# Memory Index\nSTATUS-MEMORY-SENTINEL' 'STATUS-PROJECT-SENTINEL'
printf '\nWORKTREE-STATUS-SENTINEL\n' >> "$TMP/status-fail/MEMORY.md"
mkdir -p "$TMP/status-fail-stub"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "$1" = "-C" ] && [ "$2" = "$INJECT_TEST_MEMORY_DIR" ] && [ "$3" = "status" ] && [ "$4" = "--porcelain" ]; then' \
  '  printf "PARTIAL-STATUS-BODY\n"' \
  '  exit 2' \
  'fi' \
  'exec "$INJECT_TEST_SYSTEM_GIT" "$@"' > "$TMP/status-fail-stub/git"
chmod +x "$TMP/status-fail-stub/git"
out=$(PATH="$TMP/status-fail-stub:$PATH" INJECT_TEST_SYSTEM_GIT="$system_git" \
  INJECT_TEST_MEMORY_DIR="$TMP/status-fail" run_hook "$TMP/secret-project" "$TMP/status-fail"); rc=$?
expected_status_warning='<personal-memory-warning>記憶 repo の Git 状態を確認できないため注入をスキップしました</personal-memory-warning>'
if [ "$out" = "$expected_status_warning" ]; then PASS=$((PASS+1)); echo "ok: (q9) status failure emits only the fixed warning"
else FAIL=$((FAIL+1)); echo "NG: (q9) status failure output differs from the fixed warning"; fi
assert_not_contains "(q9) status failure has no wrapper" "$out" "<personal-memory>"
assert_not_contains "(q9) status partial stdout is withheld" "$out" "PARTIAL-STATUS-BODY"
assert_not_contains "(q9) status failure withholds committed MEMORY" "$out" "STATUS-MEMORY-SENTINEL"
assert_not_contains "(q9) status failure withholds selected project" "$out" "STATUS-PROJECT-SENTINEL"
assert_not_contains "(q9) status failure withholds worktree body" "$out" "WORKTREE-STATUS-SENTINEL"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (q9) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (q9) exit code $rc"; fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
