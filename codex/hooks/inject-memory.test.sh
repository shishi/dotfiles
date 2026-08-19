#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INJECTOR="${SCRIPT_DIR}/../../agents/hooks/inject-memory.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-inject-memory.XXXXXX") || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'not ok: %s\n' "$1" >&2
  exit 1
}

MEMORY_DIR="${TMP_DIR}/agent-memory"
PROJECT_DIR="${TMP_DIR}/dotfiles"
mkdir -p "${MEMORY_DIR}/projects" "$PROJECT_DIR"

git -C "$MEMORY_DIR" init -q
git -C "$MEMORY_DIR" branch -M main
git -C "$MEMORY_DIR" config user.name 'Codex Hook Test'
git -C "$MEMORY_DIR" config user.email 'codex-hook-test@example.invalid'
git -C "$MEMORY_DIR" config commit.gpgSign false
printf '%s\n' '# Global fixture memory' 'GLOBAL_MEMORY_SENTINEL' >"${MEMORY_DIR}/MEMORY.md"
printf '%s\n' '# Dotfiles fixture memory' 'PROJECT_MEMORY_SENTINEL' >"${MEMORY_DIR}/projects/github.com-shishi-dotfiles.md"
git -C "$MEMORY_DIR" add MEMORY.md projects/github.com-shishi-dotfiles.md
git -C "$MEMORY_DIR" commit -q -m 'test: seed memory fixture'

git -C "$PROJECT_DIR" init -q
git -C "$PROJECT_DIR" remote add origin 'git@github.com:shishi/dotfiles.git'

payload=$(printf '{"cwd":"%s","source":"startup"}' "$PROJECT_DIR")
output=$(printf '%s' "$payload" | bash "$INJECTOR" "$MEMORY_DIR") || fail 'shared memory injector exited unsuccessfully'

case "$output" in *'<personal-memory>'*'</personal-memory>'*) ;; *) fail 'personal-memory wrapper is missing' ;; esac
case "$output" in *'GLOBAL_MEMORY_SENTINEL'*) ;; *) fail 'MEMORY.md content is missing' ;; esac
case "$output" in *'projects/github.com-shishi-dotfiles.md'*) ;; *) fail 'dotfiles project slug is not selected' ;; esac
case "$output" in *'PROJECT_MEMORY_SENTINEL'*) ;; *) fail 'dotfiles project memory content is missing' ;; esac

printf '%s\n' 'ok: Codex SessionStart input receives global and dotfiles project memory from the shared injector'
