#!/usr/bin/env bash
# Memory write finalizer contract: one call commits, pushes, verifies, and releases.
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/agents/bin/memory-write-finish.sh"
LOCK_HELPER="$REPO/agents/bin/memory-write-lock.sh"
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-write-finish.XXXXXX")" || exit 1
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

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
    && printf 'rules\n' >"$SEED/CONVENTIONS.md" \
    && git -C "$SEED" add MEMORY.md CORE.md CONVENTIONS.md \
    && git_commit "$SEED" init \
    && git init -q --bare -b main "$ORIGIN" \
    && git -C "$SEED" push -q "$ORIGIN" main \
    && git clone -q "$ORIGIN" "$CLONE" \
    && git -C "$CLONE" config user.name test \
    && git -C "$CLONE" config user.email test@example.com \
    && git -C "$CLONE" config commit.gpgsign false \
    && ln -s "$CLONE" "$LINK"
}

acquire() {
  bash "$LOCK_HELPER" acquire "$CLONE"
}

if [ ! -x "$HELPER" ]; then
  fail "finish helper exists and is executable"
  echo
  echo "PASS/FAIL: FAILURES=$FAILURES"
  exit 1
fi

make_fixture happy || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
printf '\n- [Core](CORE.md)\n' >>"$CLONE/MEMORY.md"
handle="$(acquire)" || exit 1
out="$TMP_ROOT/happy.out"; err="$TMP_ROOT/happy.err"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md MEMORY.md >"$out" 2>"$err"
status=$?
if [ "$status" -eq 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  pass "one call commits, pushes, verifies, and releases the lock"
else
  fail "happy path did not finish the complete transaction (status=$status)"
fi
actual_paths="$(git -C "$CLONE" diff-tree --no-commit-id --name-only -r HEAD | sort)"
if [ "$actual_paths" = $'CORE.md\nMEMORY.md' ]; then
  pass "only explicitly named memory paths are committed"
else
  fail "commit contains unexpected paths: $actual_paths"
fi

make_fixture missinglink || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$TMP_ROOT/does-not-exist" "$handle" \
  "memory: capture durable rule" CORE.md >"$TMP_ROOT/missinglink.out" 2>"$TMP_ROOT/missinglink.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  pass "missing memory link fails before Git mutation and releases the lock"
else
  fail "missing memory link leaked the lock (status=$status)"
  bash "$LOCK_HELPER" release "$handle" 2>/dev/null || true
fi

make_fixture missingpath || exit 1
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" >"$TMP_ROOT/missingpath.out" 2>"$TMP_ROOT/missingpath.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  pass "missing path argument reports usage and releases the supplied lock"
else
  fail "missing path argument leaked the supplied lock (status=$status)"
  bash "$LOCK_HELPER" release "$handle" 2>/dev/null || true
fi

make_fixture badresolver || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$TMP_ROOT/not-a-repo" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md >"$TMP_ROOT/badresolver.out" 2>"$TMP_ROOT/badresolver.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  pass "resolver failure occurs before Git mutation and releases the lock"
else
  fail "resolver failure leaked the lock (status=$status)"
  bash "$LOCK_HELPER" release "$handle" 2>/dev/null || true
fi

make_fixture earlysignal || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(acquire)" || exit 1
marker="$TMP_ROOT/earlysignal.marker"
AGENT_MEMORY_DIR="$CLONE" FINISH_TEST_MARKER="$marker" FINISH_PAUSE_AFTER_TRAP=3 \
  bash "$HELPER" "$LINK" "$handle" "memory: capture durable rule" CORE.md \
  >"$TMP_ROOT/earlysignal.out" 2>"$TMP_ROOT/earlysignal.err" &
finish_pid=$!
i=0
while [ ! -e "$marker" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
kill -TERM "$finish_pid" 2>/dev/null
wait "$finish_pid"
status=$?
if [ "$i" -lt 100 ] && [ "$status" -ne 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  pass "signal immediately after trap setup releases the lock"
else
  fail "early signal leaked the lock or mutated Git (status=$status, i=$i)"
  bash "$LOCK_HELPER" release "$handle" 2>/dev/null || true
fi

make_fixture fakehandle || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
before="$(git -C "$CLONE" rev-parse HEAD)"
real_handle="$(acquire)" || exit 1
fake_handle="$CLONE/.git/memory-write-state/handle.fake"
mkdir "$fake_handle"
printf '%s\n' "$CLONE" >"$fake_handle/repo"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$fake_handle" \
  "memory: capture durable rule" CORE.md >"$TMP_ROOT/fakehandle.out" 2>"$TMP_ROOT/fakehandle.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ "$(git -C "$ORIGIN" rev-parse main)" = "$before" ] \
  && [ -e "$CLONE/.git/memory-write.lock" ] \
  && [ -e "$real_handle" ]; then
  pass "unowned handle is rejected before any Git mutation"
else
  fail "unowned handle reached Git mutation or damaged the real lock (status=$status)"
fi
rm -rf "$fake_handle"
bash "$LOCK_HELPER" release "$real_handle" || fail "real lock cleanup after fake handle test failed"

make_fixture unexpected || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
printf 'unrelated\n' >"$CLONE/scratch.txt"
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md >"$TMP_ROOT/unexpected.out" 2>"$TMP_ROOT/unexpected.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  pass "unexpected worktree changes abort before commit and still release the lock"
else
  fail "unexpected changes were committed or leaked the lock (status=$status)"
fi

make_fixture pushfail || exit 1
printf '\n- durable rule\n' >>"$CLONE/CORE.md"
cat >"$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$ORIGIN/hooks/pre-receive"
handle="$(acquire)" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: capture durable rule" CORE.md >"$TMP_ROOT/pushfail.out" 2>"$TMP_ROOT/pushfail.err"
status=$?
if [ "$status" -ne 0 ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ] \
  && [ "$(git -C "$ORIGIN" rev-parse main)" != "$(git -C "$CLONE" rev-parse HEAD)" ]; then
  pass "push failure is reported and releases the lock"
else
  fail "push failure was hidden or leaked the lock (status=$status)"
fi

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
