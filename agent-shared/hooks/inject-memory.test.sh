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
automatic_output=$(printf '%s' "$lookup_payload" | jq '.session_id += "-automatic"' | HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup)
if printf '%s' "$automatic_output" | jq -e '.hookSpecificOutput.additionalContext | contains("spectraldb.md") and (contains("検索取得_SENTINEL") | not) and (contains("本文未取得") | not)' >/dev/null; then
  ok "automatic lookup offers candidates without injecting unselected bodies"
else
  ng "automatic lookup offers candidates without injecting unselected bodies"
fi
# Explicit retrieval still exercises delivery tracking, ranking, sections and scanning.
lookup() { printf '%s' "$lookup_payload" | jq '.memory_lookup_manual = true' | HOME="$TMP/home" PYTHONIOENCODING=cp932 bash "$HOOK" "$MEMORY_DIR" lookup; }
output=$(lookup)
if printf '%s' "$output" | jq -er '.hookSpecificOutput | select(.hookEventName=="UserPromptSubmit") | .additionalContext | select(contains("無関係_SENTINEL") | not)' | grep -q 検索取得_SENTINEL; then
  ok "an explicit query retrieves committed memory without unrelated body matches"
else
  ng "an explicit query retrieves committed memory without unrelated body matches"
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
output=$(printf '%s' "$lookup_payload" | HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup)
if printf '%s' "$output" | jq -er '.hookSpecificOutput.additionalContext | (split("\n") | map(select(startswith("語句検索の候補"))) | join("\n") | contains("context.md") and contains("other-project.md")) and (contains("INDEX_ROUTE_BODY") | not) and (contains("INCIDENTAL_MEMORY_BODY") | not)' >/dev/null; then
  ok "index cues expose candidates without committing to incidental body matches"
else
  ng "index cues expose candidates without committing to incidental body matches"
fi
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup '記憶を整理して索引をつける')
if printf '%s' "$output" | grep -q INCIDENTAL_MEMORY_BODY; then
  ok "explicit lookup can still retrieve body-only candidates"
else
  ng "explicit lookup can still retrieve body-only candidates"
fi
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup MEMORY.md)
if printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("INDEX_SENTINEL") and contains("<retrieved-memory path=\"MEMORY.md\">")' >/dev/null; then
  ok "an explicitly selected index is retrieved rather than silently excluded"
else
  ng "an explicitly selected index is retrieved rather than silently excluded"
fi
printf '# Memory conventions\nCONVENTIONS_BODY\n' >"$MEMORY_DIR/CONVENTIONS.md"
git -C "$MEMORY_DIR" add CONVENTIONS.md
git -C "$MEMORY_DIR" commit -qm conventions-fixture
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup CONVENTIONS.md)
if printf '%s' "$output" | grep -q CONVENTIONS_BODY; then
  ok "an explicitly selected protocol is retrieved in full"
else
  ng "an explicitly selected protocol is retrieved in full"
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
output=$(lookup)
printf '%s' "$lookup_payload" | HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" project >/dev/null
output=$(lookup)
if printf '%s' "$output" | grep -q 検索取得_SENTINEL; then
  ok "Claude's project startup hook resets retrieved-memory tracking"
else
  ng "Claude's project startup hook resets retrieved-memory tracking"
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

# lookup は事前に repo の状態を確かめない。main を読めなければ git のエラーを示して止まる。
NO_MAIN_DIR="$TMP/no-main-memory"
git init -q -b other "$NO_MAIN_DIR"
printf '# Index\n' >"$NO_MAIN_DIR/MEMORY.md"
git -C "$NO_MAIN_DIR" add MEMORY.md
git -C "$NO_MAIN_DIR" -c user.name=test -c user.email=test@example.invalid -c commit.gpgSign=false commit -qm init
lookup_status=0
lookup_error=$(HOME="$TMP/home" bash "$HOOK" "$NO_MAIN_DIR" lookup MEMORY.md 2>&1 >/dev/null) || lookup_status=$?
if [ "$lookup_status" -eq 2 ] && printf '%s' "$lookup_error" | grep -q 'fatal:'; then
  ok "lookup reports the git error when the main commit cannot be read"
else
  ng "lookup reports the git error when the main commit cannot be read"
fi
lookup_status=0
lookup_error=$(HOME="$TMP/home" bash "$HOOK" "$TMP/missing-memory" lookup MEMORY.md 2>&1 >/dev/null) || lookup_status=$?
if [ "$lookup_status" -eq 2 ] && printf '%s' "$lookup_error" | grep -q 'fatal:'; then
  ok "lookup reports the git error when the memory directory is missing"
else
  ng "lookup reports the git error when the memory directory is missing"
fi
SECRET_INDEX_DIR="$TMP/secret-index-memory"
git init -q -b main "$SECRET_INDEX_DIR"
printf '# Index\npassword = %s\n' "$secret_value" >"$SECRET_INDEX_DIR/MEMORY.md"
git -C "$SECRET_INDEX_DIR" add MEMORY.md
git -C "$SECRET_INDEX_DIR" -c user.name=test -c user.email=test@example.invalid -c commit.gpgSign=false commit -qm init
lookup_status=0
output=$(printf '%s' '{"prompt":"index"}' | HOME="$TMP/home" bash "$HOOK" "$SECRET_INDEX_DIR" lookup 2>/dev/null) || lookup_status=$?
if [ "$lookup_status" -eq 2 ] && ! printf '%s' "$output" | grep -qF "$secret_value"; then
  ok "lookup does not emit an index with secret candidates"
else
  ng "lookup does not emit an index with secret candidates"
fi

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
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup sections.md)
if printf '%s' "$output" | grep -q QUARTZ_BODY && printf '%s' "$output" | grep -q AMBER_CHANGED \
  && ! printf '%s' "$output" | grep -q '<personal-memory-index>'; then
  ok "an exact path retrieves the complete source without repeating the index"
else
  ng "an exact path retrieves the complete source without repeating the index"
fi
output=$(HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" lookup context.md z.md)
if printf '%s' "$output" | grep -q INDEX_ROUTE_BODY && printf '%s' "$output" | grep -q INCIDENTAL_FOURTH \
  && ! printf '%s' "$output" | grep -q '<personal-memory-index>'; then
  ok "several exact paths are retrieved in one lookup"
else
  ng "several exact paths are retrieved in one lookup"
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

# Claude は hook 出力 1 つあたり 10,000 文字を超えると先頭だけのプレビューに置き換えるため、
# 起動時の CORE とプロジェクト記憶を別の hook 出力に分け、それぞれを全文で渡す。
chars() { printf '%s' "$1" | python3 -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8").encode("utf-16-le")) // 2)' | tr -d '\r'; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
make_memory_repo() { # $1=dir
  mkdir -p "$1/projects"
  git -C "$1" init -q -b main
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config commit.gpgSign false
}
large_body() { # $1=title $2=line prefix $3=tail sentinel
  printf '# %s\n' "$1"
  for i in $(seq 1 170); do
    printf -- '- %sの規則その%s。応答・設計・検証の手順を長めに書いた行です。\n' "$2" "$i"
  done
  printf '%s\n' "$3"
}
LARGE_DIR="$TMP/large-memory"
make_memory_repo "$LARGE_DIR"
large_body Index 索引 INDEX_TAIL_SENTINEL >"$LARGE_DIR/MEMORY.md"
large_body Core 全体方針 CORE_TAIL_SENTINEL >"$LARGE_DIR/CORE.md"
large_body Project プロジェクト PROJECT_TAIL_SENTINEL >"$LARGE_DIR/projects/github.com-shishi-dotfiles.md"
git -C "$LARGE_DIR" add -A
git -C "$LARGE_DIR" commit -qm large
core_body=$(git -C "$LARGE_DIR" show HEAD:CORE.md)
project_body=$(git -C "$LARGE_DIR" show HEAD:projects/github.com-shishi-dotfiles.md)
core_output=$(printf '%s' "$payload" | HOME="$TMP/home" bash "$HOOK" "$LARGE_DIR" core)
project_output=$(printf '%s' "$payload" | HOME="$TMP/home" bash "$HOOK" "$LARGE_DIR" project)
if [ "$(chars "$core_output")" -lt 10000 ] && contains "$core_output" "$core_body" \
  && ! contains "$core_output" PROJECT_TAIL_SENTINEL && ! contains "$core_output" INDEX_TAIL_SENTINEL; then
  ok "Claude core startup output carries the whole CORE within the hook limit"
else
  ng "Claude core startup output carries the whole CORE within the hook limit ($(chars "$core_output") chars)"
fi
if [ "$(chars "$project_output")" -lt 10000 ] && contains "$project_output" "$project_body" \
  && ! contains "$project_output" CORE_TAIL_SENTINEL && ! contains "$project_output" INDEX_TAIL_SENTINEL; then
  ok "Claude project startup output carries the whole project memory within the hook limit"
else
  ng "Claude project startup output carries the whole project memory within the hook limit ($(chars "$project_output") chars)"
fi

# 上限を超える文書はプレビューに切り詰めさせず、確定 commit から読む手順だけを渡す。
{ cat "$LARGE_DIR/CORE.md"; large_body More 追加方針 CORE_OVERFLOW_SENTINEL; } >"$TMP/core-overflow"
cp "$TMP/core-overflow" "$LARGE_DIR/CORE.md"
git -C "$LARGE_DIR" add CORE.md
git -C "$LARGE_DIR" commit -qm overflow
overflow_commit=$(git -C "$LARGE_DIR" rev-parse HEAD)
core_output=$(printf '%s' "$payload" | HOME="$TMP/home" bash "$HOOK" "$LARGE_DIR" core)
if [ "$(chars "$core_output")" -lt 10000 ] && ! contains "$core_output" CORE_TAIL_SENTINEL \
  && contains "$core_output" "show ${overflow_commit}:CORE.md"; then
  ok "an oversized startup document is replaced by a pinned read instruction"
else
  ng "an oversized startup document is replaced by a pinned read instruction ($(chars "$core_output") chars)"
fi

# 同期は CORE 側の hook だけが行い、並列に走るプロジェクト側は同期を待たずに読む旨を伝える。
SYNC_ORIGIN="$TMP/sync-origin.git"
SYNC_SEED="$TMP/sync-seed"
SYNC_CLONE="$TMP/sync-clone"
make_memory_repo "$SYNC_SEED"
printf '# Index\n' >"$SYNC_SEED/MEMORY.md"
printf '# Core\nSYNC_CORE\n' >"$SYNC_SEED/CORE.md"
git -C "$SYNC_SEED" add -A
git -C "$SYNC_SEED" commit -qm init
git init -q --bare -b main "$SYNC_ORIGIN"
git -C "$SYNC_SEED" push -q "$SYNC_ORIGIN" main
git clone -q "$SYNC_ORIGIN" "$SYNC_CLONE"
printf 'REMOTE_UPDATE\n' >>"$SYNC_SEED/CORE.md"
git -C "$SYNC_SEED" commit -qam remote-update
git -C "$SYNC_SEED" push -q "$SYNC_ORIGIN" main
head_before=$(git -C "$SYNC_CLONE" rev-parse HEAD)
output=$(printf '%s' "$payload" | HOME="$TMP/home" AGENT_MEMORY_DIR="$SYNC_CLONE" bash "$HOOK" "$SYNC_CLONE" project)
if [ "$(git -C "$SYNC_CLONE" rev-parse HEAD)" = "$head_before" ] && contains "$output" 同期を待たず; then
  ok "the project startup hook reads without syncing and says so"
else
  ng "the project startup hook reads without syncing and says so"
fi
output=$(printf '%s' "$payload" | HOME="$TMP/home" AGENT_MEMORY_DIR="$SYNC_CLONE" bash "$HOOK" "$SYNC_CLONE" core)
if [ "$(git -C "$SYNC_CLONE" rev-parse HEAD)" = "$(git -C "$SYNC_ORIGIN" rev-parse main)" ] \
  && contains "$output" REMOTE_UPDATE && contains "$output" 同期済み && ! contains "$output" 同期で更新; then
  ok "the core startup hook syncs before reading"
else
  ng "the core startup hook syncs before reading"
fi

# 起動時の既読記録は、その hook が本文を渡した文書だけにする。CORE を出す hook が
# 取り消されても、後の lookup で CORE を取得できなければならない。
manual_lookup() { # $1=memory dir $2=session $3=path
  jq -n --arg cwd "$PROJECT_DIR" --arg s "$2" --arg p "$3" '{cwd:$cwd,session_id:$s,prompt:$p,memory_lookup_manual:true}' \
    | HOME="$TMP/home" bash "$HOOK" "$1" lookup
}
jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"split-core"}' \
  | HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" project >/dev/null
if manual_lookup "$MEMORY_DIR" split-core CORE.md | grep -q CORE_SENTINEL; then
  ok "the project startup hook does not record CORE as delivered"
else
  ng "the project startup hook does not record CORE as delivered"
fi
# 2 つの hook は並列に走るので、どちらが先に終わっても両方の記録が残らなければならない。
for order in "project core" "core project"; do
  session="split-both-${order% *}-first"
  for startup in $order; do
    jq -n --arg cwd "$PROJECT_DIR" --arg s "$session" '{cwd:$cwd,session_id:$s}' \
      | HOME="$TMP/home" bash "$HOOK" "$MEMORY_DIR" "$startup" >/dev/null
  done
  core_lookup=$(manual_lookup "$MEMORY_DIR" "$session" CORE.md)
  project_lookup=$(manual_lookup "$MEMORY_DIR" "$session" projects/github.com-shishi-dotfiles.md)
  if ! printf '%s' "$core_lookup" | grep -q CORE_SENTINEL && printf '%s' "$core_lookup" | grep -q 既読の同一版 \
    && ! printf '%s' "$project_lookup" | grep -q CURRENT_PROJECT && printf '%s' "$project_lookup" | grep -q 既読の同一版; then
    ok "each startup hook records the document it delivered in full ($order)"
  else
    ng "each startup hook records the document it delivered in full ($order)"
  fi
done
# 起動後に CORE が更新されたら、新しい版を一度取得した後は起動時の古い記録で再送しない。
CORE_UPDATE_DIR="$TMP/core-update-memory"
make_memory_repo "$CORE_UPDATE_DIR"
printf '# Index\n' >"$CORE_UPDATE_DIR/MEMORY.md"
printf '# Core\nOLD_CORE\n' >"$CORE_UPDATE_DIR/CORE.md"
git -C "$CORE_UPDATE_DIR" add -A
git -C "$CORE_UPDATE_DIR" commit -qm old
jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"core-update"}' \
  | HOME="$TMP/home" bash "$HOOK" "$CORE_UPDATE_DIR" core >/dev/null
printf '# Core\nNEW_CORE\n' >"$CORE_UPDATE_DIR/CORE.md"
git -C "$CORE_UPDATE_DIR" commit -qam new
manual_lookup "$CORE_UPDATE_DIR" core-update CORE.md >/dev/null
if ! manual_lookup "$CORE_UPDATE_DIR" core-update CORE.md | grep -q NEW_CORE; then
  ok "a CORE retrieved after startup is not resent because of the startup record"
else
  ng "a CORE retrieved after startup is not resent because of the startup record"
fi
{ cat "$LARGE_DIR/projects/github.com-shishi-dotfiles.md"; large_body More 追加 PROJECT_OVERFLOW_SENTINEL; } >"$TMP/project-overflow"
cp "$TMP/project-overflow" "$LARGE_DIR/projects/github.com-shishi-dotfiles.md"
git -C "$LARGE_DIR" add projects/github.com-shishi-dotfiles.md
git -C "$LARGE_DIR" commit -qm project-overflow
jq -n --arg cwd "$PROJECT_DIR" '{cwd:$cwd,session_id:"split-large"}' \
  | HOME="$TMP/home" bash "$HOOK" "$LARGE_DIR" project >/dev/null
if manual_lookup "$LARGE_DIR" split-large projects/github.com-shishi-dotfiles.md | grep -q PROJECT_OVERFLOW_SENTINEL; then
  ok "an omitted project memory is not recorded as delivered"
else
  ng "an omitted project memory is not recorded as delivered"
fi

# 同期でプロジェクト記憶が変わったら、同期を待たずに読んだ側の版が古いことを CORE 側が伝える。
PROJECT_SEED="$TMP/project-seed"
PROJECT_ORIGIN="$TMP/project-origin.git"
PROJECT_CLONE="$TMP/project-clone"
make_memory_repo "$PROJECT_SEED"
printf '# Index\n' >"$PROJECT_SEED/MEMORY.md"
printf '# Core\n' >"$PROJECT_SEED/CORE.md"
printf '# Project\nOLD_PROJECT\n' >"$PROJECT_SEED/projects/github.com-shishi-dotfiles.md"
git -C "$PROJECT_SEED" add -A
git -C "$PROJECT_SEED" commit -qm init
git init -q --bare -b main "$PROJECT_ORIGIN"
git -C "$PROJECT_SEED" push -q "$PROJECT_ORIGIN" main
git clone -q "$PROJECT_ORIGIN" "$PROJECT_CLONE"
printf 'NEW_PROJECT\n' >>"$PROJECT_SEED/projects/github.com-shishi-dotfiles.md"
git -C "$PROJECT_SEED" commit -qam project-update
git -C "$PROJECT_SEED" push -q "$PROJECT_ORIGIN" main
output=$(printf '%s' "$payload" | HOME="$TMP/home" AGENT_MEMORY_DIR="$PROJECT_CLONE" bash "$HOOK" "$PROJECT_CLONE" core)
if contains "$output" "projects/github.com-shishi-dotfiles.md" && contains "$output" 同期で更新; then
  ok "the core startup hook reports a project memory changed by its sync"
else
  ng "the core startup hook reports a project memory changed by its sync"
fi

settings="$HOOK_DIR/../../claude/settings.json"
if jq -e '[.hooks.SessionStart[].hooks[] | .command | select(contains("inject-memory.sh"))] | sort == ["bash ~/.agent-shared/hooks/inject-memory.sh ~/.claude/memory core", "bash ~/.agent-shared/hooks/inject-memory.sh ~/.claude/memory project"]' "$settings" >/dev/null; then
  ok "claude/settings.json injects CORE and project memory from separate startup hooks"
else
  ng "claude/settings.json injects CORE and project memory from separate startup hooks"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
