#!/usr/bin/env bash
# inject-memory.sh の単体テスト。fake HOME を組み立てて hook を直接叩く。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/inject-memory.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

run_hook() { # $1=cwd
  printf '{"cwd":"%s"}' "$1" | HOME="$TMP/home" bash "$HOOK"
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

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
