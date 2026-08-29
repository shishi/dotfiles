#!/usr/bin/env bash
# Finish one daily memory capture after the caller edits the selected files.
# One invocation stages exact paths, commits, pushes, verifies the remote, and
# releases the cross-process lock acquired by memory-write-preflight.sh.
set -u

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn() { echo "memory-write-finish: $1" >&2; }

contains_newline() {
  case "$1" in
    *"
"*) return 0 ;;
    *) return 1 ;;
  esac
}

read_state_line() {
  local file=$1 value file_bytes value_bytes

  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  file_bytes="$({ wc -c <"$file"; } 2>/dev/null | tr -d '[:space:]')" || return 1
  { IFS= read -r value <"$file"; } 2>/dev/null || return 1
  value_bytes="$(printf '%s' "$value" | wc -c | tr -d '[:space:]')" || return 1
  case "$file_bytes:$value_bytes" in *[!0-9:]*) return 1 ;; esac
  [ "$file_bytes" -eq $((value_bytes + 1)) ] || return 1
  printf '%s\n' "$value"
}

has_other_entries() {
  local directory=$1 own1=${2:-} own2=${3:-} entry

  for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
    if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
      continue
    fi
    [ -n "$own1" ] && [ "$entry" = "$own1" ] && continue
    [ -n "$own2" ] && [ "$entry" = "$own2" ] && continue
    return 0
  done
  return 1
}

link=${1:-}
handle=${2:-}
message=${3:-}
if [ -n "$handle" ]; then
  owns_lock=true
else
  owns_lock=false
fi
status_file=""
cleanup() {
  local status=$?
  trap '' HUP INT TERM
  trap - EXIT
  [ -z "$status_file" ] || rm -f "$status_file"
  if [ "$owns_lock" = true ]; then
    if ! bash "$BIN_DIR/memory-write-lock.sh" release "$handle"; then
      warn "write lock could not be released; manual recovery is required"
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$#" -lt 4 ] || [ -z "$link" ] || [ -z "$handle" ] || [ -z "$message" ]; then
  warn "usage: memory-write-finish.sh <memory-link> <lock-handle> <message> <path>..."
  exit 2
fi
shift 3
paths=("$@")

# Test-only injection point for the signal boundary immediately after traps.
if [ -n "${FINISH_TEST_MARKER:-}" ]; then
  : >"$FINISH_TEST_MARKER"
fi
if [ -n "${FINISH_PAUSE_AFTER_TRAP:-}" ]; then
  sleep "$FINISH_PAUSE_AFTER_TRAP"
fi

repo="$(bash "$BIN_DIR/resolve-memory-dir.sh")" \
  || { warn "memory repo could not be resolved"; exit 1; }
repo="$(cd "$repo" 2>/dev/null && pwd -P)" \
  || { warn "memory repo is not accessible"; exit 1; }
link_physical="$(cd "$link" 2>/dev/null && pwd -P)" \
  || { warn "memory link is not accessible"; exit 1; }
[ "$link_physical" = "$repo" ] \
  || { warn "memory link does not resolve to the canonical repo"; exit 1; }

case "$handle" in
  "$repo/.git/memory-write-state/handle."*) ;;
  *) warn "lock handle does not belong to the memory repo"; exit 1 ;;
esac
state_root="$repo/.git/memory-write-state"
lock="$repo/.git/memory-write.lock"
handle_parent="$(cd "$(dirname "$handle")" 2>/dev/null && pwd -P)" || handle_parent=""
recorded_repo="$(read_state_line "$handle/repo")" || recorded_repo=""
token="$(read_state_line "$handle/token")" || token=""
case "$token" in
  ''|*[!0-9a-f]*) token_valid=false ;;
  *) [ "${#token}" -eq 64 ] && token_valid=true || token_valid=false ;;
esac
owner="$lock/owner-$token"
recorded_owner="$(read_state_line "$owner/value")" || recorded_owner=""
if [ "$recorded_repo" != "$repo" ] || [ "$token_valid" != true ] \
  || [ "$recorded_owner" != "$token" ] \
  || [ ! -d "$handle" ] || [ -L "$handle" ] \
  || [ "$handle_parent" != "$state_root" ] \
  || [ ! -d "$lock" ] || [ -L "$lock" ] \
  || [ ! -d "$owner" ] || [ -L "$owner" ] \
  || has_other_entries "$handle" "$handle/repo" "$handle/token" \
  || has_other_entries "$state_root" "$handle" \
  || has_other_entries "$lock" "$owner" \
  || has_other_entries "$owner" "$owner/value"; then
  warn "lock handle is invalid"
  exit 1
fi

is_allowed_path() {
  local candidate=$1 allowed
  for allowed in "${paths[@]}"; do
    [ "$candidate" = "$allowed" ] && return 0
  done
  return 1
}

for path in "${paths[@]}"; do
  if [ -z "$path" ] || contains_newline "$path"; then
    warn "memory path is invalid"
    exit 1
  fi
  case "$path" in
    /*|.git|.git/*|..|../*|*/..|*/../*)
      warn "memory path must stay inside the repo"
      exit 1
      ;;
  esac
done

branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" \
  || { warn "branch could not be determined"; exit 1; }
upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" \
  || { warn "upstream could not be determined"; exit 1; }
if [ "$branch" != main ] || [ "$upstream" != origin/main ]; then
  warn "memory repo is not main tracking origin/main"
  exit 1
fi

status_file="$(mktemp "${TMPDIR:-/tmp}/memory-write-finish.XXXXXX")" \
  || { warn "temporary status file could not be created"; exit 1; }
git -C "$repo" status --porcelain=v1 -z >"$status_file" \
  || { warn "worktree state could not be determined"; exit 1; }
while IFS= read -r -d '' entry; do
  code=${entry:0:2}
  case "$code" in
    *R*|*C*) warn "renamed memory paths are unsupported"; exit 1 ;;
  esac
  path=${entry:3}
  if ! is_allowed_path "$path"; then
    warn "unexpected worktree change: $path"
    exit 1
  fi
done <"$status_file"

git -C "$repo" add -- "${paths[@]}" \
  || { warn "memory paths could not be staged"; exit 1; }
git -C "$repo" diff --cached --quiet
diff_status=$?
if [ "$diff_status" -eq 0 ]; then
  owns_lock=false
  if ! bash "$BIN_DIR/memory-write-lock.sh" release "$handle"; then
    warn "write lock could not be released; manual recovery is required"
    exit 1
  fi
  rm -f "$status_file"
  status_file=""
  trap - EXIT HUP INT TERM
  echo NO_CHANGES
  exit 0
fi
if [ "$diff_status" -ne 1 ]; then
  warn "staged diff could not be determined"
  exit 1
fi

git -C "$repo" diff --cached --name-only -z >"$status_file" \
  || { warn "staged paths could not be determined"; exit 1; }
while IFS= read -r -d '' path; do
  if ! is_allowed_path "$path"; then
    warn "unexpected staged path: $path"
    exit 1
  fi
done <"$status_file"

git -C "$repo" commit -m "$message" >&2 \
  || { warn "memory commit failed"; exit 1; }
commit="$(git -C "$repo" rev-parse HEAD)" \
  || { warn "memory commit could not be resolved"; exit 1; }

git -C "$repo" diff-tree --no-commit-id --name-only -z -r "$commit" >"$status_file" \
  || { warn "committed paths could not be determined"; exit 1; }
while IFS= read -r -d '' path; do
  if ! is_allowed_path "$path"; then
    warn "commit contains an unexpected path: $path"
    exit 1
  fi
done <"$status_file"

git -C "$repo" push origin main >&2 \
  || { warn "memory push failed"; exit 1; }
git -C "$repo" fetch origin main >&2 \
  || { warn "remote verification fetch failed"; exit 1; }
git -C "$repo" merge-base --is-ancestor "$commit" origin/main \
  || { warn "remote main does not contain the memory commit"; exit 1; }
post_status="$(git -C "$repo" status --porcelain)" \
  || { warn "post-commit worktree state could not be determined"; exit 1; }
[ -z "$post_status" ] \
  || { warn "memory worktree is not clean after commit"; exit 1; }

owns_lock=false
if ! bash "$BIN_DIR/memory-write-lock.sh" release "$handle"; then
  warn "write lock could not be released; manual recovery is required"
  exit 1
fi
rm -f "$status_file"
status_file=""
trap - EXIT HUP INT TERM
printf '%s\n' "$commit"
