#!/usr/bin/env bash
# preflight が同期済み repo の lock だけを呼び出し側へ渡す契約を検証する。
set -u

case "$(uname -s)" in
  MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$REPO/agent-shared/bin/memory-write-preflight.sh"
LOCK_HELPER="$REPO/agent-shared/bin/memory-write-lock.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/memory-write-preflight.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

git_commit() {
  git -C "$1" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false commit -qm "$2"
}

make_fixture() {
  local name="$1"
  ORIGIN="$TMP/$name-origin.git"
  SEED="$TMP/$name-seed"
  CLONE="$TMP/$name"
  LINK="$TMP/$name-link"
  git init -q -b main "$SEED" \
    && printf '# Conventions\n' >"$SEED/CONVENTIONS.md" \
    && git -C "$SEED" add CONVENTIONS.md \
    && git_commit "$SEED" init \
    && git init -q --bare -b main "$ORIGIN" \
    && git -C "$SEED" push -q "$ORIGIN" main \
    && git clone -q "$ORIGIN" "$CLONE" \
    && ln -s "$CLONE" "$LINK"
}

make_fixture happy || exit 1
printf 'updated\n' >>"$SEED/CONVENTIONS.md"
git -C "$SEED" add CONVENTIONS.md && git_commit "$SEED" update
git -C "$SEED" push -q "$ORIGIN" main
handle="$(AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" 2>"$TMP/happy.err")"
status=$?
if [ "$status" -eq 0 ] && [ -d "$handle" ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ]; then
  ok "success pulls origin/main and transfers a live lock handle"
else
  ng "success pulls origin/main and transfers a live lock handle"
fi
if bash "$LOCK_HELPER" release "$handle" 2>"$TMP/release.err"; then
  ok "the transferred handle can be released"
else
  ng "the transferred handle can be released"
fi

make_fixture dirty || exit 1
printf 'uncommitted\n' >"$CLONE/scratch.txt"
out="$(AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" 2>"$TMP/dirty.err")"
status=$?
if [ "$status" -ne 0 ] && [ -z "$out" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "dirty worktree is rejected without leaking a lock"
else
  ng "dirty worktree is rejected without leaking a lock"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
