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

# 検索の fixture は秘密情報を含まない確定済み snapshot に戻す。
git -C "$MEMORY_DIR" show HEAD^:MEMORY.md >"$MEMORY_DIR/MEMORY.md"
printf '# SpectralDB\n検索取得_SENTINEL\n承認後に再開する。\n' >"$MEMORY_DIR/spectraldb.md"
git -C "$MEMORY_DIR" add MEMORY.md spectraldb.md
git -C "$MEMORY_DIR" commit -qm lookup-fixture
mkdir -p "$TMP/home"
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup '承認した。再開せよ')
if printf '%s' "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q '0件一致、本文取得0件'; then
  ok "approval and resume alone do not retrieve unrelated memory"
else
  ng "approval and resume alone do not retrieve unrelated memory"
fi
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"lookup-test",prompt:"SpectralDB の設定を調べる",hook_event_name:"UserPromptSubmit"}')
# Windows Python の既定文字コードでも UTF-8 の hook JSON を読めることを含める。
lookup() { printf '%s' "$lookup_payload" | HOME="$TMP/home" PYTHONIOENCODING=cp932 bash "$HOOK" "$MEMORY_DIR" lookup; }
output=$(lookup)
if printf '%s' "$output" | jq -er '.hookSpecificOutput | select(.hookEventName=="UserPromptSubmit") | .additionalContext' | grep -q 検索取得_SENTINEL; then
  ok "user input searches and retrieves a committed memory without a model read"
else
  ng "user input searches and retrieves a committed memory without a model read"
fi
output=$(lookup)
if printf '%s' "$output" | grep -q '既読' && ! printf '%s' "$output" | grep -q 検索取得_SENTINEL; then
  ok "the same memory version is not injected twice in one context"
else
  ng "the same memory version is not injected twice in one context"
fi
printf '# SpectralDB\n新規記憶_SENTINEL\n' >"$MEMORY_DIR/new-topic.md"
git -C "$MEMORY_DIR" add new-topic.md
git -C "$MEMORY_DIR" commit -qm new-memory
output=$(lookup)
if printf '%s' "$output" | grep -q 新規記憶_SENTINEL; then
  ok "newly committed memory is found without changing hook rules"
else
  ng "newly committed memory is found without changing hook rules"
fi
printf '%s' "$lookup_payload" | HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" >/dev/null
output=$(lookup)
if printf '%s' "$output" | grep -q 検索取得_SENTINEL; then
  ok "a new context resets retrieved-memory tracking"
else
  ng "a new context resets retrieved-memory tracking"
fi
printf '\npassword = %s\n' "$secret_value" >>"$MEMORY_DIR/new-topic.md"
git -C "$MEMORY_DIR" add new-topic.md
git -C "$MEMORY_DIR" commit -qm lookup-secret
lookup_status=0
output=$(lookup 2>/dev/null) || lookup_status=$?
if [ "$lookup_status" -eq 2 ] && ! printf '%s' "$output" | grep -qF "$secret_value"; then
  ok "lookup fails before task execution without emitting secret candidates"
else
  ng "lookup fails before task execution without emitting secret candidates"
fi
for config in claude/settings.json codex/hooks.json; do
  if jq -e '[.hooks.UserPromptSubmit[].hooks[] | select(.command | contains("inject-memory.sh") and endswith(" lookup"))] | length == 1' "$HOOK_DIR/../../$config" >/dev/null; then
    ok "$config performs lookup on every user input"
  else
    ng "$config performs lookup on every user input"
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
