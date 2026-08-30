#!/usr/bin/env bash
# finish が指定 path だけを publish し、成功・失敗のどちらでも lock を解放する契約を検証する。
set -u

case "$(uname -s)" in
  MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$REPO/agents/bin/memory-write-finish.sh"
LOCK_HELPER="$REPO/agents/bin/memory-write-lock.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/memory-write-finish.XXXXXX")" || exit 1
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
    && printf '# Index\n' >"$SEED/MEMORY.md" \
    && printf '# Core\n' >"$SEED/CORE.md" \
    && git -C "$SEED" add MEMORY.md CORE.md \
    && git_commit "$SEED" init \
    && git init -q --bare -b main "$ORIGIN" \
    && git -C "$SEED" push -q "$ORIGIN" main \
    && git clone -q "$ORIGIN" "$CLONE" \
    && git -C "$CLONE" config user.name test \
    && git -C "$CLONE" config user.email test@example.invalid \
    && git -C "$CLONE" config commit.gpgsign false \
    && ln -s "$CLONE" "$LINK"
}

make_fixture happy || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md >"$TMP/happy.out" 2>"$TMP/happy.err"
status=$?
paths="$(git -C "$CLONE" diff-tree --no-commit-id --name-only -r HEAD)"
if [ "$status" -eq 0 ] && [ "$paths" = CORE.md ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "success publishes only the named path and releases the lock"
else
  ng "success publishes only the named path and releases the lock"
fi

make_fixture unexpected || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
printf 'unrelated\n' >"$CLONE/scratch.txt"
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md >"$TMP/unexpected.out" 2>"$TMP/unexpected.err"
status=$?
if [ "$status" -ne 0 ] && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "unexpected changes abort before commit and release the lock"
else
  ng "unexpected changes abort before commit and release the lock"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
