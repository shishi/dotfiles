#!/usr/bin/env bash
# Memory write preflight helper runtime contract.
# Covers bootstrap steps 1-4 (resolve / link check / lock / sync) as one call.
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/agents/bin/memory-write-preflight.sh"
LOCK_HELPER="$REPO/agents/bin/memory-write-lock.sh"
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-write-preflight.XXXXXX")" || exit 1
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)" || exit 1
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

git_commit() {
  git -C "$1" -c user.name=test -c user.email=test@example.com \
    -c commit.gpgsign=false commit -q -m "$2"
}

# Build origin (bare) + clone + symlink for one scenario.
# Sets: ORIGIN, SEED, CLONE, LINK.
make_fixture() {
  local name="$1"
  ORIGIN="$TMP_ROOT/$name-origin.git"
  SEED="$TMP_ROOT/$name-seed"
  CLONE="$TMP_ROOT/$name"
  LINK="$TMP_ROOT/$name-link"
  git init -q -b main "$SEED" \
    && printf 'conventions\n' >"$SEED/CONVENTIONS.md" \
    && git -C "$SEED" add -A \
    && git_commit "$SEED" init \
    && git init -q --bare -b main "$ORIGIN" \
    && git -C "$SEED" push -q "$ORIGIN" main \
    && git clone -q "$ORIGIN" "$CLONE" \
    && ln -s "$CLONE" "$LINK"
}

# Push one more commit to origin so the clone is behind.
advance_origin() {
  printf 'more\n' >>"$SEED/CONVENTIONS.md" \
    && git -C "$SEED" add -A \
    && git_commit "$SEED" advance \
    && git -C "$SEED" push -q "$ORIGIN" main
}

run_preflight() {
  local stdout_file="$1" stderr_file="$2" repo="$3" link="$4"
  AGENT_MEMORY_DIR="$repo" bash "$HELPER" "$link" \
    >"$stdout_file" 2>"$stderr_file"
}

# git を選択的に失敗・遅延させる PATH shim。挙動は env で切り替える:
#   GIT_SHIM_PULL_MARKER  pull 開始時に touch するファイル
#   GIT_SHIM_PULL_SLEEP   pull 前に sleep する秒数
#   GIT_SHIM_STATUS_FAIL  1 なら status を空出力のまま非ゼロで落とす
SHIM_DIR="$TMP_ROOT/git-shim"
make_git_shim() {
  local real_git
  real_git="$(command -v git)" || return 1
  mkdir -p "$SHIM_DIR"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'for arg in "$@"; do\n'
    printf '  case "$arg" in\n'
    printf '    pull)\n'
    printf '      [ -n "${GIT_SHIM_PULL_MARKER:-}" ] && : >"$GIT_SHIM_PULL_MARKER"\n'
    printf '      [ -n "${GIT_SHIM_PULL_SLEEP:-}" ] && sleep "$GIT_SHIM_PULL_SLEEP"\n'
    printf '      ;;\n'
    printf '    status)\n'
    printf '      [ "${GIT_SHIM_STATUS_FAIL:-}" = 1 ] && exit 1\n'
    printf '      ;;\n'
    printf '  esac\n'
    printf 'done\n'
    printf 'exec %s "$@"\n' "$real_git"
  } >"$SHIM_DIR/git"
  chmod +x "$SHIM_DIR/git"
}

lock_dir_of() { printf '%s\n' "$1/.git/memory-write.lock"; }

if [ ! -f "$HELPER" ]; then
  fail "preflight helper exists"
  echo
  echo "PASS/FAIL: FAILURES=$FAILURES"
  exit 1
fi

# --- happy path: behind clone is pulled, handle returned, lock held ---
make_fixture happy || exit 1
advance_origin || exit 1
out="$TMP_ROOT/happy.out"; err="$TMP_ROOT/happy.err"
run_preflight "$out" "$err" "$CLONE" "$LINK"
status=$?
handle="$(sed -n '1p' "$out")"
case "$handle" in
  "$CLONE/.git/memory-write-state/handle."*) handle_shape=true ;;
  *) handle_shape=false ;;
esac
if [ "$status" -eq 0 ] && [ "$(wc -l <"$out" | tr -d ' ')" -eq 1 ] \
  && [ "$handle_shape" = true ] && [ -d "$handle" ] \
  && [ -d "$(lock_dir_of "$CLONE")" ]; then
  pass "success emits exactly one handle line and keeps the lock held"
else
  fail "success output or lock state is wrong (status=$status)"
fi
if [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ]; then
  pass "success syncs the clone to origin/main (pull happened)"
else
  fail "clone was not synced to origin/main"
fi
release_err="$TMP_ROOT/happy-release.err"
if bash "$LOCK_HELPER" release "$handle" 2>"$release_err" \
  && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "returned handle releases the lock via the lock helper"
else
  fail "returned handle could not release the lock"
fi

# --- link mismatch: refuses before taking the lock ---
make_fixture mismatch || exit 1
mkdir "$TMP_ROOT/elsewhere"
rm "$LINK" && ln -s "$TMP_ROOT/elsewhere" "$LINK"
out="$TMP_ROOT/mismatch.out"; err="$TMP_ROOT/mismatch.err"
run_preflight "$out" "$err" "$CLONE" "$LINK"
if [ $? -ne 0 ] && [ ! -s "$out" ] && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "link that resolves elsewhere fails with no stdout and no lock"
else
  fail "link mismatch was not rejected cleanly"
fi

# --- dirty worktree: fails and releases the lock it acquired ---
make_fixture dirty || exit 1
printf 'uncommitted\n' >"$CLONE/scratch.txt"
out="$TMP_ROOT/dirty.out"; err="$TMP_ROOT/dirty.err"
run_preflight "$out" "$err" "$CLONE" "$LINK"
if [ $? -ne 0 ] && [ ! -s "$out" ] && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "dirty worktree fails and leaves no lock behind"
else
  fail "dirty worktree did not fail cleanly"
fi

# --- ahead of origin: fails and releases the lock ---
make_fixture ahead || exit 1
printf 'local only\n' >>"$CLONE/CONVENTIONS.md"
git -C "$CLONE" add -A && git_commit "$CLONE" local-only
out="$TMP_ROOT/ahead.out"; err="$TMP_ROOT/ahead.err"
run_preflight "$out" "$err" "$CLONE" "$LINK"
if [ $? -ne 0 ] && [ ! -s "$out" ] && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "clone ahead of origin fails and leaves no lock behind"
else
  fail "ahead clone did not fail cleanly"
fi

# --- wrong branch: fails and releases the lock ---
make_fixture branch || exit 1
git -C "$CLONE" checkout -q -b feature
out="$TMP_ROOT/branch.out"; err="$TMP_ROOT/branch.err"
run_preflight "$out" "$err" "$CLONE" "$LINK"
if [ $? -ne 0 ] && [ ! -s "$out" ] && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "non-main branch fails and leaves no lock behind"
else
  fail "non-main branch did not fail cleanly"
fi

# --- lock already held by someone else: fails without touching that lock ---
make_fixture held || exit 1
held_out="$TMP_ROOT/held-acquire.out"; held_err="$TMP_ROOT/held-acquire.err"
bash "$LOCK_HELPER" acquire "$CLONE" >"$held_out" 2>"$held_err" || exit 1
foreign_handle="$(sed -n '1p' "$held_out")"
out="$TMP_ROOT/held.out"; err="$TMP_ROOT/held.err"
run_preflight "$out" "$err" "$CLONE" "$LINK"
if [ $? -ne 0 ] && [ ! -s "$out" ] && [ -d "$(lock_dir_of "$CLONE")" ]; then
  pass "held lock fails preflight and the foreign lock survives"
else
  fail "held lock was not respected"
fi
bash "$LOCK_HELPER" release "$foreign_handle" || fail "foreign lock cleanup failed"

make_git_shim || { fail "git shim could not be created"; echo; echo "PASS/FAIL: FAILURES=$FAILURES"; exit 1; }

# --- SIGTERM while holding the lock: the lock is released, not leaked ---
make_fixture signal || exit 1
out="$TMP_ROOT/signal.out"; err="$TMP_ROOT/signal.err"
marker="$TMP_ROOT/signal-pull-started"
AGENT_MEMORY_DIR="$CLONE" PATH="$SHIM_DIR:$PATH" \
  GIT_SHIM_PULL_MARKER="$marker" GIT_SHIM_PULL_SLEEP=2 \
  bash "$HELPER" "$LINK" >"$out" 2>"$err" &
preflight_pid=$!
i=0
while [ ! -e "$marker" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
kill -TERM "$preflight_pid" 2>/dev/null
wait "$preflight_pid"
status=$?
if [ -e "$marker" ] && [ "$status" -ne 0 ] && [ ! -s "$out" ] \
  && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "SIGTERM while holding the lock releases it and exits nonzero"
else
  fail "SIGTERM leaked the lock (status=$status)"
fi

# --- closed stdout: handle cannot be transferred, so the lock is released ---
make_fixture nostdout || exit 1
err="$TMP_ROOT/nostdout.err"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" >&- 2>"$err"
if [ $? -ne 0 ] && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "closed stdout fails the transfer and leaves no lock behind"
else
  fail "closed stdout was treated as success or leaked the lock"
fi

# --- git status failing silently: not mistaken for a clean worktree ---
make_fixture gitfail || exit 1
out="$TMP_ROOT/gitfail.out"; err="$TMP_ROOT/gitfail.err"
AGENT_MEMORY_DIR="$CLONE" PATH="$SHIM_DIR:$PATH" GIT_SHIM_STATUS_FAIL=1 \
  bash "$HELPER" "$LINK" >"$out" 2>"$err"
if [ $? -ne 0 ] && [ ! -s "$out" ] && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "silent git status failure is rejected, not treated as clean"
else
  fail "silent git status failure passed as clean"
fi

# --- signal in the acquire boundary (before pull starts): lock is released ---
make_fixture boundary1 || exit 1
out="$TMP_ROOT/boundary1.out"; err="$TMP_ROOT/boundary1.err"
AGENT_MEMORY_DIR="$CLONE" PREFLIGHT_PAUSE_AFTER_ACQUIRE=3 \
  bash "$HELPER" "$LINK" >"$out" 2>"$err" &
preflight_pid=$!
i=0
while [ ! -d "$(lock_dir_of "$CLONE")" ] && [ "$i" -lt 100 ]; do
  sleep 0.1; i=$((i + 1))
done
kill -TERM "$preflight_pid" 2>/dev/null
wait "$preflight_pid"
status=$?
if [ "$i" -lt 100 ] && [ "$status" -ne 0 ] && [ ! -s "$out" ] \
  && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "signal right after acquire still releases the lock"
else
  fail "signal right after acquire leaked the lock (status=$status, i=$i)"
fi

# --- signal just before exit: the success contract is already committed ---
# handle を観測した実行が nonzero で終わると、呼び出し側は有効な handle を捨てる。
make_fixture boundary2 || exit 1
out="$TMP_ROOT/boundary2.out"; err="$TMP_ROOT/boundary2.err"
AGENT_MEMORY_DIR="$CLONE" PREFLIGHT_PAUSE_BEFORE_EXIT=3 \
  bash "$HELPER" "$LINK" >"$out" 2>"$err" &
preflight_pid=$!
i=0
while [ ! -s "$out" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
kill -TERM "$preflight_pid" 2>/dev/null
wait "$preflight_pid"
status=$?
handle="$(sed -n '1p' "$out")"
if [ "$i" -lt 100 ] && [ "$status" -eq 0 ] && [ -d "$handle" ] \
  && [ -d "$(lock_dir_of "$CLONE")" ] \
  && bash "$LOCK_HELPER" release "$handle" 2>/dev/null \
  && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "signal just before exit keeps the success contract intact"
else
  fail "signal just before exit broke the success contract (status=$status, i=$i)"
fi

# --- signal right after the handle is printed: nonzero-implies-empty-stdout ---
# 契約: stdout に handle が出た実行は exit 0 で終わる(呼び出し側は nonzero の
# 出力を捨てるため、handle 出力済み + nonzero は誰も解放しない lock を作る)。
make_fixture boundary3 || exit 1
out="$TMP_ROOT/boundary3.out"; err="$TMP_ROOT/boundary3.err"
AGENT_MEMORY_DIR="$CLONE" PREFLIGHT_PAUSE_AFTER_TRANSFER=3 \
  bash "$HELPER" "$LINK" >"$out" 2>"$err" &
preflight_pid=$!
i=0
while [ ! -s "$out" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
kill -TERM "$preflight_pid" 2>/dev/null
wait "$preflight_pid"
status=$?
handle="$(sed -n '1p' "$out")"
if [ "$i" -lt 100 ] && [ "$status" -eq 0 ] && [ -d "$handle" ] \
  && [ -d "$(lock_dir_of "$CLONE")" ] \
  && bash "$LOCK_HELPER" release "$handle" 2>/dev/null \
  && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "signal right after handle transfer still exits 0 with a usable handle"
else
  fail "printed handle was invalidated by a nonzero exit (status=$status, i=$i)"
fi

# --- stdout reader gone (SIGPIPE): fails cleanly and releases the lock ---
make_fixture pipebreak || exit 1
err="$TMP_ROOT/pipebreak.err"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" 2>"$err" | :
status="${PIPESTATUS[0]}"
if [ "$status" -ne 0 ] && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "broken stdout pipe fails cleanly and leaves no lock behind"
else
  fail "broken stdout pipe leaked the lock (status=$status)"
fi

# --- resolver output with dot segments: physically canonical repo is accepted ---
make_fixture dotted || exit 1
out="$TMP_ROOT/dotted.out"; err="$TMP_ROOT/dotted.err"
run_preflight "$out" "$err" "$TMP_ROOT/dotted-seed/../dotted" "$LINK"
status=$?
handle="$(sed -n '1p' "$out")"
if [ "$status" -eq 0 ] && [ -d "$handle" ] \
  && [ -d "$(lock_dir_of "$CLONE")" ] \
  && bash "$LOCK_HELPER" release "$handle" 2>/dev/null \
  && [ ! -e "$(lock_dir_of "$CLONE")" ]; then
  pass "dot-segment resolver path is normalized before acquiring the lock"
else
  fail "physically canonical repo was rejected over path spelling (status=$status)"
fi

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
