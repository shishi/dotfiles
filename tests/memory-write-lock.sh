#!/usr/bin/env bash
# write lock の排他性と所有権付き release だけを検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$REPO/agent-shared/bin/memory-write-lock.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/memory-write-lock.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MEMORY_REPO="$TMP/agent-memory"
git init -q "$MEMORY_REPO"
MEMORY_REPO="$(cd "$MEMORY_REPO" && pwd -P)"
LOCK="$MEMORY_REPO/.git/memory-write.lock"

handle="$(bash "$HELPER" acquire "$MEMORY_REPO" 2>"$TMP/acquire.err")"
status=$?
if [ "$status" -eq 0 ] && [ -n "$handle" ] && [ -d "$handle" ] && [ -d "$LOCK" ]; then
  ok "acquire returns an opaque handle and keeps the lock"
else
  ng "acquire returns an opaque handle and keeps the lock"
fi

second="$(bash "$HELPER" acquire "$MEMORY_REPO" 2>"$TMP/second.err")"
status=$?
if [ "$status" -ne 0 ] && [ -z "$second" ] && [ -d "$LOCK" ]; then
  ok "a second process cannot acquire the lock"
else
  ng "a second process cannot acquire the lock"
fi

mkdir "$TMP/foreign-handle"
if ! bash "$HELPER" release "$TMP/foreign-handle" 2>"$TMP/foreign.err" \
  && [ -d "$LOCK" ]; then
  ok "an unrelated handle cannot release the lock"
else
  ng "an unrelated handle cannot release the lock"
fi

if bash "$HELPER" release "$handle" 2>"$TMP/release.err" \
  && [ ! -e "$LOCK" ] && [ ! -e "$handle" ]; then
  ok "the owning handle releases its lock and private state"
else
  ng "the owning handle releases its lock and private state"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
