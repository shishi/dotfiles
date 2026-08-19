#!/usr/bin/env bash
# Shared memory write-lock helper runtime contract.
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/agents/bin/memory-write-lock.sh"
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-write-lock.XXXXXX")" || exit 1
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)" || exit 1
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

mode_of() {
  case "$(uname -s)" in
    Darwin | FreeBSD | OpenBSD | NetBSD) stat -f '%Lp' "$1" ;;
    *) stat -c '%a' "$1" ;;
  esac
}

token_output_is_absent() {
  ! grep -Eq '(^|[^0-9a-f])[0-9a-f]{64}([^0-9a-f]|$)|owner-[0-9a-f]{64}' "$1"
}

find_retired_handle() {
  find "$1/.git/memory-write-state" -mindepth 1 -maxdepth 2 \
    \( -name 'handle.retired-*' -o -path '*/retired-*/handle.*' \
    -o -path '*/retired-*/state' \) -print -quit
}

find_owner_marker() {
  find "$1/.git/memory-write.lock" -mindepth 1 -maxdepth 1 \
    \( -type d -o -type f \) -name 'owner-*' -print -quit 2>/dev/null
}

run_helper() {
  local stdout_file="$1" stderr_file="$2"
  shift 2
  bash "$HELPER" "$@" >"$stdout_file" 2>"$stderr_file"
}

write_malformed_record() {
  local kind="$1" value="$2" target="$3"

  case "$kind" in
    two-lines) printf '%s\nextra-line\n' "$value" >"$target" ;;
    unterminated-extra) printf '%s\nextra-line' "$value" >"$target" ;;
    no-final-newline) printf '%s' "$value" >"$target" ;;
    nul-byte) printf '%s\0\n' "$value" >"$target" ;;
  esac
}

if [ ! -f "$HELPER" ]; then
  fail "shared helper exists"
  echo
  echo "PASS/FAIL: FAILURES=$FAILURES"
  exit 1
fi

runtime_repo="$TMP_ROOT/repository with spaces"
mkdir -p "$runtime_repo/.git"
acquire_out="$TMP_ROOT/acquire.out"
acquire_err="$TMP_ROOT/acquire.err"
run_helper "$acquire_out" "$acquire_err" acquire "$runtime_repo"
acquire_status=$?
handle="$(sed -n '1p' "$acquire_out")"

case "$handle" in
  "$runtime_repo/.git/memory-write-state/handle."*) handle_shape=true ;;
  *) handle_shape=false ;;
esac
if [ "$acquire_status" -eq 0 ] && [ "$(wc -l <"$acquire_out" | tr -d ' ')" -eq 1 ] \
  && [ "$handle_shape" = true ] && [ -d "$handle" ] && [ ! -L "$handle" ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ]; then
  pass "acquire returns one opaque handle and keeps the lock after process exit"
else
  fail "acquire did not preserve a cross-process lock (status=$acquire_status)"
fi

owner_marker="$(find_owner_marker "$runtime_repo")"
if [ -n "$owner_marker" ] && [ "$(mode_of "$handle")" = 700 ] \
  && [ "$(mode_of "$handle/repo")" = 600 ] \
  && [ "$(mode_of "$handle/token")" = 600 ] \
  && [ "$(cat "$handle/repo")" = "$runtime_repo" ] \
  && grep -Eq '^[0-9a-f]{64}$' "$handle/token" \
  && token_output_is_absent "$acquire_out" && token_output_is_absent "$acquire_err"; then
  pass "handle state is strict, private, and does not expose the token"
else
  fail "handle state format, permissions, or output contract is invalid"
fi

second_out="$TMP_ROOT/second.out"
second_err="$TMP_ROOT/second.err"
run_helper "$second_out" "$second_err" acquire "$runtime_repo"
second_status=$?
if [ "$second_status" -ne 0 ] && [ ! -s "$second_out" ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ] \
  && token_output_is_absent "$second_err"; then
  pass "a second process cannot acquire an active lock"
else
  fail "a second process acquired or exposed an active lock"
fi

release_out="$TMP_ROOT/release.out"
release_err="$TMP_ROOT/release.err"
run_helper "$release_out" "$release_err" release "$handle"
release_status=$?
if [ "$release_status" -eq 0 ] && [ ! -s "$release_out" ] \
  && [ ! -e "$handle" ] && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
  && token_output_is_absent "$release_err"; then
  pass "a separate release process removes its lock and handle"
else
  fail "release did not remove its owned cross-process state (status=$release_status)"
fi

for collision_kind in real symlink; do
  runtime_repo="$TMP_ROOT/handle destination $collision_kind"
  foreign_target="$runtime_repo/foreign-target"
  mkdir -p "$runtime_repo/.git" "$foreign_target"
  printf 'preserve-me\n' >"$foreign_target/marker"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_KIND="$collision_kind" MEMORY_TEST_TARGET="$foreign_target" \
  MEMORY_TEST_FIRED="$runtime_repo/collision-fired" \
  bash -c '
    install_collision() {
      local destination="$1"
      [ ! -e "$MEMORY_TEST_FIRED" ] || return 0
      if [ "$MEMORY_TEST_KIND" = real ]; then
        command mkdir "$destination"
        command printf "%s\n" preserve-me >"$destination/marker"
      else
        command ln -s "$MEMORY_TEST_TARGET" "$destination"
      fi
      : >"$MEMORY_TEST_FIRED"
    }
    mkdir() {
      local argument last=""
      for argument in "$@"; do last="$argument"; done
      case "$last" in */memory-write-state/handle.*) install_collision "$last" ;; esac
      command mkdir "$@"
    }
    mv() {
      local argument previous="" source="" target=""
      for argument in "$@"; do source="$previous"; previous="$argument"; done
      target="$previous"
      case "$source:$target" in
        */.pending.*:*/memory-write-state/handle.*) install_collision "$target" ;;
      esac
      command mv "$@"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  handle_collision_status=$?
  collision_path="$(find "$runtime_repo/.git/memory-write-state" -mindepth 1 -maxdepth 1 \
    \( -type d -o -type l \) -name 'handle.*' -print -quit 2>/dev/null)"
  if [ "$collision_kind" = real ]; then collision_content="$collision_path"; \
  else collision_content="$foreign_target"; fi
  collision_extra="$(find "$collision_content" -mindepth 1 ! -name marker -print -quit 2>/dev/null)"
  if [ "$handle_collision_status" -ne 0 ] && [ -f "$runtime_repo/collision-fired" ] \
    && [ ! -s "$runtime_repo/acquire.out" ] && [ -n "$collision_path" ] \
    && [ "$(cat "$collision_content/marker")" = preserve-me ] \
    && [ -z "$collision_extra" ] && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && token_output_is_absent "$runtime_repo/acquire.err"; then
    pass "$collision_kind handle destination is never used as a directory move target"
  else
    fail "$collision_kind handle destination accepted nested owner state"
  fi
done

for collision_kind in real symlink; do
  runtime_repo="$TMP_ROOT/owner destination $collision_kind"
  foreign_target="$runtime_repo/foreign-target"
  mkdir -p "$runtime_repo/.git" "$foreign_target"
  printf 'preserve-me\n' >"$foreign_target/marker"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_KIND="$collision_kind" MEMORY_TEST_TARGET="$foreign_target" \
  MEMORY_TEST_FIRED="$runtime_repo/collision-fired" \
  bash -c '
    install_collision() {
      local destination="$1"
      [ ! -e "$MEMORY_TEST_FIRED" ] || return 0
      if [ "$MEMORY_TEST_KIND" = real ]; then
        command mkdir "$destination"
        command printf "%s\n" preserve-me >"$destination/marker"
      else
        command ln -s "$MEMORY_TEST_TARGET" "$destination"
      fi
      : >"$MEMORY_TEST_FIRED"
    }
    mv() {
      local argument previous="" source="" target=""
      for argument in "$@"; do source="$previous"; previous="$argument"; done
      target="$previous"
      case "$target" in */memory-write.lock/owner-*) install_collision "$target" ;; esac
      command mv "$@"
    }
    ln() {
      local argument last=""
      for argument in "$@"; do last="$argument"; done
      case "$last" in */memory-write.lock/owner-*) install_collision "$last" ;; esac
      command ln "$@"
    }
    mkdir() {
      local argument last=""
      for argument in "$@"; do last="$argument"; done
      case "$last" in */memory-write.lock/owner-*) install_collision "$last" ;; esac
      command mkdir "$@"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  owner_collision_status=$?
  owner_collision="$(find "$runtime_repo/.git/memory-write.lock" -mindepth 1 -maxdepth 1 \
    \( -type d -o -type l \) -name 'owner-*' -print -quit 2>/dev/null)"
  if [ "$collision_kind" = real ]; then collision_content="$owner_collision"; \
  else collision_content="$foreign_target"; fi
  collision_extra="$(find "$collision_content" -mindepth 1 ! -name marker -print -quit 2>/dev/null)"
  if [ "$owner_collision_status" -ne 0 ] && [ -f "$runtime_repo/collision-fired" ] \
    && [ ! -s "$runtime_repo/acquire.out" ] && [ -n "$owner_collision" ] \
    && [ "$(cat "$collision_content/marker")" = preserve-me ] \
    && [ -z "$collision_extra" ] && [ -d "$runtime_repo/.git/memory-write.lock" ] \
    && find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q . \
    && token_output_is_absent "$runtime_repo/acquire.err"; then
    pass "$collision_kind owner destination rejects atomic no-replace commit"
  else
    fail "$collision_kind owner destination nested the owner temp file"
  fi
done

for collision_kind in real symlink; do
  runtime_repo="$TMP_ROOT/retirement destination $collision_kind"
  foreign_target="$runtime_repo/foreign-target"
  mkdir -p "$runtime_repo/.git" "$foreign_target"
  printf 'preserve-me\n' >"$foreign_target/marker"
  run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
  handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
  MEMORY_TEST_LOCK="$runtime_repo/.git/memory-write.lock" \
  MEMORY_TEST_KIND="$collision_kind" MEMORY_TEST_TARGET="$foreign_target" \
  MEMORY_TEST_FIRED="$runtime_repo/collision-fired" \
  bash -c '
    install_collision() {
      local destination="$1"
      [ ! -e "$MEMORY_TEST_FIRED" ] || return 0
      if [ "$MEMORY_TEST_KIND" = real ]; then
        command mkdir "$destination"
        command printf "%s\n" preserve-me >"$destination/marker"
      else
        command ln -s "$MEMORY_TEST_TARGET" "$destination"
      fi
      : >"$MEMORY_TEST_FIRED"
    }
    mkdir() {
      local argument last=""
      for argument in "$@"; do last="$argument"; done
      case "$last" in */.git/memory-write-retirement.*) install_collision "$last" ;; esac
      command mkdir "$@"
    }
    mv() {
      local source="${1:-}" target="${2:-}"
      case "$source:$target" in
        "$MEMORY_TEST_LOCK":*/memory-write.lock.retired-*) install_collision "$target" ;;
      esac
      command mv "$@"
    }
    source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
  ' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
  retirement_collision_status=$?
  if [ "$collision_kind" = real ]; then
    collision_path="$(find "$runtime_repo/.git" -mindepth 1 -maxdepth 1 -type d \
      \( -name 'memory-write.lock.retired-*' -o -name 'memory-write-retirement.*' \) \
      -print -quit 2>/dev/null)"
    collision_content="$collision_path"
  else
    collision_path="$(find "$runtime_repo/.git" -mindepth 1 -maxdepth 1 -type l \
      \( -name 'memory-write.lock.retired-*' -o -name 'memory-write-retirement.*' \) \
      -print -quit 2>/dev/null)"
    collision_content="$foreign_target"
  fi
  collision_extra="$(find "$collision_content" -mindepth 1 ! -name marker -print -quit 2>/dev/null)"
  if [ "$retirement_collision_status" -ne 0 ] \
    && [ -f "$runtime_repo/collision-fired" ] && [ -n "$collision_path" ] \
    && [ "$(cat "$collision_content/marker")" = preserve-me ] \
    && [ -z "$collision_extra" ] && [ -d "$runtime_repo/.git/memory-write.lock" ] \
    && [ -n "$(find_retired_handle "$runtime_repo")" ] \
    && token_output_is_absent "$runtime_repo/release.err"; then
    pass "$collision_kind retirement destination is never used for owned lock insertion"
  else
    fail "$collision_kind retirement destination nested the owned lock"
  fi
done

runtime_repo="$TMP_ROOT/handle ABA"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
MEMORY_TEST_REPO="$runtime_repo" MEMORY_TEST_SWAP="$runtime_repo/handle-swap-fired" \
bash -c '
  rm() {
    local argument swap=false
    for argument in "$@"; do
      case "$argument" in
        */memory-write.lock.retired-*/owner-*|*/memory-write-retirement.*/lock/owner-*/value)
          swap=true
          ;;
      esac
    done
    if [ "$swap" = true ]; then
      command rm -rf "$MEMORY_TEST_HANDLE"
      command mkdir "$MEMORY_TEST_HANDLE"
      command chmod 700 "$MEMORY_TEST_HANDLE"
      command printf "%s\n" "$MEMORY_TEST_REPO" >"$MEMORY_TEST_HANDLE/repo"
      command printf "%064d\n" 0 | command tr 0 f >"$MEMORY_TEST_HANDLE/token"
      command chmod 600 "$MEMORY_TEST_HANDLE/repo" "$MEMORY_TEST_HANDLE/token"
      : >"$MEMORY_TEST_SWAP"
    fi
    command rm "$@"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
handle_aba_status=$?
if [ "$handle_aba_status" -eq 0 ] && [ -f "$runtime_repo/handle-swap-fired" ] \
  && [ -d "$handle" ] && grep -Eq '^f{64}$' "$handle/token" \
  && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
  && token_output_is_absent "$runtime_repo/release.err"; then
  pass "release never deletes a same-name foreign handle created after retirement"
else
  fail "release deleted or changed a same-name foreign handle (status=$handle_aba_status)"
fi

runtime_repo="$TMP_ROOT/foreign handle before retirement"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
MEMORY_TEST_REPO="$runtime_repo" MEMORY_TEST_SWAP="$runtime_repo/handle-swap-fired" \
bash -c '
  mv() {
    local argument previous="" source=""
    for argument in "$@"; do source="$previous"; previous="$argument"; done
    if [ "$source" = "$MEMORY_TEST_HANDLE" ] && [ ! -e "$MEMORY_TEST_SWAP" ]; then
      command rm -rf "$MEMORY_TEST_HANDLE"
      command mkdir "$MEMORY_TEST_HANDLE"
      command chmod 700 "$MEMORY_TEST_HANDLE"
      command printf "%s\n" "$MEMORY_TEST_REPO" >"$MEMORY_TEST_HANDLE/repo"
      command printf "%064d\n" 0 | command tr 0 f >"$MEMORY_TEST_HANDLE/token"
      command chmod 600 "$MEMORY_TEST_HANDLE/repo" "$MEMORY_TEST_HANDLE/token"
      : >"$MEMORY_TEST_SWAP"
    fi
    command mv "$@"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
foreign_handle_status=$?
retired_handle="$(find_retired_handle "$runtime_repo")"
if [ "$foreign_handle_status" -ne 0 ] && [ -f "$runtime_repo/handle-swap-fired" ] \
  && [ ! -e "$handle" ] && [ -d "$retired_handle" ] \
  && grep -Eq '^f{64}$' "$retired_handle/token" \
  && [ -d "$runtime_repo/.git/memory-write.lock" ] \
  && token_output_is_absent "$runtime_repo/release.err"; then
  pass "foreign handle moved at retirement is retained without touching the lock"
else
  fail "foreign handle retirement was modified or lost"
fi

runtime_repo="$TMP_ROOT/symlink handle before retirement"
symlink_target="$runtime_repo/foreign target"
mkdir -p "$runtime_repo/.git" "$symlink_target"
printf 'preserve-me\n' >"$symlink_target/victim"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
MEMORY_TEST_TARGET="$symlink_target" MEMORY_TEST_SWAP="$runtime_repo/handle-swap-fired" \
bash -c '
  mv() {
    local argument previous="" source=""
    for argument in "$@"; do source="$previous"; previous="$argument"; done
    if [ "$source" = "$MEMORY_TEST_HANDLE" ] && [ ! -e "$MEMORY_TEST_SWAP" ]; then
      command rm -rf "$MEMORY_TEST_HANDLE"
      command ln -s "$MEMORY_TEST_TARGET" "$MEMORY_TEST_HANDLE"
      : >"$MEMORY_TEST_SWAP"
    fi
    command mv "$@"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
symlink_handle_status=$?
retired_handle="$(find_retired_handle "$runtime_repo")"
if [ "$symlink_handle_status" -ne 0 ] && [ -f "$runtime_repo/handle-swap-fired" ] \
  && [ ! -e "$handle" ] && [ -L "$retired_handle" ] \
  && [ "$(readlink "$retired_handle")" = "$symlink_target" ] \
  && [ "$(cat "$symlink_target/victim")" = preserve-me ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ] \
  && token_output_is_absent "$runtime_repo/release.err"; then
  pass "symlink handle moved at retirement is retained without touching its target"
else
  fail "symlink handle retirement changed its target or recovery state"
fi

runtime_repo="$TMP_ROOT/foreign handle restore conflict"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
MEMORY_TEST_REPO="$runtime_repo" MEMORY_TEST_SWAP="$runtime_repo/handle-swap-fired" \
MEMORY_TEST_RESTORE="$runtime_repo/handle-restore-fired" \
bash -c '
  mv() {
    local argument previous="" source=""
    for argument in "$@"; do source="$previous"; previous="$argument"; done
    if [ "$source" = "$MEMORY_TEST_HANDLE" ] && [ ! -e "$MEMORY_TEST_SWAP" ]; then
      command rm -rf "$MEMORY_TEST_HANDLE"
      command mkdir "$MEMORY_TEST_HANDLE"
      command chmod 700 "$MEMORY_TEST_HANDLE"
      command printf "%s\n" "$MEMORY_TEST_REPO" >"$MEMORY_TEST_HANDLE/repo"
      command printf "%064d\n" 0 | command tr 0 f >"$MEMORY_TEST_HANDLE/token"
      command chmod 600 "$MEMORY_TEST_HANDLE/repo" "$MEMORY_TEST_HANDLE/token"
      : >"$MEMORY_TEST_SWAP"
    elif [ -e "$MEMORY_TEST_SWAP" ]; then
      case "$source" in
        */handle.retired-*|*/retired-*/handle.*)
          if [ ! -e "$MEMORY_TEST_HANDLE" ]; then
            command mkdir "$MEMORY_TEST_HANDLE"
            : >"$MEMORY_TEST_HANDLE/foreign-marker"
          fi
          : >"$MEMORY_TEST_RESTORE"
          ;;
      esac
    fi
    command mv "$@"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
restore_conflict_status=$?
retired_handle="$(find_retired_handle "$runtime_repo")"
if [ "$restore_conflict_status" -ne 0 ] \
  && [ -f "$runtime_repo/handle-swap-fired" ] \
  && [ ! -e "$runtime_repo/handle-restore-fired" ] \
  && [ ! -e "$handle" ] && [ -d "$retired_handle" ] \
  && grep -Eq '^f{64}$' "$retired_handle/token" \
  && [ -d "$runtime_repo/.git/memory-write.lock" ] \
  && token_output_is_absent "$runtime_repo/release.err"; then
  pass "foreign retired state is never restored through a directory target"
else
  fail "foreign retired state triggered an unsafe restore"
fi

for stale_kind in .pending.stale handle.stale; do
  runtime_repo="$TMP_ROOT/preexisting-$stale_kind"
  mkdir -p "$runtime_repo/.git/memory-write-state/$stale_kind"
  chmod 700 "$runtime_repo/.git/memory-write-state"
  stale_out="$runtime_repo/stale.out"
  stale_err="$runtime_repo/stale.err"
  run_helper "$stale_out" "$stale_err" acquire "$runtime_repo"
  stale_status=$?
  if [ "$stale_status" -ne 0 ] && [ ! -s "$stale_out" ] \
    && [ -d "$runtime_repo/.git/memory-write-state/$stale_kind" ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ]; then
    pass "preexisting $stale_kind state fences acquisition"
  else
    fail "preexisting $stale_kind state was ignored or changed"
  fi
done

runtime_repo="$TMP_ROOT/preexisting retirement"
mkdir -p "$runtime_repo/.git/memory-write.lock.retired-stale"
: >"$runtime_repo/.git/memory-write.lock.retired-stale/residual"
run_helper "$runtime_repo/retired.out" "$runtime_repo/retired.err" \
  acquire "$runtime_repo"
retired_status=$?
if [ "$retired_status" -ne 0 ] && [ ! -s "$runtime_repo/retired.out" ] \
  && [ -f "$runtime_repo/.git/memory-write.lock.retired-stale/residual" ] \
  && [ ! -e "$runtime_repo/.git/memory-write.lock" ]; then
  pass "preexisting retirement fences acquisition without modification"
else
  fail "preexisting retirement was ignored or modified"
fi

runtime_repo="$TMP_ROOT/concurrent pending"
mkdir -p "$runtime_repo/.git"
concurrent_pids=""
for attempt in 1 2 3 4 5 6 7 8; do
  run_helper "$runtime_repo/out.$attempt" "$runtime_repo/err.$attempt" \
    acquire "$runtime_repo" &
  concurrent_pids="$concurrent_pids $!"
done
for child_pid in $concurrent_pids; do
  wait "$child_pid" 2>/dev/null || :
done
concurrent_successes=0
concurrent_handle=""
for attempt in 1 2 3 4 5 6 7 8; do
  candidate_handle="$(sed -n '1p' "$runtime_repo/out.$attempt")"
  if [ -n "$candidate_handle" ]; then
    concurrent_successes=$((concurrent_successes + 1))
    concurrent_handle="$candidate_handle"
  fi
done
if [ "$concurrent_successes" -le 1 ]; then
  pass "parallel pending states allow at most one acquisition"
else
  fail "parallel pending states allowed $concurrent_successes acquisitions"
fi
if [ -n "$concurrent_handle" ]; then
  run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" \
    release "$concurrent_handle" || fail "parallel acquisition winner could not release"
fi

runtime_repo="$TMP_ROOT/old handle"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/first.out" "$runtime_repo/first.err" acquire "$runtime_repo"
first_handle="$(sed -n '1p' "$runtime_repo/first.out")"
old_token="$(cat "$first_handle/token")"
run_helper "$runtime_repo/first-release.out" "$runtime_repo/first-release.err" \
  release "$first_handle"
run_helper "$runtime_repo/second.out" "$runtime_repo/second.err" acquire "$runtime_repo"
second_handle="$(sed -n '1p' "$runtime_repo/second.out")"
mkdir "$first_handle"
chmod 700 "$first_handle"
printf '%s\n' "$runtime_repo" >"$first_handle/repo"
printf '%s\n' "$old_token" >"$first_handle/token"
chmod 600 "$first_handle/repo" "$first_handle/token"
run_helper "$runtime_repo/old-release.out" "$runtime_repo/old-release.err" \
  release "$first_handle"
old_release_status=$?
if [ "$old_release_status" -ne 0 ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ] \
  && [ -d "$second_handle" ]; then
  pass "a recreated old handle cannot release a newer lock"
else
  fail "a recreated old handle changed a newer lock"
fi
rm -rf "$first_handle"
run_helper "$runtime_repo/second-release.out" "$runtime_repo/second-release.err" \
  release "$second_handle" || fail "new handle could not release after old-handle rejection"

runtime_repo="$TMP_ROOT/malformed handle state"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
saved_owner_value="$(cat "$handle/token")"
printf '%s\nextra-line\n' "$saved_owner_value" >"$handle/token"
run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" release "$handle"
malformed_status=$?
if [ "$malformed_status" -ne 0 ] && [ -d "$handle" ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ]; then
  pass "release rejects handle state that is not the fixed two-file format"
else
  fail "release accepted or changed malformed handle state"
fi
printf '%s\n' "$saved_owner_value" >"$handle/token"
: >"$handle/extra"
run_helper "$runtime_repo/release-extra.out" "$runtime_repo/release-extra.err" release "$handle"
extra_state_status=$?
if [ "$extra_state_status" -ne 0 ] && [ -d "$handle" ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ]; then
  pass "release rejects unexpected handle state before changing the lock"
else
  fail "release changed a lock described by unexpected handle state"
fi
rm "$handle/extra"
run_helper "$runtime_repo/release-restored.out" "$runtime_repo/release-restored.err" \
  release "$handle" || fail "restored fixed-format handle could not release"

for malformed_field in repo token owner; do
  for malformed_kind in two-lines unterminated-extra no-final-newline nul-byte; do
    runtime_repo="$TMP_ROOT/malformed $malformed_field $malformed_kind"
    mkdir -p "$runtime_repo/.git"
    run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
    handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
    owner_value="$(cat "$handle/token")"
    case "$malformed_field" in
      repo)
        malformed_target="$handle/repo"
        malformed_value="$runtime_repo"
        ;;
      token)
        malformed_target="$handle/token"
        malformed_value="$owner_value"
        ;;
      owner)
        malformed_target="$(find_owner_marker "$runtime_repo")/value"
        malformed_value="$owner_value"
        ;;
    esac
    write_malformed_record "$malformed_kind" "$malformed_value" "$malformed_target"
    malformed_checksum="$(cksum <"$malformed_target")"
    run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" release "$handle"
    strict_record_status=$?
    retired_handle="$(find_retired_handle "$runtime_repo")"
    preserved_state=false
    if [ -d "$handle" ] || [ -n "$retired_handle" ]; then preserved_state=true; fi
    after_checksum=""
    if [ -f "$malformed_target" ]; then after_checksum="$(cksum <"$malformed_target")"; fi
    canonical_handle_expected=true
    if [ "$malformed_field" != owner ] \
      && { [ ! -d "$handle" ] || [ -n "$retired_handle" ]; }; then
      canonical_handle_expected=false
    fi
    if [ "$strict_record_status" -ne 0 ] \
      && [ -d "$runtime_repo/.git/memory-write.lock" ] \
      && [ "$preserved_state" = true ] && [ "$canonical_handle_expected" = true ] \
      && [ "$after_checksum" = "$malformed_checksum" ] \
      && token_output_is_absent "$runtime_repo/release.err"; then
      pass "$malformed_field rejects $malformed_kind without changing lock state"
    else
      fail "$malformed_field accepted or changed $malformed_kind state"
    fi
  done
done

runtime_repo="$TMP_ROOT/foreign owner"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
owner_marker="$(find_owner_marker "$runtime_repo")"
printf 'foreign-owner\n' >"$owner_marker/value"
run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" release "$handle"
foreign_owner_status=$?
retired_handle="$(find_retired_handle "$runtime_repo")"
if [ "$foreign_owner_status" -ne 0 ] \
  && [ -f "$owner_marker/value" ] && [ -d "$retired_handle" ]; then
  pass "release requires owner marker content to match the handle token"
else
  fail "release removed a foreign owner marker"
fi

runtime_repo="$TMP_ROOT/symlink state parent"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
mv "$runtime_repo/.git/memory-write-state" "$runtime_repo/.git/real-state"
ln -s "$runtime_repo/.git/real-state" "$runtime_repo/.git/memory-write-state"
run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" release "$handle"
symlink_parent_status=$?
if [ "$symlink_parent_status" -ne 0 ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ]; then
  pass "release rejects a handle reached through a symlink state parent"
else
  fail "release trusted a handle through a symlink state parent"
fi
rm "$runtime_repo/.git/memory-write-state"
mv "$runtime_repo/.git/real-state" "$runtime_repo/.git/memory-write-state"
run_helper "$runtime_repo/release-real.out" "$runtime_repo/release-real.err" \
  release "$handle" || fail "restored real state handle could not release"

runtime_repo="$TMP_ROOT/symlink lock ABA"
symlink_target="$runtime_repo/foreign target"
mkdir -p "$runtime_repo/.git" "$symlink_target"
printf 'preserve-me\n' >"$symlink_target/victim"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
owner_marker="$(find_owner_marker "$runtime_repo")"
MEMORY_TEST_LOCK="$runtime_repo/.git/memory-write.lock" \
MEMORY_TEST_OWNER="$owner_marker" MEMORY_TEST_TARGET="$symlink_target" \
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
bash -c '
  mv() {
    if [ "${1:-}" = "$MEMORY_TEST_LOCK" ]; then
      command rm -f "$MEMORY_TEST_OWNER/value"
      command rmdir "$MEMORY_TEST_OWNER"
      command rmdir "$MEMORY_TEST_LOCK"
      command ln -s "$MEMORY_TEST_TARGET" "$MEMORY_TEST_LOCK"
    fi
    command mv "$@"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
symlink_release_status=$?
retired_symlink="$(find "$runtime_repo/.git" -mindepth 1 -maxdepth 2 -type l \
  \( -name 'memory-write.lock.retired-*' -o -path '*/memory-write-retirement.*/lock' \) \
  -print -quit)"
retired_handle="$(find_retired_handle "$runtime_repo")"
if [ "$symlink_release_status" -ne 0 ] \
  && [ "$(cat "$symlink_target/victim")" = preserve-me ] \
  && [ -L "$retired_symlink" ] && [ -d "$retired_handle" ]; then
  pass "symlink ABA leaves the target untouched and retains recovery state"
else
  fail "symlink ABA modified its target or discarded recovery state"
fi

runtime_repo="$TMP_ROOT/cleanup failure"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
bash -c '
  rmdir() {
    case "${1:-}" in
      *.retired-*|*/memory-write-retirement.*/lock) : >"$1/cleanup-residual" ;;
    esac
    command rmdir "$@"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
cleanup_failure_status=$?
cleanup_residual="$(find "$runtime_repo/.git" \
  \( -path '*/memory-write.lock.retired-*/cleanup-residual' \
  -o -path '*/memory-write-retirement.*/lock/cleanup-residual' \) -print -quit)"
retired_handle="$(find_retired_handle "$runtime_repo")"
run_helper "$runtime_repo/retry.out" "$runtime_repo/retry.err" acquire "$runtime_repo"
retry_status=$?
if [ "$cleanup_failure_status" -ne 0 ] && [ -n "$cleanup_residual" ] \
  && [ -d "$retired_handle" ] && [ "$retry_status" -ne 0 ] \
  && token_output_is_absent "$runtime_repo/release.err"; then
  pass "cleanup failure retains fenced state without leaking token paths"
else
  fail "cleanup failure was not fail-closed or leaked token output"
fi

runtime_repo="$TMP_ROOT/state cleanup failure"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
bash -c '
  rm() {
    for argument in "$@"; do
      case "$argument" in
        */handle.*/token|*/retired-*/state/token) return 1 ;;
      esac
    done
    command rm "$@"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
state_cleanup_status=$?
retired_handle="$(find_retired_handle "$runtime_repo")"
run_helper "$runtime_repo/retry.out" "$runtime_repo/retry.err" acquire "$runtime_repo"
state_retry_status=$?
if [ "$state_cleanup_status" -ne 0 ] && [ -d "$retired_handle" ] \
  && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
  && [ "$state_retry_status" -ne 0 ] \
  && token_output_is_absent "$runtime_repo/release.err"; then
  pass "state cleanup failure retains a fence after lock removal"
else
  fail "state cleanup failure was not fenced or leaked token output"
fi

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/release signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
  handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
  MEMORY_TEST_LOCK="$runtime_repo/.git/memory-write.lock" MEMORY_TEST_SIGNAL="$signal_name" \
  bash -c '
    mv() {
      command mv "$@" || return
      if [ "${1:-}" = "$MEMORY_TEST_LOCK" ]; then kill "-$MEMORY_TEST_SIGNAL" "$$"; fi
    }
    source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
  ' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
  release_signal_status=$?
  if [ "$release_signal_status" -eq "$signal_status" ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && [ ! -e "$handle" ]; then
    pass "$signal_name during release completes cleanup and preserves signal status"
  else
    fail "$signal_name during release left partial state or returned $release_signal_status"
  fi
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  expected_signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/mkdir signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_LOCK="$runtime_repo/.git/memory-write.lock" MEMORY_TEST_SIGNAL="$signal_name" \
  bash -c '
    mkdir() {
      local argument last="" status
      for argument in "$@"; do last="$argument"; done
      command mkdir "$@"
      status=$?
      if [ "$status" -eq 0 ] && [ "$last" = "$MEMORY_TEST_LOCK" ]; then
        kill "-$MEMORY_TEST_SIGNAL" "$$"
      fi
      return "$status"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  mkdir_signal_status=$?
  if [ "$mkdir_signal_status" -eq "$expected_signal_status" ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
    pass "$signal_name immediately after lock mkdir cleans ownership and state"
  else
    fail "$signal_name immediately after lock mkdir left stale state or returned $mkdir_signal_status"
  fi
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  expected_signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/mkdir failure signal $signal_name"
  mkdir -p "$runtime_repo/.git/memory-write.lock"
  : >"$runtime_repo/.git/memory-write.lock/foreign-marker"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_LOCK="$runtime_repo/.git/memory-write.lock" MEMORY_TEST_SIGNAL="$signal_name" \
  bash -c '
    mkdir() {
      local argument last="" status
      for argument in "$@"; do last="$argument"; done
      command mkdir "$@"
      status=$?
      if [ "$last" = "$MEMORY_TEST_LOCK" ]; then kill "-$MEMORY_TEST_SIGNAL" "$$"; fi
      return "$status"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  mkdir_failure_status=$?
  if [ "$mkdir_failure_status" -eq "$expected_signal_status" ] \
    && [ -f "$runtime_repo/.git/memory-write.lock/foreign-marker" ] \
    && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
    pass "$signal_name on failed lock mkdir preserves the foreign lock and signal status"
  else
    fail "$signal_name on failed lock mkdir changed foreign state or returned $mkdir_failure_status"
  fi
done

runtime_repo="$TMP_ROOT/owner record failure"
mkdir -p "$runtime_repo/.git"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
bash -c '
  mktemp() {
    case "${1:-}" in
      */memory-write.lock/.owner.XXXXXX) return 1 ;;
    esac
    command mktemp "$@"
  }
  source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
record_failure_status=$?
run_helper "$runtime_repo/retry.out" "$runtime_repo/retry.err" acquire "$runtime_repo"
record_retry_status=$?
record_fence="$(find "$runtime_repo/.git/memory-write-state" -mindepth 1 -maxdepth 1 \
  -type d \( -name '.pending.*' -o -name 'retired-*' \) -print -quit)"
if [ "$record_failure_status" -ne 0 ] && [ "$record_retry_status" -ne 0 ] \
  && [ -d "$runtime_repo/.git/memory-write.lock" ] && [ -n "$record_fence" ] \
  && token_output_is_absent "$runtime_repo/acquire.err"; then
  pass "owner-record failure retains a fenced lock instead of deleting an unowned path"
else
  fail "owner-record failure removed an unproven lock or did not retain a fence"
fi

runtime_repo="$TMP_ROOT/owner read race"
mkdir -p "$runtime_repo/.git"
run_helper "$runtime_repo/acquire.out" "$runtime_repo/acquire.err" acquire "$runtime_repo"
handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
owner_marker="$(find_owner_marker "$runtime_repo")/value"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_HANDLE="$handle" \
MEMORY_TEST_OWNER="$owner_marker" MEMORY_TEST_COUNTER="$runtime_repo/stat-count" \
bash -c '
  stat() {
    local argument last="" owner_stat_count=0 status
    for argument in "$@"; do last="$argument"; done
    command stat "$@"
    status=$?
    if [ "$last" = "$MEMORY_TEST_OWNER" ]; then
      if [ -f "$MEMORY_TEST_COUNTER" ]; then
        owner_stat_count="$(cat "$MEMORY_TEST_COUNTER")"
      fi
      owner_stat_count=$((owner_stat_count + 1))
      printf "%s\n" "$owner_stat_count" >"$MEMORY_TEST_COUNTER"
      if [ "$owner_stat_count" -eq 1 ]; then command rm -f "$MEMORY_TEST_OWNER"; fi
    fi
    return "$status"
  }
  source "$MEMORY_TEST_HELPER" release "$MEMORY_TEST_HANDLE"
' >"$runtime_repo/release.out" 2>"$runtime_repo/release.err"
owner_read_status=$?
retired_handle="$(find_retired_handle "$runtime_repo")"
if [ "$owner_read_status" -ne 0 ] && [ -d "$retired_handle" ] \
  && token_output_is_absent "$runtime_repo/release.err"; then
  pass "owner-read race fails closed without leaking a token-bearing path"
else
  owner_read_leaked=false
  token_output_is_absent "$runtime_repo/release.err" || owner_read_leaked=true
  fail "owner-read race was unsafe (status=$owner_read_status handle=$([ -d "$retired_handle" ] && echo kept || echo missing) leaked=$owner_read_leaked)"
fi

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  expected_signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/acquire signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_SIGNAL="$signal_name" \
  bash -c '
    mv() {
      command mv "$@" || return
      case "${2:-}" in
        */memory-write.lock/owner-*/value) kill "-$MEMORY_TEST_SIGNAL" "$$" ;;
      esac
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  acquire_signal_status=$?
  if [ "$acquire_signal_status" -eq "$expected_signal_status" ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
    pass "$signal_name during acquire cleans partial ownership and preserves status"
  else
    fail "$signal_name during acquire left partial ownership or wrong status $acquire_signal_status"
  fi
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  expected_signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/handle mkdir signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_SIGNAL="$signal_name" \
  bash -c '
    mkdir() {
      local argument last=""
      for argument in "$@"; do last="$argument"; done
      command mkdir "$@" || return
      case "$last" in
        */memory-write-state/handle.*) kill "-$MEMORY_TEST_SIGNAL" "$$" ;;
      esac
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  rename_signal_status=$?
  if [ "$rename_signal_status" -eq "$expected_signal_status" ] \
    && [ ! -s "$runtime_repo/acquire.out" ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
    pass "$signal_name after final handle mkdir removes untransferred ownership"
  else
    fail "$signal_name after final handle mkdir left unreachable state or returned $rename_signal_status"
  fi
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  expected_signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/cleanup state ABA $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_SIGNAL="$signal_name" \
  MEMORY_TEST_STATE_ROOT="$runtime_repo/.git/memory-write-state" \
  MEMORY_TEST_SWAP="$runtime_repo/state-swap-fired" \
  bash -c '
    runtime_handle=""
    printf() {
      case "${2:-}" in
        */memory-write-state/handle.*)
          runtime_handle="$2"
          kill "-$MEMORY_TEST_SIGNAL" "$$"
          ;;
      esac
      builtin printf "$@"
    }
    rm() {
      local argument canonical="" state="" swap=false
      for argument in "$@"; do
        case "$argument" in
          */memory-write-state/handle.*/repo|*/memory-write-state/retired-*/handle.*/repo|*/memory-write-state/retired-*/state/repo)
            state="$(dirname "$argument")"
            swap=true
            ;;
        esac
      done
      if [ "$swap" = true ] && [ ! -e "$MEMORY_TEST_SWAP" ]; then
        case "$state" in
          "$MEMORY_TEST_STATE_ROOT"/retired-*/handle.*) canonical="$MEMORY_TEST_STATE_ROOT/${state##*/}" ;;
          "$MEMORY_TEST_STATE_ROOT"/retired-*/state) canonical="$runtime_handle" ;;
          *) canonical="$state" ;;
        esac
        command rm -rf "$canonical"
        command mkdir "$canonical"
        command chmod 700 "$canonical"
        command printf "%s\n" foreign-repository >"$canonical/repo"
        command printf "%064d\n" 0 | command tr 0 f >"$canonical/token"
        command chmod 600 "$canonical/repo" "$canonical/token"
        : >"$MEMORY_TEST_SWAP"
      fi
      command rm "$@"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  state_aba_status=$?
  handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
  if [ "$state_aba_status" -eq "$expected_signal_status" ] \
    && [ -f "$runtime_repo/state-swap-fired" ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && [ -d "$handle" ] && grep -qxF foreign-repository "$handle/repo" \
    && grep -Eq '^f{64}$' "$handle/token"; then
    pass "$signal_name partial cleanup removes retired ownership and preserves canonical foreign state"
  else
    fail "$signal_name partial cleanup deleted canonical foreign state after validation"
  fi
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  expected_signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/stdout signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_SIGNAL="$signal_name" \
  bash -c '
    printf() {
      case "${2:-}" in
        */memory-write-state/handle.*) kill "-$MEMORY_TEST_SIGNAL" "$$" ;;
      esac
      builtin printf "$@"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  stdout_signal_status=$?
  if [ "$stdout_signal_status" -eq "$expected_signal_status" ] \
    && [ "$(wc -l <"$runtime_repo/acquire.out" | tr -d ' ')" -le 1 ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
    pass "$signal_name before handle stdout removes untransferred ownership"
  else
    fail "$signal_name before handle stdout left unreachable state or returned $stdout_signal_status"
  fi
done

for switch_position in before after; do
  for signal_case in HUP:129 INT:130 TERM:143; do
    signal_name="${signal_case%%:*}"
    expected_signal_status="${signal_case#*:}"
    runtime_repo="$TMP_ROOT/signal switch $switch_position $signal_name"
    mkdir -p "$runtime_repo/.git"
    MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
    MEMORY_TEST_SIGNAL="$signal_name" MEMORY_TEST_POSITION="$switch_position" \
    MEMORY_TEST_SWITCH_MARKER="$runtime_repo/switch-fired" \
    bash -c '
      trap() {
        if [ "${1+x}" = x ] && [ -z "${1:-}" ] \
          && [ "${2:-}" = HUP ] && [ "${3:-}" = INT ] && [ "${4:-}" = TERM ]; then
          if [ "$MEMORY_TEST_POSITION" = before ]; then kill "-$MEMORY_TEST_SIGNAL" "$$"; fi
          builtin trap "$@"
          if [ "$MEMORY_TEST_POSITION" = after ]; then kill "-$MEMORY_TEST_SIGNAL" "$$"; fi
          : >"$MEMORY_TEST_SWITCH_MARKER"
          return 0
        fi
        builtin trap "$@"
      }
      source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
    ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
    switch_status=$?
    handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
    if [ "$switch_position" = before ]; then
      if [ "$switch_status" -eq "$expected_signal_status" ] \
        && [ -f "$runtime_repo/switch-fired" ] \
        && [ "$(wc -l <"$runtime_repo/acquire.out" | tr -d ' ')" -eq 1 ] \
        && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
        && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
        pass "$signal_name before commit signal switch aborts ownership transfer"
      else
        fail "$signal_name before commit signal switch returned $switch_status or left ownership"
      fi
    else
      if [ "$switch_status" -eq 0 ] && [ -f "$runtime_repo/switch-fired" ] \
        && [ -d "$handle" ] && [ -d "$runtime_repo/.git/memory-write.lock" ]; then
        pass "$signal_name after commit signal switch preserves successful transfer"
      else
        fail "$signal_name after commit signal switch returned $switch_status or lost ownership"
      fi
      if [ -n "$handle" ]; then
        run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" release "$handle" \
          || fail "$signal_name post-switch handle could not release"
      fi
    fi
  done
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  runtime_repo="$TMP_ROOT/committed flag signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_SIGNAL="$signal_name" MEMORY_TEST_FLAG_MARKER="$runtime_repo/flag-fired" \
  bash -c '
    set -T
    trap '\''
      if [ "${acquire_committed:-false}" = true ] && [ ! -e "$MEMORY_TEST_FLAG_MARKER" ]; then
        : >"$MEMORY_TEST_FLAG_MARKER"
        kill "-$MEMORY_TEST_SIGNAL" "$$"
      fi
    '\'' DEBUG
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  flag_signal_status=$?
  handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
  if [ "$flag_signal_status" -eq 0 ] && [ -f "$runtime_repo/flag-fired" ] \
    && [ -d "$handle" ] && [ -d "$runtime_repo/.git/memory-write.lock" ]; then
    pass "$signal_name immediately after committed flag preserves status 0 transfer"
  else
    fail "$signal_name immediately after committed flag returned $flag_signal_status or lost transfer"
  fi
  if [ -n "$handle" ]; then
    run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" release "$handle" \
      || fail "$signal_name committed-flag handle could not release"
  fi
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  runtime_repo="$TMP_ROOT/exit trap signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_SIGNAL="$signal_name" MEMORY_TEST_EXIT_MARKER="$runtime_repo/exit-fired" \
  bash -c '
    trap() {
      if [ "${1:-}" = - ] && [ "${2:-}" = EXIT ]; then
        builtin trap "$@"
        : >"$MEMORY_TEST_EXIT_MARKER"
        kill "-$MEMORY_TEST_SIGNAL" "$$"
        return 0
      fi
      builtin trap "$@"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  exit_signal_status=$?
  handle="$(sed -n '1p' "$runtime_repo/acquire.out")"
  if [ "$exit_signal_status" -eq 0 ] && [ -f "$runtime_repo/exit-fired" ] \
    && [ -d "$handle" ] && [ -d "$runtime_repo/.git/memory-write.lock" ]; then
    pass "$signal_name in committed EXIT handling preserves status 0 ownership transfer"
  else
    fail "$signal_name in committed EXIT handling returned $exit_signal_status or lost transfer"
  fi
  if [ -n "$handle" ]; then
    run_helper "$runtime_repo/release.out" "$runtime_repo/release.err" release "$handle" \
      || fail "$signal_name EXIT handle could not release"
  fi
done

for signal_case in HUP:129 INT:130 TERM:143; do
  signal_name="${signal_case%%:*}"
  expected_signal_status="${signal_case#*:}"
  runtime_repo="$TMP_ROOT/stdout written signal $signal_name"
  mkdir -p "$runtime_repo/.git"
  MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
  MEMORY_TEST_SIGNAL="$signal_name" \
  bash -c '
    printf() {
      local status
      builtin printf "$@"
      status=$?
      case "${2:-}" in
        */memory-write-state/handle.*) kill "-$MEMORY_TEST_SIGNAL" "$$" ;;
      esac
      return "$status"
    }
    source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
  ' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
  stdout_written_signal_status=$?
  if [ "$stdout_written_signal_status" -eq "$expected_signal_status" ] \
    && [ "$(wc -l <"$runtime_repo/acquire.out" | tr -d ' ')" -eq 1 ] \
    && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
    && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
    pass "$signal_name after stdout write but before commit invalidates output and cleans ownership"
  else
    fail "$signal_name after stdout write committed unreachable ownership or returned $stdout_written_signal_status"
  fi
done

runtime_repo="$TMP_ROOT/stdout failure"
mkdir -p "$runtime_repo/.git"
MEMORY_TEST_HELPER="$HELPER" MEMORY_TEST_REPO="$runtime_repo" \
bash -c '
  printf() {
    case "${2:-}" in
      */memory-write-state/handle.*) return 1 ;;
    esac
    builtin printf "$@"
  }
  source "$MEMORY_TEST_HELPER" acquire "$MEMORY_TEST_REPO"
' >"$runtime_repo/acquire.out" 2>"$runtime_repo/acquire.err"
stdout_failure_status=$?
if [ "$stdout_failure_status" -ne 0 ] && [ ! -s "$runtime_repo/acquire.out" ] \
  && [ ! -e "$runtime_repo/.git/memory-write.lock" ] \
  && ! find "$runtime_repo/.git/memory-write-state" -mindepth 1 -print -quit | grep -q .; then
  pass "failed handle stdout removes untransferred ownership"
else
  fail "failed handle stdout left unreachable ownership or returned success"
fi

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
