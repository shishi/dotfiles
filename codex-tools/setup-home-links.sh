#!/usr/bin/env bash
set -uo pipefail

case "$(uname -s)" in
  MINGW*|MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "${TOOLS_DIR}/.." && pwd)"
if [ "$#" -gt 1 ]; then
  echo "setup-home-links: usage: setup-home-links.sh" >&2
  exit 2
fi
DOTFILES_DIR="${1:-$DOTFILES_ROOT}"
CODEX_SOURCE="${DOTFILES_DIR}/codex"
SKILLS_SOURCE="${CODEX_SOURCE}/skills"
CODEX_TARGET="${HOME}/.codex"
SKILLS_TARGET="${HOME}/.agents/skills"
LOCK_DIR="${HOME}/.codex-setup-home-links.lock"

fail() {
  echo "setup-home-links: ERROR $*" >&2
  return 1
}

same_link() {
  local source_path target_path
  [ -L "$2" ] || return 1
  source_path="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  target_path="$(cd "$2" 2>/dev/null && pwd -P)" || return 1
  [ "$target_path" = "$source_path" ]
}

[ -d "$CODEX_SOURCE" ] || { fail "missing source: $CODEX_SOURCE"; exit 1; }
[ -d "$SKILLS_SOURCE" ] || { fail "missing source: $SKILLS_SOURCE"; exit 1; }
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "setup already running: $LOCK_DIR"
  exit 1
fi
trap 'rmdir "$LOCK_DIR"' EXIT
mkdir -p "${HOME}/.agents"

for pair in "$CODEX_SOURCE|$CODEX_TARGET" "$SKILLS_SOURCE|$SKILLS_TARGET"; do
  source_path="${pair%%|*}"
  target_path="${pair#*|}"
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    same_link "$source_path" "$target_path" \
      || { fail "refusing to replace existing path: $target_path"; exit 1; }
  fi
done

probe="$(mktemp -d "${HOME}/.codex-link-probe.XXXXXX")" || exit 1
mkdir "$probe/target"
if ! ln -s "$probe/target" "$probe/link" 2>/dev/null || [ ! -L "$probe/link" ]; then
  rm -rf "$probe"
  fail "directory symlink creation unavailable; enable Developer Mode or elevate"
  exit 1
fi
rm -rf "$probe"

created_codex=0
created_skills=0
created_codex_source=""
created_skills_source=""

link_matches_source() {
  local expected_source="$1"
  local target_path="$2"
  local actual_source

  [ -L "$target_path" ] || return 1
  actual_source="$(readlink "$target_path")" || return 1
  [ "$actual_source" = "$expected_source" ]
}

remove_created_link() {
  local expected_source="$1"
  local target_path="$2"
  local quarantine_path="${target_path}.rollback-quarantine"
  local suffix=0

  while [ -e "$quarantine_path" ] || [ -L "$quarantine_path" ]; do
    suffix=$((suffix + 1))
    quarantine_path="${target_path}.rollback-quarantine-${suffix}"
  done
  if ! mv "$target_path" "$quarantine_path"; then
    fail "could not quarantine created link: $target_path"
    return 1
  fi
  if ! link_matches_source "$expected_source" "$quarantine_path"; then
    fail "ownership changed: $target_path (retained at $quarantine_path)"
    return 1
  fi
  # Keep verified links in quarantine. A later rm would create another
  # check/use race against an entry replaced after link_matches_source.
}

cleanup_created_links() {
  local cleanup_failed=0

  if [ "$created_skills" -eq 1 ] \
    && ! remove_created_link "$created_skills_source" "$SKILLS_TARGET"; then
    cleanup_failed=1
  fi
  if [ "$created_codex" -eq 1 ] \
    && ! remove_created_link "$created_codex_source" "$CODEX_TARGET"; then
    cleanup_failed=1
  fi

  [ "$cleanup_failed" -eq 0 ]
}

if [ ! -L "$CODEX_TARGET" ]; then
  if ! ln -s "$CODEX_SOURCE" "$CODEX_TARGET"; then
    fail "could not create $CODEX_TARGET"
    if link_matches_source "$CODEX_SOURCE" "$CODEX_TARGET"; then
      created_codex=1
      created_codex_source="$CODEX_SOURCE"
      cleanup_created_links || fail "rollback incomplete"
    elif [ -L "$CODEX_TARGET" ]; then
      fail "ownership changed: $CODEX_TARGET"
      fail "rollback incomplete"
    fi
    exit 1
  fi
  created_codex=1
  created_codex_source="$CODEX_SOURCE"
fi

if [ ! -L "$SKILLS_TARGET" ]; then
  if ! ln -s "$SKILLS_SOURCE" "$SKILLS_TARGET"; then
    rollback_failed=0
    fail "could not create $SKILLS_TARGET"
    if link_matches_source "$SKILLS_SOURCE" "$SKILLS_TARGET"; then
      created_skills=1
      created_skills_source="$SKILLS_SOURCE"
    elif [ -L "$SKILLS_TARGET" ]; then
      fail "ownership changed: $SKILLS_TARGET"
      rollback_failed=1
    fi
    cleanup_created_links || rollback_failed=1
    [ "$rollback_failed" -eq 0 ] || fail "rollback incomplete"
    exit 1
  fi
  created_skills=1
  created_skills_source="$SKILLS_SOURCE"
fi

if ! same_link "$CODEX_SOURCE" "$CODEX_TARGET" \
  || ! same_link "$SKILLS_SOURCE" "$SKILLS_TARGET"; then
  fail "symlink verification failed"
  cleanup_created_links || fail "rollback incomplete"
  exit 1
fi
