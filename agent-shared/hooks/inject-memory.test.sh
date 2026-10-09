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
printf '# Capture hardware\n映像の問題に対応する。\n無関係_SENTINEL\n' >"$MEMORY_DIR/capture.md"
git -C "$MEMORY_DIR" add MEMORY.md spectraldb.md capture.md
git -C "$MEMORY_DIR" commit -qm lookup-fixture
mkdir -p "$TMP/home"
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup '承認した。再開せよ')
if printf '%s' "$output" | jq -er '.hookSpecificOutput.additionalContext | select(contains("INDEX_SENTINEL") and startswith("[記憶検索]") and (contains("[作業継続]") | not))' | grep -q '0件一致、本文取得0件'; then
  ok "zero matches still inject the index without task policy"
else
  ng "zero matches still inject the index without task policy"
fi
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup '論点をそらさず、問題を増やさないルールを作る。コンテキストがすぐ圧縮されるので、対応を考える。')
if printf '%s' "$output" | jq -er '.hookSpecificOutput.additionalContext | contains("0件一致、本文取得0件") and (contains("無関係_SENTINEL") | not)' >/dev/null; then
  ok "generic problem and response words do not retrieve unrelated memory"
else
  ng "generic problem and response words do not retrieve unrelated memory"
fi
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"lookup-test",prompt:"SpectralDB の問題に対応するため設定を調べる",hook_event_name:"UserPromptSubmit"}')
# Windows Python の既定文字コードでも UTF-8 の hook JSON を読めることを含める。
lookup() { printf '%s' "$lookup_payload" | HOME="$TMP/home" PYTHONIOENCODING=cp932 bash "$HOOK" "$MEMORY_DIR" lookup; }
output=$(lookup)
if printf '%s' "$output" | jq -er '.hookSpecificOutput | select(.hookEventName=="UserPromptSubmit") | .additionalContext | select(contains("無関係_SENTINEL") | not)' | grep -q 検索取得_SENTINEL; then
  ok "user input searches and retrieves a committed memory without a model read"
else
  ng "user input searches and retrieves a committed memory without a model read"
fi
output=$(lookup)
if printf '%s' "$output" | jq -er '.hookSpecificOutput.additionalContext | select(contains("INDEX_SENTINEL") and startswith("[記憶検索]") and (contains("[作業継続]") | not))' | grep -q '既読' && ! printf '%s' "$output" | grep -q 検索取得_SENTINEL; then
  ok "index repeats even when already-read memory is omitted"
else
  ng "index repeats even when already-read memory is omitted"
fi

# Index-only vocabulary routes to the right document; incidental prose stays a candidate.
printf '\n- [記憶システム](context.md) — 索引と本文の読み込み\n' >>"$MEMORY_DIR/MEMORY.md"
printf '# Context support\nINDEX_ROUTE_BODY\n' >"$MEMORY_DIR/context.md"
printf '# Other project プロジェクト記憶\n## 削除\n記憶を整理し索引を確認した。\nINCIDENTAL_MEMORY_BODY\n' >"$MEMORY_DIR/other-project.md"
git -C "$MEMORY_DIR" add MEMORY.md context.md other-project.md
git -C "$MEMORY_DIR" commit -qm index-routing
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"index-routing",prompt:"記憶を整理して不要なものを削除し、索引をつける"}')
output=$(lookup)
if printf '%s' "$output" | jq -er '.hookSpecificOutput.additionalContext | contains("INDEX_ROUTE_BODY") and contains("other-project.md") and (contains("INCIDENTAL_MEMORY_BODY") | not)' >/dev/null; then
  ok "index cues retrieve relevant memory without injecting incidental body matches"
else
  ng "index cues retrieve relevant memory without injecting incidental body matches"
fi
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup '記憶を整理して索引をつける')
if printf '%s' "$output" | grep -q INCIDENTAL_MEMORY_BODY; then
  ok "explicit lookup can still retrieve body-only candidates"
else
  ng "explicit lookup can still retrieve body-only candidates"
fi
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"lookup-test",prompt:"SpectralDB の問題に対応するため設定を調べる",hook_event_name:"UserPromptSubmit"}')
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

# Meaningful approval queries retain the word that acknowledgement-only prompts omit.
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup '承認の手順')
if printf '%s' "$output" | grep -q 検索取得_SENTINEL; then
  ok "approval remains searchable in a substantive request"
else
  ng "approval remains searchable in a substantive request"
fi

# Fixed relevance set: a second lookup must not promote an incidental fourth hit.
for name in a b c; do
  printf '# LookupTarget\nPRIMARY_%s\n' "$name" >"$MEMORY_DIR/$name.md"
done
printf '# Other topic\nLookupTarget INCIDENTAL_FOURTH\n' >"$MEMORY_DIR/z.md"
git -C "$MEMORY_DIR" add a.md b.md c.md z.md
git -C "$MEMORY_DIR" commit -qm ranking-fixture
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"ranking",prompt:"LookupTarget"}')
output=$(lookup)
output=$(lookup)
if ! printf '%s' "$output" | grep -q INCIDENTAL_FOURTH && printf '%s' "$output" | grep -q '既読'; then
  ok "already read candidates do not refill slots with weaker matches"
else
  ng "already read candidates do not refill slots with weaker matches"
fi

printf '# LookupTarget\nCURRENT_PROJECT\n' >"$MEMORY_DIR/projects/github.com-shishi-dotfiles.md"
git -C "$MEMORY_DIR" add projects
git -C "$MEMORY_DIR" commit -qm project-ranking
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"project-ranking",prompt:"LookupTarget"}')
output=$(lookup)
if printf '%s' "$output" | grep -q CURRENT_PROJECT; then
  ok "current project ranks ahead of equivalent general matches"
else
  ng "current project ranks ahead of equivalent general matches"
fi

cat >"$MEMORY_DIR/sections.md" <<'EOF'
---
retrieval: sections
description: QuartzDB and AmberDB storage reference
---
# Storage reference
GLOBAL_CONDITION: only on the test platform.
## QuartzDB
QUARTZ_BODY
### Restore
RESTORE_CONDITION
## AmberDB
AMBER_BODY
EOF
git -C "$MEMORY_DIR" add sections.md
git -C "$MEMORY_DIR" commit -qm section-fixture
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"sections",prompt:"QuartzDB"}')
output=$(lookup)
if printf '%s' "$output" | grep -q QUARTZ_BODY && printf '%s' "$output" | grep -q GLOBAL_CONDITION \
  && printf '%s' "$output" | grep -q RESTORE_CONDITION && ! printf '%s' "$output" | grep -q AMBER_BODY; then
  ok "section lookup retains the preamble and complete nested conditions"
else
  ng "section lookup retains the preamble and complete nested conditions"
fi
sed 's/AMBER_BODY/AMBER_CHANGED/' "$MEMORY_DIR/sections.md" >"$TMP/sections"
cp "$TMP/sections" "$MEMORY_DIR/sections.md"
git -C "$MEMORY_DIR" add sections.md
git -C "$MEMORY_DIR" commit -qm unrelated-section-change
output=$(lookup)
if ! printf '%s' "$output" | grep -q QUARTZ_BODY; then
  ok "unrelated section updates do not repeat the read section"
else
  ng "unrelated section updates do not repeat the read section"
fi
lookup_payload=$(jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"sections",prompt:"AmberDB"}')
output=$(lookup)
if printf '%s' "$output" | grep -q AMBER_CHANGED && printf '%s' "$output" | grep -q GLOBAL_CONDITION; then
  ok "another section is still unread and includes shared conditions"
else
  ng "another section is still unread and includes shared conditions"
fi
printf '\npassword = %s\n' "$secret_value" >>"$MEMORY_DIR/sections.md"
git -C "$MEMORY_DIR" add sections.md
git -C "$MEMORY_DIR" commit -qm hidden-section-secret
lookup_status=0
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup QuartzDB 2>/dev/null) || lookup_status=$?
if [ "$lookup_status" -eq 2 ] && ! printf '%s' "$output" | grep -q QUARTZ_BODY; then
  ok "secret scan covers the whole source even outside selected sections"
else
  ng "secret scan covers the whole source even outside selected sections"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
