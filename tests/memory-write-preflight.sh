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

make_fixture reader || exit 1
printf '# Index\nREMOTE_MEMORY\n' >"$SEED/MEMORY.md"
git -C "$SEED" add MEMORY.md && git_commit "$SEED" remote-memory
git -C "$SEED" push -q "$ORIGIN" main
out=$(printf '{}' | AGENT_MEMORY_DIR="$CLONE" bash "$REPO/agent-shared/hooks/inject-memory.sh" "$LINK")
if printf '%s' "$out" | grep -q REMOTE_MEMORY \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ] \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "session startup syncs remote memory and releases its own lock"
else
  ng "session startup syncs remote memory and releases its own lock"
fi

# Advance remote again, then ensure a concurrent writer and drafts are preserved.
printf '\nSECOND_REMOTE_MEMORY\n' >>"$SEED/MEMORY.md"
git -C "$SEED" add MEMORY.md && git_commit "$SEED" next-remote-memory
git -C "$SEED" push -q "$ORIGIN" main
handle=$(bash "$LOCK_HELPER" acquire "$CLONE")
head_before=$(git -C "$CLONE" rev-parse HEAD)
out=$(printf '{}' | AGENT_MEMORY_DIR="$CLONE" bash "$REPO/agent-shared/hooks/inject-memory.sh" "$LINK")
if printf '%s' "$out" | grep -q '未同期' && ! printf '%s' "$out" | grep -q SECOND_REMOTE_MEMORY \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$head_before" ] && [ -d "$handle" ]; then
  ok "reader retains committed memory without touching another writer's lock"
else
  ng "reader retains committed memory without touching another writer's lock"
fi
bash "$LOCK_HELPER" release "$handle"
printf 'DRAFT_MEMORY\n' >>"$CLONE/MEMORY.md"
out=$(printf '{}' | AGENT_MEMORY_DIR="$CLONE" bash "$REPO/agent-shared/hooks/inject-memory.sh" "$LINK")
if printf '%s' "$out" | grep -q '未同期' && ! printf '%s' "$out" | grep -q DRAFT_MEMORY \
  && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$head_before" ] \
  && grep -q DRAFT_MEMORY "$CLONE/MEMORY.md" && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "reader keeps drafts untouched and injects only committed content"
else
  ng "reader keeps drafts untouched and injects only committed content"
fi
git -C "$CLONE" restore MEMORY.md
git -C "$CLONE" remote set-url origin "$TMP/missing-remote.git"
out=$(printf '{}' | AGENT_MEMORY_DIR="$CLONE" bash "$REPO/agent-shared/hooks/inject-memory.sh" "$LINK")
if printf '%s' "$out" | grep -q REMOTE_MEMORY && printf '%s' "$out" | grep -q '未同期' \
  && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "offline startup uses committed memory with an explicit sync warning"
else
  ng "offline startup uses committed memory with an explicit sync warning"
fi

# The remote side is replaced through upload-pack because Windows Python does not
# resolve a git stub placed on the MSYS PATH.
make_upload_pack() { # $1=script path $2=body run before serving the fetch
  printf '#!/usr/bin/env bash
%s
exec git upload-pack "$@"
' "$2" >"$1"
  chmod +x "$1"
}

# The network wait must not block writers: the write lock is taken only for the local update.
make_fixture network || exit 1
make_upload_pack "$TMP/record-upload-pack"   "if [ -e '$CLONE/.git/memory-write.lock' ]; then echo held; else echo free; fi >>'$TMP/fetch.log'"
git -C "$CLONE" config remote.origin.uploadpack "$TMP/record-upload-pack"
printf 'network update
' >>"$SEED/CONVENTIONS.md"
git -C "$SEED" add CONVENTIONS.md && git_commit "$SEED" network-update
git -C "$SEED" push -q "$ORIGIN" main
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" --read-sync 2>"$TMP/network.err"
status=$?
if [ "$status" -eq 0 ] && [ "$(cat "$TMP/fetch.log" 2>/dev/null)" = free ]   && [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ]   && [ "$(git -C "$CLONE" rev-parse origin/main)" = "$(git -C "$ORIGIN" rev-parse main)" ]   && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "read sync fetches without holding the write lock and still fast-forwards"
else
  ng "read sync fetches without holding the write lock and still fast-forwards"
fi
# Already in sync, but a writer holds the lock: the reader must not claim to be synchronized.
handle=$(bash "$LOCK_HELPER" acquire "$CLONE")
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" --read-sync 2>"$TMP/held.err"
status=$?
if [ "$status" -ne 0 ] && [ -d "$handle" ] && grep -q 'write lock is held or needs recovery' "$TMP/held.err"; then
  ok "an up-to-date read sync still reports a writer's lock as unsynchronized"
else
  ng "an up-to-date read sync still reports a writer's lock as unsynchronized"
fi
bash "$LOCK_HELPER" release "$handle"

# A stuck transport must finish well within the startup hook timeout and leave no lock.
make_upload_pack "$TMP/stuck-upload-pack" "sleep 20"
git -C "$CLONE" config remote.origin.uploadpack "$TMP/stuck-upload-pack"
printf 'unreachable update
' >>"$SEED/CONVENTIONS.md"
git -C "$SEED" add CONVENTIONS.md && git_commit "$SEED" unreachable-update
git -C "$SEED" push -q "$ORIGIN" main
started=$SECONDS
out=$(AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" --read-sync 2>"$TMP/timeout.err")
status=$?
if [ "$status" -ne 0 ] && [ $((SECONDS - started)) -lt 15 ]   && grep -q 'timed out' "$TMP/timeout.err" && [ ! -e "$CLONE/.git/memory-write.lock" ]; then
  ok "read sync bounds network wait and releases the lock on timeout"
else
  ng "read sync bounds network wait and releases the lock on timeout"
fi

# The unlocked fetch must not touch the refs a writer uses, even while the writer holds the lock.
make_fixture refs || exit 1
handle=$(bash "$LOCK_HELPER" acquire "$CLONE")
tracking_before=$(git -C "$CLONE" rev-parse origin/main)
printf 'writer-time update\n' >>"$SEED/CONVENTIONS.md"
git -C "$SEED" add CONVENTIONS.md && git_commit "$SEED" writer-time-update
git -C "$SEED" push -q "$ORIGIN" main
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" --read-sync 2>"$TMP/refs.err"
status=$?
if [ "$status" -ne 0 ] && [ "$(git -C "$CLONE" rev-parse origin/main)" = "$tracking_before" ] \
  && [ "$(git -C "$CLONE" rev-parse refs/memory-read-sync/main)" = "$(git -C "$ORIGIN" rev-parse main)" ] \
  && [ ! -e "$CLONE/.git/FETCH_HEAD" ] && [ -d "$handle" ]; then
  ok "read sync leaves origin/main and FETCH_HEAD to the lock holder"
else
  ng "read sync leaves origin/main and FETCH_HEAD to the lock holder"
fi
bash "$LOCK_HELPER" release "$handle"

# Up to date, but the private state root is not what acquire accepts.
make_fixture badroot || exit 1
rm -rf "$CLONE/.git/memory-write-state"
printf 'not a directory\n' >"$CLONE/.git/memory-write-state"
AGENT_MEMORY_DIR="$CLONE" bash "$HELPER" "$LINK" --read-sync 2>"$TMP/badroot.err"
if [ "$?" -ne 0 ] && grep -q 'write lock is held or needs recovery' "$TMP/badroot.err"; then
  ok "an up-to-date read sync rejects a state root that acquire would reject"
else
  ng "an up-to-date read sync rejects a state root that acquire would reject"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
