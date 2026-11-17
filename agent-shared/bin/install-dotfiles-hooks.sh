#!/usr/bin/env bash
set -eu

repo_root=$(git rev-parse --show-toplevel)
hook_dir=$(git rev-parse --git-path hooks)
case "$hook_dir" in /* | ?:/*) ;; *) hook_dir="$repo_root/$hook_dir" ;; esac
mkdir -p "$hook_dir"
hook="$hook_dir/pre-commit"
runner="$hook_dir/pre-commit.dotfiles"
marker='# managed by dotfiles: portability dispatcher'
git config --local dotfiles.portabilityCheck true

if [ -f "$hook" ] && grep -Fxq "$marker" "$hook"; then
  cp "$repo_root/agent-shared/git-hooks/pre-commit" "$runner"
  chmod +x "$runner"
  exit 0
fi
if [ -e "$runner" ] || [ -L "$runner" ]; then
  echo "dotfiles hooks: $runner already exists and is not managed by this installer" >&2
  exit 1
fi

previous=
if [ -e "$hook" ] || [ -L "$hook" ]; then
  previous=$(mktemp "$hook_dir/pre-commit.previous.XXXXXX")
fi
dispatcher=$(mktemp "$hook_dir/pre-commit.install.XXXXXX")
trap 'rm -f "$dispatcher"; if [ -n "$previous" ] && [ ! -e "$hook" ]; then mv "$previous" "$hook"; fi' EXIT
{
  printf '#!/bin/sh\n%s\nset -eu\n' "$marker"
  printf 'hook_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)\n'
  printf '"$hook_dir/pre-commit.dotfiles" "$@"\n'
  if [ -n "$previous" ]; then
    printf 'if [ -x "$hook_dir/%s" ]; then exec "$hook_dir/%s" "$@"; fi\n' "${previous##*/}" "${previous##*/}"
  fi
} > "$dispatcher"
chmod +x "$dispatcher"
cp "$repo_root/agent-shared/git-hooks/pre-commit" "$runner"
chmod +x "$runner"
if [ -n "$previous" ]; then mv "$hook" "$previous"; fi
mv "$dispatcher" "$hook"
trap - EXIT
