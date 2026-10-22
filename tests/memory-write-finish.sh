#!/usr/bin/env bash
# finish が指定 path だけを publish し、成功・失敗のどちらでも lock を解放する契約を検証する。
set -u

case "$(uname -s)" in
  MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$REPO/agent-shared/bin/memory-write-finish.sh"
LOCK_HELPER="$REPO/agent-shared/bin/memory-write-lock.sh"
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

make_patch() {
  base="$(git -C "$CLONE" rev-parse HEAD)"
  patch="$TMP/$(basename "$CLONE").patch"
  printf '\n- prepared durable rule\n' >>"$SEED/CORE.md"
  git -C "$SEED" diff --binary HEAD -- CORE.md >"$patch"
}

make_fixture prepared || exit 1
make_patch
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: capture prepared rule" CORE.md >"$TMP/prepared.out" 2>"$TMP/prepared.err"
status=$?
if [ "$status" -eq 0 ] \
  && git -C "$ORIGIN" show main:CORE.md | grep -q 'prepared durable rule' \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "a prepared patch is published and released within one helper call"
else
  ng "a prepared patch is published and released within one helper call"
fi

make_fixture delete_add || exit 1
base="$(git -C "$CLONE" rev-parse HEAD)"
patch="$TMP/delete-add.patch"
rm "$SEED/CORE.md"
printf '# Replacement\n' >"$SEED/replacement.md"
git -C "$SEED" add -- CORE.md replacement.md
git -C "$SEED" diff --cached --binary HEAD >"$patch"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: replace obsolete topic" CORE.md replacement.md >"$TMP/delete-add.out" 2>"$TMP/delete-add.err"
status=$?
if [ "$status" -eq 0 ] && [ ! -e "$CLONE/CORE.md" ] \
  && [ -f "$CLONE/replacement.md" ] \
  && git -C "$ORIGIN" show main:replacement.md | grep -q '# Replacement' \
  && ! git -C "$ORIGIN" cat-file -e main:CORE.md 2>/dev/null \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "a patch can delete an obsolete topic and publish its replacement"
else
  ng "a patch can delete an obsolete topic and publish its replacement"
fi

make_fixture moved_topic || exit 1
base="$(git -C "$CLONE" rev-parse HEAD)"
mv "$SEED/CORE.md" "$SEED/TOPIC.md"
git -C "$SEED" add -N TOPIC.md
patch="$TMP/moved-topic.patch"
git -C "$SEED" diff --binary --no-renames HEAD -- CORE.md TOPIC.md >"$patch"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: move topic without losing content" CORE.md TOPIC.md >"$TMP/moved.out" 2>"$TMP/moved.err"
status=$?
if [ "$status" -eq 0 ] \
  && ! git -C "$ORIGIN" cat-file -e main:CORE.md 2>/dev/null \
  && git -C "$ORIGIN" show main:TOPIC.md | cmp -s - "$SEED/TOPIC.md" \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "explicit delete-and-add paths can preserve the complete moved topic"
else
  ng "explicit delete-and-add paths can preserve the complete moved topic"
fi

make_fixture stale || exit 1
make_patch
printf '\n- concurrent change\n' >>"$SEED/MEMORY.md"
git -C "$SEED" add MEMORY.md && git_commit "$SEED" concurrent
git -C "$SEED" push -q "$ORIGIN" main
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: capture prepared rule" CORE.md >"$TMP/stale.out" 2>"$TMP/stale.err"
status=$?
if [ "$status" -ne 0 ] && grep -q 'base commit changed' "$TMP/stale.err" \
  && ! grep -q 'prepared durable rule' "$CLONE/CORE.md" \
  && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "a draft based on an older commit is rejected after sync and releases its lock"
else
  ng "a draft based on an older commit is rejected after sync and releases its lock"
fi

make_fixture interrupted || exit 1
make_patch
mkdir "$TMP/bin"
export MEMORY_TEST_REAL_GIT
MEMORY_TEST_REAL_GIT=$(command -v git)
cat >"$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "${3:-}" = commit ]; then
  kill -TERM "$PPID"
  exit 143
fi
exec "$MEMORY_TEST_REAL_GIT" "$@"
EOF
chmod +x "$TMP/bin/git"
PATH="$TMP/bin:$PATH" AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: capture prepared rule" CORE.md >"$TMP/interrupted.out" 2>"$TMP/interrupted.err"
status=$?
if [ "$status" -eq 143 ] && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(find "$CLONE/.git/memory-write-state" -mindepth 1 -print 2>/dev/null)" ] \
  && grep -q 'prepared durable rule' "$CLONE/CORE.md" \
  && ! git -C "$ORIGIN" show main:CORE.md | grep -q 'prepared durable rule'; then
  ok "interruption after apply releases the lock and preserves the unpublished draft"
else
  ng "interruption after apply releases the lock and preserves the unpublished draft"
fi

make_fixture interrupted_preflight || exit 1
make_patch
cat >"$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "${3:-}" = pull ]; then
  kill -TERM "$MEMORY_TEST_FINISH_PID"
fi
exec "$MEMORY_TEST_REAL_GIT" "$@"
EOF
PATH="$TMP/bin:$PATH" AGENT_MEMORY_DIR="$CLONE" bash -c \
  'export MEMORY_TEST_FINISH_PID=$$; exec bash "$@"' _ \
  "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: interrupted preflight" CORE.md >"$TMP/interrupted_preflight.out" 2>"$TMP/interrupted_preflight.err"
status=$?
if [ "$status" -eq 143 ] && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(find "$CLONE/.git/memory-write-state" -mindepth 1 -print 2>/dev/null)" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "TERM while preflight owns the lock leaves no transferred handle or lock"
else
  ng "TERM while preflight owns the lock leaves no transferred handle or lock"
fi

make_fixture interrupted_acquire || exit 1
make_patch
cat >"$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
exec "$MEMORY_TEST_REAL_GIT" "$@"
EOF
export MEMORY_TEST_REAL_MKDIR
MEMORY_TEST_REAL_MKDIR=$(command -v mkdir)
cat >"$TMP/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
"$MEMORY_TEST_REAL_MKDIR" "$@" || exit $?
case "${1:-}" in
  */memory-write.lock) kill -TERM "$MEMORY_TEST_FINISH_PID" ;;
esac
EOF
chmod +x "$TMP/bin/mkdir"
PATH="$TMP/bin:$PATH" AGENT_MEMORY_DIR="$CLONE" bash -c \
  'export MEMORY_TEST_FINISH_PID=$$; exec bash "$@"' _ \
  "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: interrupted acquisition" CORE.md >"$TMP/interrupted_acquire.out" 2>"$TMP/interrupted_acquire.err"
status=$?
if [ "$status" -eq 143 ] && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(find "$CLONE/.git/memory-write-state" -mindepth 1 -print 2>/dev/null)" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "TERM during low-level acquisition releases the eventually transferred lock"
else
  ng "TERM during low-level acquisition releases the eventually transferred lock"
fi
rm "$TMP/bin/mkdir"

make_fixture invalidpatch || exit 1
make_patch
printf 'not a patch\n' >"$patch"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: invalid patch" CORE.md >"$TMP/invalidpatch.out" 2>"$TMP/invalidpatch.err"
status=$?
if [ "$status" -ne 0 ] && grep -q 'memory patch could not be applied' "$TMP/invalidpatch.err" \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$base" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "an invalid patch leaves the repo unchanged and releases its lock"
else
  ng "an invalid patch leaves the repo unchanged and releases its lock"
fi

make_fixture extra_patch_path || exit 1
make_patch
printf '\n- unexpected edit\n' >>"$SEED/MEMORY.md"
git -C "$SEED" diff --binary HEAD >"$patch"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: patch exceeds named paths" CORE.md >"$TMP/extra.out" 2>"$TMP/extra.err"
status=$?
if [ "$status" -ne 0 ] && grep -q 'unexpected patch path' "$TMP/extra.err" \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "patch paths are checked before applying any edits"
else
  ng "patch paths are checked before applying any edits"
fi

make_fixture concurrent || exit 1
make_patch
handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" --patch "$LINK" "$base" "$patch" \
  "memory: concurrent patch" CORE.md >"$TMP/concurrent.out" 2>"$TMP/concurrent.err"
status=$?
if [ "$status" -ne 0 ] && [ -d "$handle" ] \
  && [ -d "$CLONE/.git/memory-write.lock" ] \
  && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "a prepared patch preserves an existing writer's lock and repo"
else
  ng "a prepared patch preserves an existing writer's lock and repo"
fi
bash "$LOCK_HELPER" release "$handle" || exit 1

for failure in commit push; do
  make_fixture "failed_$failure" || exit 1
  make_patch
  cat >"$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "${3:-}" = "$MEMORY_TEST_FAIL_COMMAND" ]; then
  exit 1
fi
exec "$MEMORY_TEST_REAL_GIT" "$@"
EOF
  PATH="$TMP/bin:$PATH" MEMORY_TEST_FAIL_COMMAND="$failure" AGENT_MEMORY_DIR="$CLONE" \
    bash "$HELPER" --patch "$LINK" "$base" "$patch" \
    "memory: interrupted publication" CORE.md >"$TMP/$failure.out" 2>"$TMP/$failure.err"
  status=$?
  if [ "$status" -ne 0 ] && grep -q "memory $failure failed" "$TMP/$failure.err" \
    && [ ! -e "$CLONE/.git/memory-write.lock" ] \
    && [ -z "$(find "$CLONE/.git/memory-write-state" -mindepth 1 -print 2>/dev/null)" ] \
    && grep -q 'prepared durable rule' "$CLONE/CORE.md" \
    && [ "$(git -C "$ORIGIN" rev-parse main)" = "$base" ]; then
    ok "$failure failure releases the lock and keeps unpublished work recoverable"
  else
    ng "$failure failure releases the lock and keeps unpublished work recoverable"
  fi
done

make_fixture missingpaths || exit 1
handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$handle" \
  "memory: missing paths" >"$TMP/missingpaths.out" 2>"$TMP/missingpaths.err"
status=$?
if [ "$status" -eq 2 ] && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "invalid finish arguments still release a verified owning handle"
else
  ng "invalid finish arguments still release a verified owning handle"
fi

make_fixture missinglink || exit 1
handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$TMP/nonexistent-link" "$handle" \
  "memory: missing link" CORE.md >"$TMP/missinglink.out" 2>"$TMP/missinglink.err"
status=$?
if [ "$status" -ne 0 ] && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  ok "an inaccessible link still releases the canonical repo's owning handle"
else
  ng "an inaccessible link still releases the canonical repo's owning handle"
fi

make_fixture interrupted_resolve || exit 1
handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
export MEMORY_TEST_REAL_BASH
MEMORY_TEST_REAL_BASH=$(command -v bash)
printf '#!%s\n' "$MEMORY_TEST_REAL_BASH" >"$TMP/bin/bash"
cat >>"$TMP/bin/bash" <<'EOF'
case "${1:-}" in
  */resolve-memory-dir.sh) kill -TERM "$PPID" ;;
esac
exec "$MEMORY_TEST_REAL_BASH" "$@"
EOF
chmod +x "$TMP/bin/bash"
PATH="$TMP/bin:$PATH" AGENT_MEMORY_DIR="$CLONE" "$MEMORY_TEST_REAL_BASH" "$HELPER" \
  "$LINK" "$handle" "memory: interrupted resolution" CORE.md \
  >"$TMP/interrupted_resolve.out" 2>"$TMP/interrupted_resolve.err"
status=$?
rm "$TMP/bin/bash"
if [ "$status" -eq 143 ] && [ ! -e "$CLONE/.git/memory-write.lock" ] \
  && [ ! -e "$handle" ]; then
  ok "TERM during canonical resolution releases the received owning handle"
else
  ng "TERM during canonical resolution releases the received owning handle"
fi

make_fixture foreign_owner || exit 1
foreign_repo="$CLONE"
foreign_handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
make_fixture foreign_target || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$foreign_handle" \
  "memory: foreign owner" CORE.md >"$TMP/foreign.out" 2>"$TMP/foreign.err"
status=$?
if [ "$status" -ne 0 ] && [ -e "$foreign_repo/.git/memory-write.lock" ] \
  && [ -d "$foreign_handle" ] && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "a valid handle from another repo remains untouched"
else
  ng "a valid handle from another repo remains untouched"
fi
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$TMP/nonexistent-link" "$foreign_handle" \
  "memory: foreign owner and bad link" CORE.md >"$TMP/foreign-link.out" 2>"$TMP/foreign-link.err"
status=$?
if [ "$status" -ne 0 ] && [ -e "$foreign_repo/.git/memory-write.lock" ] \
  && [ -d "$foreign_handle" ]; then
  ok "early link failure cannot release another repo's valid handle"
else
  ng "early link failure cannot release another repo's valid handle"
fi
bash "$LOCK_HELPER" release "$foreign_handle" || exit 1

make_fixture wronghandle || exit 1
printf '\n- must remain unpublished\n' >>"$CLONE/CORE.md"
before="$(git -C "$CLONE" rev-parse HEAD)"
handle="$(bash "$LOCK_HELPER" acquire "$CLONE")" || exit 1
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" "$TMP/missing-handle" \
  "memory: invalid owner" CORE.md >"$TMP/wronghandle.out" 2>"$TMP/wronghandle.err"
status=$?
if [ "$status" -ne 0 ] && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ] \
  && [ -d "$handle" ] && [ -d "$CLONE/.git/memory-write.lock" ]; then
  ok "an invalid handle cannot publish changes owned by another writer"
else
  ng "an invalid handle cannot publish changes owned by another writer"
fi
bash "$LOCK_HELPER" release "$handle" || exit 1

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
