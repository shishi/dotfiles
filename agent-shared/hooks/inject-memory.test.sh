#!/usr/bin/env bash
# commit 済みの記憶だけを注入し、秘密らしい内容を出さない契約を検証する。
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/inject-memory.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/inject-memory.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MEMORY_DIR="$TMP/agent-memory"
PROJECT_DIR="$TMP/dotfiles"
mkdir -p "$MEMORY_DIR/projects" "$PROJECT_DIR"

git -C "$MEMORY_DIR" init -q
git -C "$MEMORY_DIR" branch -M main
git -C "$MEMORY_DIR" config user.name test
git -C "$MEMORY_DIR" config user.email test@example.invalid
git -C "$MEMORY_DIR" config commit.gpgSign false
printf '# Index\nINDEX_SENTINEL\n' >"$MEMORY_DIR/MEMORY.md"
printf '# Core\nCORE_SENTINEL\n' >"$MEMORY_DIR/CORE.md"
printf '# Project\nPROJECT_SENTINEL\n' \
  >"$MEMORY_DIR/projects/github.com-shishi-dotfiles.md"
git -C "$MEMORY_DIR" add MEMORY.md CORE.md projects/github.com-shishi-dotfiles.md
git -C "$MEMORY_DIR" commit -qm init

git -C "$PROJECT_DIR" init -q
git -C "$PROJECT_DIR" remote add origin git@github.com:shishi/dotfiles.git
payload="$(printf '{\"cwd\":\"%s\"}' "$PROJECT_DIR")"
output="$(printf '%s' "$payload" | bash "$HOOK" "$MEMORY_DIR")"
if printf '%s' "$output" | grep -q '<personal-memory>' \
  && printf '%s' "$output" | grep -q INDEX_SENTINEL \
  && printf '%s' "$output" | grep -q CORE_SENTINEL \
  && printf '%s' "$output" | grep -q PROJECT_SENTINEL; then
  ok "healthy main snapshot injects index, core, and selected project memory"
else
  ng "healthy main snapshot injects index, core, and selected project memory"
fi

draft_value="UNCOMMITTED_DRAFT_SENTINEL"
printf '\n%s\n' "$draft_value" >>"$MEMORY_DIR/MEMORY.md"
output="$(printf '%s' "$payload" | bash "$HOOK" "$MEMORY_DIR")"
if printf '%s' "$output" | grep -q INDEX_SENTINEL \
  && ! printf '%s' "$output" | grep -qF "$draft_value"; then
  ok "dirty worktree injects the committed snapshot, not the draft"
else
  ng "dirty worktree injects the committed snapshot, not the draft"
fi
git -C "$MEMORY_DIR" restore MEMORY.md

secret_value="dummy-credential-value"
printf 'password = %s\n' "$secret_value" >"$MEMORY_DIR/MEMORY.md"
git -C "$MEMORY_DIR" add MEMORY.md
git -C "$MEMORY_DIR" commit -qm secret-fixture
output="$(printf '%s' "$payload" | bash "$HOOK" "$MEMORY_DIR")"
if printf '%s' "$output" | grep -q '<personal-memory-warning>' \
  && ! printf '%s' "$output" | grep -qF "$secret_value" \
  && ! printf '%s' "$output" | grep -q CORE_SENTINEL; then
  ok "secret candidate withholds its value and the whole memory payload"
else
  ng "secret candidate withholds its value and the whole memory payload"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
