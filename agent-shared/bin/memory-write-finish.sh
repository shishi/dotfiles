#!/usr/bin/env bash
# Commit and publish one daily memory capture, then release its preflight lock.
set -u
umask 077

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn() { echo "memory-write-finish: $1" >&2; }

patch_mode=false
patch_snapshot=""
handle=""
owns_lock=false

cleanup() {
  local status=$? cleanup_repo
  trap '' HUP INT TERM PIPE
  trap - EXIT
  if [ "$owns_lock" = true ] && [ -n "$handle" ]; then
    cleanup_repo="${repo:-}"
    if [ -z "$cleanup_repo" ]; then
      cleanup_repo="$(bash "$BIN_DIR/resolve-memory-dir.sh")" || cleanup_repo=""
    fi
    if [ -z "$cleanup_repo" ] \
      || ! cleanup_repo="$(cd "$cleanup_repo" 2>/dev/null && pwd -P)" \
      || ! bash "$BIN_DIR/memory-write-lock.sh" verify "$handle" "$cleanup_repo"; then
      warn "received handle was not released: canonical ownership could not be verified"
      status=1
    elif ! bash "$BIN_DIR/memory-write-lock.sh" release "$handle"; then
      warn "write lock could not be released; manual recovery is required"
      status=1
    fi
  fi
  [ -z "$patch_snapshot" ] || rm -f "$patch_snapshot"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 141' PIPE
trap 'exit 143' TERM

if [ "${1:-}" = --patch ]; then
  if [ "$#" -lt 6 ]; then
    warn "usage: memory-write-finish.sh --patch <memory-link> <base-commit> <patch-file> <message> <path>..."
    exit 2
  fi
  patch_mode=true
  link=$2
  base=$3
  patch_file=$4
  message=$5
  shift 5
  [ -f "$patch_file" ] && [ -r "$patch_file" ] \
    || { warn "patch file is unavailable"; exit 1; }
  patch_snapshot="$(mktemp "${TMPDIR:-/tmp}/memory-write-patch.XXXXXX")" \
    || { warn "patch snapshot could not be created"; exit 1; }
  cat "$patch_file" >"$patch_snapshot" \
    || { warn "patch snapshot could not be read"; exit 1; }
else
  link=${1:-}
  handle=${2:-}
  [ -z "$handle" ] || owns_lock=true
  message=${3:-}
  if [ "$#" -ge 3 ]; then shift 3; else set --; fi
fi
paths=("$@")

repo="$(bash "$BIN_DIR/resolve-memory-dir.sh")" \
  || { warn "memory repo could not be resolved"; exit 1; }
repo="$(cd "$repo" 2>/dev/null && pwd -P)" \
  || { warn "memory repo is not accessible"; exit 1; }
link_physical="$(cd "$link" 2>/dev/null && pwd -P)" \
  || { warn "memory link is not accessible"; exit 1; }
[ "$link_physical" = "$repo" ] \
  || { warn "memory link does not resolve to the canonical repo"; exit 1; }

if [ "$patch_mode" = true ]; then
  # Ownership stays in this process while the prepared patch is published.
  owns_lock=true
  handle="$(bash "$BIN_DIR/memory-write-preflight.sh" "$link")" \
    || { owns_lock=false; warn "write preflight failed"; exit 1; }
fi
bash "$BIN_DIR/memory-write-lock.sh" verify "$handle" "$repo" \
  || { [ "$patch_mode" = true ] || owns_lock=false; warn "write lock ownership could not be verified"; exit 1; }
owns_lock=true
if [ -z "$message" ] || [ "${#paths[@]}" -eq 0 ]; then
  warn "a memory message and at least one path are required"
  exit 2
fi

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

if [ "$patch_mode" = true ]; then
  current="$(git -C "$repo" rev-parse HEAD)" \
    || { warn "base commit could not be resolved"; exit 1; }
  [ "$current" = "$base" ] \
    || { warn "base commit changed; rebuild the patch from the synced commit"; exit 1; }
  git -C "$repo" apply --check --index -- "$patch_snapshot" \
    || { warn "memory patch could not be applied"; exit 1; }
  patch_paths="$(git -C "$repo" apply --numstat -- "$patch_snapshot")" \
    || { warn "memory patch paths could not be read"; exit 1; }
  while IFS=$'\t' read -r added deleted path; do
    if ! is_allowed_path "$path"; then
      warn "unexpected patch path: $path"
      exit 1
    fi
  done <<<"$patch_paths"
  summary="$(git -C "$repo" apply --summary -- "$patch_snapshot")" \
    || { warn "memory patch summary could not be read"; exit 1; }
  case "$summary" in
    *' rename '*|*' copy '*) warn "renamed memory paths are unsupported"; exit 1 ;;
  esac
  git -C "$repo" apply --index -- "$patch_snapshot" \
    || { warn "memory patch could not be applied"; exit 1; }
fi

status_options=(--porcelain)
[ "$patch_mode" = false ] || status_options+=(--no-renames)
worktree_status="$(git -C "$repo" status "${status_options[@]}")" \
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

if [ "$patch_mode" = false ]; then
  git -C "$repo" add -- "${paths[@]}" \
    || { warn "memory paths could not be staged"; exit 1; }
fi
git -C "$repo" diff --cached --quiet
diff_status=$?
if [ "$diff_status" -eq 0 ]; then
  result=NO_CHANGES
else
  [ "$diff_status" -eq 1 ] \
    || { warn "staged diff could not be determined"; exit 1; }

  git -C "$repo" commit -m "$message" >&2 \
    || { warn "memory commit failed"; exit 1; }
  result="$(git -C "$repo" rev-parse HEAD)" \
    || { warn "memory commit could not be resolved"; exit 1; }
  git -C "$repo" push origin main >&2 \
    || { warn "memory push failed"; exit 1; }
  git -C "$repo" fetch origin main >&2 \
    || { warn "remote verification fetch failed"; exit 1; }
  git -C "$repo" merge-base --is-ancestor "$result" origin/main \
    || { warn "remote main does not contain the memory commit"; exit 1; }
  post_status="$(git -C "$repo" status --porcelain)" \
    || { warn "post-commit worktree state could not be determined"; exit 1; }
  [ -z "$post_status" ] \
    || { warn "memory worktree is not clean after commit"; exit 1; }
fi

# Once release starts, interruption must not skip it or invoke it twice.
trap '' HUP INT TERM PIPE
owns_lock=false
bash "$BIN_DIR/memory-write-lock.sh" release "$handle" \
  || { warn "write lock could not be released; manual recovery is required"; exit 1; }
printf '%s\n' "$result"
