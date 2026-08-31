#!/usr/bin/env bash
# Commit and publish one daily memory capture, then release its preflight lock.
set -u

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn() { echo "memory-write-finish: $1" >&2; }

link=${1:-}
handle=${2:-}
message=${3:-}
owns_lock=false
[ -z "$handle" ] || owns_lock=true

cleanup() {
  local status=$?
  trap '' HUP INT TERM
  trap - EXIT
  if [ "$owns_lock" = true ] \
    && ! bash "$BIN_DIR/memory-write-lock.sh" release "$handle"; then
    warn "write lock could not be released; manual recovery is required"
    status=1
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

repo="$(bash "$BIN_DIR/resolve-memory-dir.sh")" \
  || { warn "memory repo could not be resolved"; exit 1; }
repo="$(cd "$repo" 2>/dev/null && pwd -P)" \
  || { warn "memory repo is not accessible"; exit 1; }
link_physical="$(cd "$link" 2>/dev/null && pwd -P)" \
  || { warn "memory link is not accessible"; exit 1; }
[ "$link_physical" = "$repo" ] \
  || { warn "memory link does not resolve to the canonical repo"; exit 1; }

branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" \
  || { warn "branch could not be determined"; exit 1; }
upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" \
  || { warn "upstream could not be determined"; exit 1; }
if [ "$branch" != main ] || [ "$upstream" != origin/main ]; then
  warn "memory repo is not main tracking origin/main"
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
  case "$path" in
    ''|/*|.git|.git/*|..|../*|*/..|*/../*)
      warn "memory path must stay inside the repo"
      exit 1
      ;;
  esac
done

worktree_status="$(git -C "$repo" status --porcelain)" \
  || { warn "worktree state could not be determined"; exit 1; }
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  code=${entry:0:2}
  case "$code" in
    *R*|*C*) warn "renamed memory paths are unsupported"; exit 1 ;;
  esac
  path=${entry:3}
  if ! is_allowed_path "$path"; then
    warn "unexpected worktree change: $path"
    exit 1
  fi
done <<<"$worktree_status"

git -C "$repo" add -- "${paths[@]}" \
  || { warn "memory paths could not be staged"; exit 1; }
git -C "$repo" diff --cached --quiet
diff_status=$?
if [ "$diff_status" -eq 0 ]; then
  owns_lock=false
  bash "$BIN_DIR/memory-write-lock.sh" release "$handle" \
    || { warn "write lock could not be released; manual recovery is required"; exit 1; }
  trap - EXIT HUP INT TERM
  echo NO_CHANGES
  exit 0
fi
[ "$diff_status" -eq 1 ] \
  || { warn "staged diff could not be determined"; exit 1; }

git -C "$repo" commit -m "$message" >&2 \
  || { warn "memory commit failed"; exit 1; }
commit="$(git -C "$repo" rev-parse HEAD)" \
  || { warn "memory commit could not be resolved"; exit 1; }
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
bash "$BIN_DIR/memory-write-lock.sh" release "$handle" \
  || { warn "write lock could not be released; manual recovery is required"; exit 1; }
trap - EXIT HUP INT TERM
printf '%s\n' "$commit"
