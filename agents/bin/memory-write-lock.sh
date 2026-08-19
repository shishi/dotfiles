#!/usr/bin/env bash
# Keep the shared agent-memory write lock across separate tool processes.
set -u
umask 077

warn() { echo "memory-write-lock: $1" >&2; }

contains_newline() {
  case "$1" in
    *"
"*) return 0 ;;
    *) return 1 ;;
  esac
}

stat_mode() {
  case "$(uname -s)" in
    Darwin | FreeBSD | OpenBSD | NetBSD) stat -f '%Lp' "$1" 2>/dev/null ;;
    *) stat -c '%a' "$1" 2>/dev/null ;;
  esac
}

canonical_repo() {
  local candidate="$1" physical

  [ -n "$candidate" ] && ! contains_newline "$candidate" || return 1
  [ -d "$candidate" ] && [ ! -L "$candidate" ] || return 1
  physical="$(cd "$candidate" 2>/dev/null && pwd -P)" || return 1
  [ "$candidate" = "$physical" ] || return 1
  [ -d "$candidate/.git" ] && [ ! -L "$candidate/.git" ] || return 1
  printf '%s\n' "$physical"
}

retirement_exists() {
  local repo="$1" entry

  for entry in "$repo/.git"/memory-write.lock.retired-* \
    "$repo/.git"/memory-write-retirement.*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      return 0
    fi
  done
  return 1
}

state_has_other_entries() {
  local state_root="$1" own="${2:-}" own2="${3:-}" entry

  for entry in "$state_root"/* "$state_root"/.[!.]* "$state_root"/..?*; do
    if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
      continue
    fi
    [ -n "$own" ] && [ "$entry" = "$own" ] && continue
    [ -n "$own2" ] && [ "$entry" = "$own2" ] && continue
    return 0
  done
  return 1
}

ensure_state_root() {
  local state_root="$1"

  if [ -e "$state_root" ] || [ -L "$state_root" ]; then
    [ -d "$state_root" ] && [ ! -L "$state_root" ] || return 1
    [ "$(stat_mode "$state_root")" = 700 ] || return 1
    return 0
  fi
  (umask 077 && mkdir "$state_root") 2>/dev/null || return 1
  [ "$(stat_mode "$state_root")" = 700 ]
}

valid_token() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in
    *[!0-9a-f]*|'') return 1 ;;
    *) return 0 ;;
  esac
}

random_hex() {
  local bytes="$1" value

  value="$(od -An -N"$bytes" -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')" \
    || return 1
  [ "${#value}" -eq $((bytes * 2)) ] || return 1
  case "$value" in *[!0-9a-f]*|'') return 1 ;; esac
  printf '%s\n' "$value"
}

private_container=""

create_private_container() {
  local parent="$1" prefix="$2" nonce physical physical_parent

  private_container=""
  nonce="$(random_hex 32)" || return 1
  private_container="$parent/$prefix$nonce"
  mkdir "$private_container" 2>/dev/null || return 1
  [ -d "$private_container" ] && [ ! -L "$private_container" ] \
    && [ "$(stat_mode "$private_container")" = 700 ] || return 1
  physical="$(cd "$private_container" 2>/dev/null && pwd -P)" \
    && physical_parent="$(cd "$(dirname "$private_container")" 2>/dev/null && pwd -P)" \
    || return 1
  [ "$physical" = "$private_container" ] && [ "$physical_parent" = "$parent" ]
}

remove_owned_lock() {
  local repo="$1" token="$2" lock retired owner recorded_token

  lock="$repo/.git/memory-write.lock"
  owner="$lock/owner-$token"
  [ -d "$lock" ] && [ ! -L "$lock" ] || return 1
  state_has_other_entries "$lock" "$owner" && return 1
  [ -d "$owner" ] && [ ! -L "$owner" ] \
    && [ "$(stat_mode "$owner")" = 700 ] || return 1
  state_has_other_entries "$owner" "$owner/value" && return 1
  recorded_token="$(read_state_line "$owner/value")" || return 1
  [ "$recorded_token" = "$token" ] || return 1
  create_private_container "$repo/.git" "memory-write-retirement." || return 1
  retired="$private_container/lock"
  [ ! -e "$retired" ] && [ ! -L "$retired" ] || return 1
  mv "$lock" "$retired" 2>/dev/null || return 1
  [ ! -e "$lock" ] && [ ! -L "$lock" ] || return 1
  [ -d "$retired" ] && [ ! -L "$retired" ] || return 1
  owner="$retired/owner-$token"
  state_has_other_entries "$retired" "$owner" && return 1
  [ -d "$owner" ] && [ ! -L "$owner" ] \
    && [ "$(stat_mode "$owner")" = 700 ] || return 1
  state_has_other_entries "$owner" "$owner/value" && return 1
  recorded_token="$(read_state_line "$owner/value")" || return 1
  [ "$recorded_token" = "$token" ] || return 1
  rm "$owner/value" 2>/dev/null || return 1
  rmdir "$owner" 2>/dev/null || return 1
  rmdir "$retired" 2>/dev/null || return 1
  rmdir "$private_container" 2>/dev/null
}

remove_state_directory() {
  local state="$1"

  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  rm "$state/repo" "$state/token" 2>/dev/null || return 1
  rmdir "$state" 2>/dev/null
}

retired_state_matches() {
  local retired="$1" expected_repo="$2" expected_token="$3" state_root="$4"
  local actual_repo actual_token physical parent retirement_root retirement_root_parent

  [ -d "$retired" ] && [ ! -L "$retired" ] \
    && [ "$(stat_mode "$retired")" = 700 ] || return 1
  state_has_other_entries "$retired" "$retired/repo" "$retired/token" && return 1
  actual_repo="$(read_state_line "$retired/repo")" \
    && actual_token="$(read_state_line "$retired/token")" || return 1
  [ "$actual_repo" = "$expected_repo" ] && [ "$actual_token" = "$expected_token" ] \
    || return 1
  valid_token "$actual_token" || return 1
  retirement_root="$(dirname "$retired")"
  [ -d "$retirement_root" ] && [ ! -L "$retirement_root" ] \
    && [ "$(stat_mode "$retirement_root")" = 700 ] || return 1
  physical="$(cd "$retired" 2>/dev/null && pwd -P)" \
    && parent="$(cd "$(dirname "$retired")" 2>/dev/null && pwd -P)" || return 1
  retirement_root_parent="$(cd "$(dirname "$retirement_root")" 2>/dev/null && pwd -P)" \
    || return 1
  [ "$physical" = "$retired" ] && [ "$parent" = "$retirement_root" ] \
    && [ "$retirement_root_parent" = "$state_root" ] || return 1
  [ "$(canonical_repo "$actual_repo")" = "$expected_repo" ]
}

state_directory_matches() {
  local state="$1" expected_repo="$2" expected_token="$3" expected_parent="$4"
  local actual_repo actual_token physical parent

  [ -d "$state" ] && [ ! -L "$state" ] \
    && [ "$(stat_mode "$state")" = 700 ] || return 1
  state_has_other_entries "$state" "$state/repo" "$state/token" && return 1
  actual_repo="$(read_state_line "$state/repo")" \
    && actual_token="$(read_state_line "$state/token")" || return 1
  [ "$actual_repo" = "$expected_repo" ] && [ "$actual_token" = "$expected_token" ] \
    || return 1
  physical="$(cd "$state" 2>/dev/null && pwd -P)" \
    && parent="$(cd "$(dirname "$state")" 2>/dev/null && pwd -P)" || return 1
  [ "$physical" = "$state" ] && [ "$parent" = "$expected_parent" ]
}

retired_state_root=""
retired_state_path=""

retire_state_directory() {
  local state="$1" repo="$2" token="$3" state_root="$4"
  local retirement_root retired

  retired_state_root=""
  retired_state_path=""
  create_private_container "$state_root" "retired-" || return 1
  retirement_root="$private_container"
  retired="$retirement_root/state"
  [ ! -e "$retired" ] && [ ! -L "$retired" ] || return 1
  mv "$state" "$retired" 2>/dev/null || return 1
  [ ! -e "$state" ] && [ ! -L "$state" ] || return 1
  retired_state_matches "$retired" "$repo" "$token" "$state_root" || return 1
  retired_state_root="$retirement_root"
  retired_state_path="$retired"
}

remove_retired_state() {
  local retired="$1" retirement_root="$2"

  remove_state_directory "$retired" \
    && rmdir "$retirement_root" 2>/dev/null
}

acquire_repo=""
acquire_owner_value=""
acquire_handle=""
acquire_handle_active=false
acquire_lock_created=false
acquire_owned=false
acquire_committed=false
acquire_pending_signal=""
acquire_critical=false

cleanup_partial_acquire() {
  local cleanup_status=0 lock_cleanup_status=0 lock owner state_to_retire=""
  local state_root="" state_retired=false

  [ "$acquire_handle_active" = true ] && state_to_retire="$acquire_handle"
  if [ -n "$state_to_retire" ] \
    && { [ -e "$state_to_retire" ] || [ -L "$state_to_retire" ]; }; then
    state_root="$(dirname "$state_to_retire")"
    if retire_state_directory "$state_to_retire" "$acquire_repo" \
      "$acquire_owner_value" "$state_root"; then
      state_retired=true
    else
      cleanup_status=1
    fi
  fi

  if [ "$acquire_owned" = true ]; then
    remove_owned_lock "$acquire_repo" "$acquire_owner_value" || lock_cleanup_status=1
  elif [ "$acquire_lock_created" = true ]; then
    lock="$acquire_repo/.git/memory-write.lock"
    owner="$lock/owner-$acquire_owner_value"
    if [ -d "$owner" ] && [ ! -L "$owner" ]; then
      remove_owned_lock "$acquire_repo" "$acquire_owner_value" || lock_cleanup_status=1
    else
      lock_cleanup_status=1
    fi
  fi
  [ "$lock_cleanup_status" -eq 0 ] || cleanup_status=1
  if [ "$state_retired" = true ]; then
    if [ "$lock_cleanup_status" -eq 0 ]; then
      remove_retired_state "$retired_state_path" "$retired_state_root" \
        || cleanup_status=1
    else
      cleanup_status=1
    fi
  fi
  return "$cleanup_status"
}

finish_acquire() {
  local status=$? cleanup_status=0

  trap '' HUP INT TERM
  trap - EXIT
  if [ "$acquire_committed" = true ]; then
    exit 0
  fi
  cleanup_partial_acquire || cleanup_status=1
  if [ -n "$acquire_pending_signal" ]; then
    exit "$acquire_pending_signal"
  fi
  [ "$status" -ne 0 ] && exit "$status"
  exit "$cleanup_status"
}

handle_acquire_signal() {
  [ -n "$acquire_pending_signal" ] || acquire_pending_signal="$1"
  [ "$acquire_critical" = true ] && return 0
  exit "$acquire_pending_signal"
}

acquire() {
  local requested_repo="$1" state_root lock owner owner_tmp handle token suffix
  local recorded_token state_status=0

  acquire_repo="$(canonical_repo "$requested_repo")" || {
    warn "canonical repository is invalid"
    return 1
  }
  state_root="$acquire_repo/.git/memory-write-state"
  lock="$acquire_repo/.git/memory-write.lock"
  ensure_state_root "$state_root" || {
    warn "private state is unavailable"
    return 1
  }
  if retirement_exists "$acquire_repo" || state_has_other_entries "$state_root"; then
    warn "write-lock recovery is required"
    return 1
  fi

  token="$(random_hex 32)"
  valid_token "$token" || {
    warn "owner state could not be created"
    return 1
  }
  acquire_owner_value="$token"

  trap finish_acquire EXIT
  trap 'handle_acquire_signal 129' HUP
  trap 'handle_acquire_signal 130' INT
  trap 'handle_acquire_signal 143' TERM

  suffix="$(random_hex 16)" || {
    warn "owner state could not be created"
    return 1
  }
  handle="$state_root/handle.$suffix"
  acquire_handle="$handle"
  acquire_critical=true
  if ! mkdir "$handle" 2>/dev/null; then
    acquire_critical=false
    if [ -n "$acquire_pending_signal" ]; then exit "$acquire_pending_signal"; fi
    warn "owner state could not be created"
    return 1
  fi
  acquire_handle_active=true
  if ! printf '%s\n' "$acquire_repo" >"$handle/repo" \
    || ! printf '%s\n' "$token" >"$handle/token" \
    || ! state_directory_matches "$handle" "$acquire_repo" "$token" "$state_root" \
    || state_has_other_entries "$state_root" "$handle" \
    || retirement_exists "$acquire_repo"; then
    state_status=1
  fi
  acquire_critical=false
  if [ -n "$acquire_pending_signal" ]; then exit "$acquire_pending_signal"; fi
  if [ "$state_status" -ne 0 ]; then
    warn "write-lock recovery is required"
    return 1
  fi

  acquire_critical=true
  mkdir "$lock" 2>/dev/null || {
    warn "write lock is already held"
    return 1
  }
  acquire_lock_created=true
  owner_tmp=""
  owner="$lock/owner-$token"
  if ! owner_tmp="$(umask 077 && mktemp "$lock/.owner.XXXXXX")" \
    || ! printf '%s\n' "$token" >"$owner_tmp" \
    || [ "$(stat_mode "$owner_tmp")" != 600 ] \
    || ! mkdir "$owner" 2>/dev/null \
    || [ ! -d "$owner" ] || [ -L "$owner" ] \
    || [ "$(stat_mode "$owner")" != 700 ] \
    || ! mv "$owner_tmp" "$owner/value" 2>/dev/null \
    || [ -e "$owner_tmp" ] || [ -L "$owner_tmp" ] \
    || state_has_other_entries "$owner" "$owner/value" \
    || ! recorded_token="$(read_state_line "$owner/value")" \
    || [ "$recorded_token" != "$token" ] \
    || state_has_other_entries "$lock" "$owner"; then
    [ -z "${owner_tmp:-}" ] || rm -f "$owner_tmp" 2>/dev/null
    warn "owner state could not be created"
    return 1
  fi
  acquire_owned=true
  acquire_critical=false
  if [ -n "$acquire_pending_signal" ]; then
    exit "$acquire_pending_signal"
  fi

  if retirement_exists "$acquire_repo" \
    || state_has_other_entries "$state_root" "$handle"; then
    warn "write-lock recovery is required"
    return 1
  fi

  acquire_critical=true
  if ! printf '%s\n' "$handle"; then
    acquire_critical=false
    warn "owner state could not be transferred"
    return 1
  fi
  if [ -n "$acquire_pending_signal" ]; then
    acquire_critical=false
    exit "$acquire_pending_signal"
  fi
  if ! trap '' HUP INT TERM; then
    acquire_critical=false
    warn "owner state could not be transferred"
    return 1
  fi
  if [ -n "$acquire_pending_signal" ]; then
    acquire_critical=false
    exit "$acquire_pending_signal"
  fi
  acquire_committed=true
  acquire_critical=false
}

read_state_line() {
  local file="$1" value file_bytes value_bytes

  [ -f "$file" ] && [ ! -L "$file" ] && [ "$(stat_mode "$file")" = 600 ] || return 1
  file_bytes="$({ wc -c <"$file"; } 2>/dev/null | tr -d '[:space:]')" || return 1
  { IFS= read -r value <"$file"; } 2>/dev/null || return 1
  value_bytes="$(printf '%s' "$value" | wc -c | tr -d '[:space:]')" || return 1
  case "$file_bytes:$value_bytes" in
    *[!0-9:]*) return 1 ;;
  esac
  [ "$file_bytes" -eq $((value_bytes + 1)) ] || return 1
  printf '%s\n' "$value"
}

release_critical=false
release_pending_signal=""

handle_release_signal() {
  [ -n "$release_pending_signal" ] || release_pending_signal="$1"
  [ "$release_critical" = true ] && return 0
  exit "$release_pending_signal"
}

release() {
  local handle="$1" repo token expected_prefix state_root state_root_physical handle_parent
  local release_status=0

  if [ -z "$handle" ] || contains_newline "$handle" \
    || [ ! -d "$handle" ] || [ -L "$handle" ] \
    || [ "$(stat_mode "$handle")" != 700 ]; then
    warn "handle is invalid"
    return 1
  fi
  if state_has_other_entries "$handle" "$handle/repo" "$handle/token"; then
    warn "handle is invalid"
    return 1
  fi
  if ! repo="$(read_state_line "$handle/repo")" \
    || ! token="$(read_state_line "$handle/token")"; then
    warn "handle is invalid"
    return 1
  fi
  repo="$(canonical_repo "$repo")" || {
    warn "handle is invalid"
    return 1
  }
  valid_token "$token" || {
    warn "handle is invalid"
    return 1
  }
  state_root="$repo/.git/memory-write-state"
  if [ ! -d "$state_root" ] || [ -L "$state_root" ] \
    || [ "$(stat_mode "$state_root")" != 700 ]; then
    warn "handle is invalid"
    return 1
  fi
  if ! state_root_physical="$(cd "$state_root" 2>/dev/null && pwd -P)" \
    || ! handle_parent="$(cd "$(dirname "$handle")" 2>/dev/null && pwd -P)"; then
    warn "handle is invalid"
    return 1
  fi
  if [ "$state_root_physical" != "$state_root" ] \
    || [ "$handle_parent" != "$state_root" ]; then
    warn "handle is invalid"
    return 1
  fi
  expected_prefix="$repo/.git/memory-write-state/handle."
  case "$handle" in
    "$expected_prefix"*) ;;
    *) warn "handle is invalid"; return 1 ;;
  esac
  case "${handle#"$expected_prefix"}" in
    ''|*/*|retired-*) warn "handle is invalid"; return 1 ;;
  esac
  if state_has_other_entries "$state_root" "$handle"; then
    warn "write-lock recovery is required"
    return 1
  fi

  trap 'handle_release_signal 129' HUP
  trap 'handle_release_signal 130' INT
  trap 'handle_release_signal 143' TERM
  release_critical=true
  if ! retire_state_directory "$handle" "$repo" "$token" "$state_root"; then
    warn "private state could not be retired"
    release_status=1
  elif ! remove_owned_lock "$repo" "$token"; then
    warn "write lock could not be released"
    release_status=1
  elif ! remove_retired_state "$retired_state_path" "$retired_state_root"; then
    warn "private state could not be removed"
    release_status=1
  fi
  release_critical=false
  trap - HUP INT TERM
  if [ -n "$release_pending_signal" ]; then
    exit "$release_pending_signal"
  fi
  return "$release_status"
}

main() {
  if [ "$#" -ne 2 ]; then
    warn "usage: acquire <canonical-repo> | release <opaque-handle>"
    return 2
  fi
  case "$1" in
    acquire) acquire "$2" ;;
    release) release "$2" ;;
    *) warn "usage: acquire <canonical-repo> | release <opaque-handle>"; return 2 ;;
  esac
}

main "$@"
