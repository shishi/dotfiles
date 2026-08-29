#!/usr/bin/env bash
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/agents/bin/memory-write-finish.sh"
LOCK_HELPER="$REPO/agents/bin/memory-write-lock.sh"
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-write-finish.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

git_commit() {
  git -C "$1" -c user.name=test -c user.email=test@example.com \
    -c commit.gpgsign=false commit -q -m "$2"
}

make_fixture() {
  local name=$1
  ORIGIN="$TMP_ROOT/$name-origin.git"
  SEED="$TMP_ROOT/$name-seed"
  CLONE="$TMP_ROOT/$name"
  LINK="$TMP_ROOT/$name-link"
  git init -q -b main "$SEED" \
    && printf '# Index\n' >"$SEED/MEMORY.md" \
    && printf '# Core\n' >"$SEED/CORE.md" \
    && git -C "$SEED" add MEMORY.md CORE.md \
    && git_commit "$SEED" init \
    && git init -q --bare -b main "$ORIGIN" \
    && git -C "$SEED" push -q "$ORIGIN" main \
    && git clone -q "$ORIGIN" "$CLONE" \
    && git -C "$CLONE" config user.name test \
    && git -C "$CLONE" config user.email test@example.com \
    && git -C "$CLONE" config commit.gpgsign false \
    && ln -s "$CLONE" "$LINK"
}

acquire() { bash "$LOCK_HELPER" acquire "$CLONE"; }

if [ ! -x "$HELPER" ]; then
  fail "finish helper exists and is executable"
  exit 1
fi

make_fixture happy || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
printf '\n- [Core](CORE.md)\n' >>"$CLONE/MEMORY.md"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md MEMORY.md \
  >"$TMP_ROOT/happy.out" 2>"$TMP_ROOT/happy.err"
status=$?
paths="$(git -C "$CLONE" diff-tree --no-commit-id --name-only -r HEAD | sort)"
if [ "$status" -eq 0 ] \
  && [ "$paths" = $'CORE.md\nMEMORY.md' ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  pass "one call publishes only named paths and releases the lock"
else
  fail "happy path did not complete the capture (status=$status)"
fi

make_fixture unexpected || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
printf 'unrelated\n' >"$CLONE/scratch.txt"
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md \
  >"$TMP_ROOT/unexpected.out" 2>"$TMP_ROOT/unexpected.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  pass "unexpected changes abort before commit and release the lock"
else
  fail "unexpected changes were committed or leaked the lock (status=$status)"
fi

make_fixture pushfail || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
printf '#!/usr/bin/env bash\nexit 1\n' >"$ORIGIN/hooks/pre-receive"
chmod +x "$ORIGIN/hooks/pre-receive"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md \
  >"$TMP_ROOT/pushfail.out" 2>"$TMP_ROOT/pushfail.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ "$(git -C "$ORIGIN" rev-parse main)" != "$(git -C "$CLONE" rev-parse HEAD)" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  pass "push failure is reported and releases the lock"
else
  fail "push failure was hidden or leaked the lock (status=$status)"
fi

make_fixture earlyfail || exit 1
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$TMP_ROOT/missing" "$handle" \
  "memory: capture durable rule" CORE.md \
  >"$TMP_ROOT/earlyfail.out" 2>"$TMP_ROOT/earlyfail.err"
status=$?
if [ "$status" -ne 0 ] && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  pass "validation failure releases the supplied lock"
else
  fail "validation failure leaked the lock (status=$status)"
fi

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
