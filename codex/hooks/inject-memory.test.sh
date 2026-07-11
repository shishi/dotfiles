#!/usr/bin/env bash
# inject-memory.sh の単体テスト。fake HOME を組み立てて hook を直接叩く。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/inject-memory.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

run_hook() { # $1=cwd [$2=memory_dir]
  if [ $# -ge 2 ]; then
    printf '{"cwd":"%s"}' "$1" | HOME="$TMP/home" bash "$HOOK" "$2"
  else
    printf '{"cwd":"%s"}' "$1" | HOME="$TMP/home" bash "$HOOK"
  fi
}
assert_contains() { # $1=desc $2=haystack $3=needle
  if printf '%s' "$2" | grep -qF -- "$3"; then PASS=$((PASS+1)); echo "ok: $1"
  else FAIL=$((FAIL+1)); echo "NG: $1 (missing: $3)"; fi
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
GITC="git -c user.name=t -c user.email=t@t"
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

# (j) main 以外のブランチ -> 警告のみ
make_repo_mem "$TMP/branchmem"
git -C "$TMP/branchmem" switch -qc consolidation/2026-07-12
out=$(run_hook "$TMP" "$TMP/branchmem")
assert_contains "(j) non-main branch warns" "$out" "personal-memory-warning"
if printf '%s' "$out" | grep -qF "REPO-MEMORY"; then FAIL=$((FAIL+1)); echo "NG: (j) body injected"
else PASS=$((PASS+1)); echo "ok: (j) body not injected"; fi

# (k) dirty worktree -> 警告のみ
make_repo_mem "$TMP/dirtymem"
printf 'draft\n' >> "$TMP/dirtymem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/dirtymem")
assert_contains "(k) dirty worktree warns" "$out" "personal-memory-warning"

# (l) write lock -> 警告のみ
make_repo_mem "$TMP/lockmem"
mkdir "$TMP/lockmem/.git/memory-write.lock"
out=$(run_hook "$TMP" "$TMP/lockmem")
assert_contains "(l) write lock warns" "$out" "personal-memory-warning"

# (o) MEMORY.md が削除された dirty repo -> 警告(無言スキップに落とさない)
make_repo_mem "$TMP/delmem"
rm "$TMP/delmem/MEMORY.md"
out=$(run_hook "$TMP" "$TMP/delmem")
assert_contains "(o) deleted MEMORY.md warns" "$out" "personal-memory-warning"

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

# (n) snapshot 読み: HEAD commit 後の未 stage 編集は注入されない(dirty 警告側に落ちる)
#     ※ clean チェックがある限り worktree==HEAD なので、snapshot 読みの直接検証は
#       「commit 済み内容が出る」(i) と「dirty は注入しない」(k) の組で担保する

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
