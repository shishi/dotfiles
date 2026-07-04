# compact 対策 3点セット Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code の compact 前後で判断構造を保全し、context 上限前に手動 compact へ誘導する 3 コンポーネント(compact-prep skill / 復旧 hook / 80% 通知)を dotfiles に実装する。

**Architecture:** statusline が使用率 80% 超で warn marker を書き、UserPromptSubmit hook が one-shot で `/compact-prep` を提案。skill が `~/.claude/compact-state/<sid>.md` に判断構造を保存し、`SessionStart(matcher: compact)` hook が圧縮直後に再読指示を additionalContext で注入する。marker/state の詳細仕様は `docs/superpowers/specs/2026-07-05-compact-safety-design.md` を正とする。

**Tech Stack:** bash (Git Bash on Windows), jq, Claude Code hooks (SessionStart / UserPromptSubmit), Claude Code personal skill

## Global Constraints

- 全 hook は fail-open: いかなる場合も `exit 0`。
- **`jq -r` の出力は必ず `| tr -d '\r'` を通す**(この環境の jq は CRLF を出力する。spec 検証済みの事実 6)。
- state/marker ディレクトリは `STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"` で解決する。
- 通知閾値は 80(整数 %)。TTL 掃除は `-mtime +30`。fallback の分母は 200000。
- settings.json の hook コマンドはスラッシュ区切り `bash ~/.claude/hooks/<name>.sh`(バックスラッシュはサイレントに失敗する)。
- 全 writer はファイル書き込み前に `mkdir -p`(失敗しても exit 0)。
- テストは `bash tests/compact-safety.sh` で全ケース実行。終了コード 0 = 全 PASS。
- コミットは構造変更(chore)と挙動追加(feat)を分ける。

---

### Task 1: .gitignore で claude/hooks/ を track 対象にする

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Produces: `claude/hooks/` 配下の新規ファイルが `git add` 可能になる(Task 2, 3 が依存)

**背景:** `.gitignore` は `/claude/*` を無視して個別解除するホワイトリスト方式。既存の `claude/hooks/git-push-guard.sh` は過去に force-add されており、新規 hook は解除エントリが無いと ignore される。

- [ ] **Step 1: .gitignore に解除エントリを追加**

`.gitignore` の `!/claude/agents/**` の行の直後に以下 2 行を追加する:

```gitignore
!/claude/hooks/
!/claude/hooks/**
```

- [ ] **Step 2: 解除が効いていることを確認**

Run: `git check-ignore -v claude/hooks/new-file.sh; echo "rc=$?"`
Expected: 何もマッチせず `rc=1`(ignore されない)

- [ ] **Step 3: Commit(構造変更)**

```bash
git add .gitignore
git commit -m "chore(claude): track claude/hooks/ in whitelist gitignore" -m "compact 対策で hook スクリプトを追加するため。既存 git-push-guard.sh は force-add されており、今後は通常 add で揃う。"
```

---

### Task 2: reminder hook(80% 通知の注入側)+ テストハーネス

**Files:**
- Create: `claude/hooks/userpromptsubmit-compact-reminder.sh`
- Create: `tests/compact-safety.sh`

**Interfaces:**
- Consumes: statusline(Task 4)が書く warn marker `$STATE_DIR/warn/<sid>`(中身は使用率の整数)
- Produces: cooldown marker `$STATE_DIR/warned/<sid>`(Task 3 の recovery hook が削除する)/ テストハーネスの `begin`/`end`/`check`/`check_not` 関数(Task 3, 4 のテストが利用)

- [ ] **Step 1: テストハーネスと reminder hook の失敗するテストを書く**

`tests/compact-safety.sh` を以下の内容で作成する:

```bash
#!/usr/bin/env bash
# compact 対策 3点セットのスモークテスト。
# 使い方: bash tests/compact-safety.sh
# COMPACT_STATE_DIR を一時ディレクトリへ向けるので本番 ~/.claude/compact-state は触らない。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$REPO/claude/hooks"
STATUSLINE="$REPO/claude/statusline.sh"
FAILURES=0
CURRENT=""
TMP=""

begin() {
  CURRENT="$1"
  TMP="$(mktemp -d)"
  export COMPACT_STATE_DIR="$TMP/state"
}

end() {
  rm -rf "$TMP"
}

pass() { echo "  ok: ${CURRENT}: $1"; }
fail() { echo "  NG: ${CURRENT}: $1"; FAILURES=$((FAILURES + 1)); }

check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

check_not() { # 成功したら NG
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

# ファイル名への CR 混入検査(spec 検証済みの事実 6 の回帰テスト)
no_cr_filenames() {
  [ -z "$(find "$COMPACT_STATE_DIR" -name "$(printf '*\r*')" 2>/dev/null)" ]
}

echo "# reminder hook"

begin "reminder/warn なし"
OUT=$(printf '{"session_id":"sid-1"}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
end

begin "reminder/warn あり"
mkdir -p "$COMPACT_STATE_DIR/warn"
printf '83\n' > "$COMPACT_STATE_DIR/warn/sid-1"
OUT=$(printf '{"session_id":"sid-1"}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "additionalContext を含む" grep -q "additionalContext" <<<"$OUT"
check "使用率 83% を含む" grep -q "83%" <<<"$OUT"
check "compact-prep 提案を含む" grep -q "compact-prep" <<<"$OUT"
check "warn 消滅" test ! -f "$COMPACT_STATE_DIR/warn/sid-1"
check "warned 作成(CR なしの名前で)" test -f "$COMPACT_STATE_DIR/warned/sid-1"
check "CR 混入ファイル名なし" no_cr_filenames
end

begin "reminder/session_id なし"
OUT=$(printf '{}' | bash "$HOOKS/userpromptsubmit-compact-reminder.sh"); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
end

echo ""
echo "結果: FAILURES=$FAILURES"
exit "$FAILURES"
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash tests/compact-safety.sh`
Expected: hook ファイルが存在しないため複数の `NG:` が出て終了コード非 0

- [ ] **Step 3: reminder hook を実装**

`claude/hooks/userpromptsubmit-compact-reminder.sh` を以下の内容で作成する:

```bash
#!/bin/bash
# UserPromptSubmit hook: statusline が書いた compact-warn marker を検出し、
# additionalContext で compact-prep 実行を促す(one-shot)。
#
# フロー:
#   statusline.sh が使用率 >= 80 で warn marker 書込
#   → 本 hook が検出 → warned marker 作成(先) → warn marker 削除 → additionalContext 注入
#   → recovery hook が compact/clear/startup 時に warned marker 削除(cooldown リセット)
#
# warned を warn より先に作るのは、並行して走る statusline が
# 「warn なし・warned なし」の瞬間を見て warn を再作成する再通知レースを塞ぐため。
#
# overhead: marker なしターンは test -f 1 回で即 exit
# fail-open (常に exit 0)

set -uo pipefail

STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
[[ -z "$SESSION_ID" ]] && exit 0

WARN_MARKER="$STATE_DIR/warn/$SESSION_ID"
[[ -f "$WARN_MARKER" ]] || exit 0

mkdir -p "$STATE_DIR/warned" 2>/dev/null || true
printf '%s\n' "$(date +%s)" > "$STATE_DIR/warned/$SESSION_ID" 2>/dev/null || true

CTX_PCT=$(tr -d '\r\n' < "$WARN_MARKER" 2>/dev/null)
CTX_PCT=${CTX_PCT:-"?"}
rm -f "$WARN_MARKER" 2>/dev/null || true

CTX="[COMPACT PREP REMINDER] context 使用率が ${CTX_PCT}% に達した。"
CTX+=$'\n'"- 作業区切りでユーザーに \`/compact-prep\` の実行を提案せよ。"
CTX+=$'\n'"- \`/compact-prep\` 実行後、ユーザーに \`/compact\` 実行を案内せよ。"
CTX+=$'\n'"- scope 縮小や別セッション化ではなく、圧縮前 state 保存で対処せよ。"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash tests/compact-safety.sh`
Expected: `# reminder hook` の全ケース `ok:`、`FAILURES=0`、終了コード 0

- [ ] **Step 5: Commit(挙動追加)**

```bash
git add claude/hooks/userpromptsubmit-compact-reminder.sh tests/compact-safety.sh
git commit -m "feat(claude): add compact-prep reminder hook with smoke tests" -m "context 使用率が閾値を超えたら one-shot で /compact-prep を提案する。autoCompact 無効運用では上限到達前に手動 compact へ誘導する必要がある。warned marker を warn 削除より先に作り statusline との再通知レースを塞ぐ。jq の CRLF 対策として tr -d '\\r' を必須化(937ef4a と同根)。"
```

---

### Task 3: recovery hook(圧縮直後の復旧指示 + marker 掃除 + TTL)

**Files:**
- Create: `claude/hooks/session-start-compaction-recovery.sh`
- Modify: `tests/compact-safety.sh`(`echo "結果: ..."` の直前にテスト追加)

**Interfaces:**
- Consumes: Task 2 のテストハーネス関数 / compact-prep skill(Task 5)が書く state file `$STATE_DIR/<sid>.md` / Task 2 の warned marker
- Produces: 第 1 引数 `recover` | `cleanup` を受ける hook スクリプト(Task 6 の settings.json 登録が依存)

- [ ] **Step 1: 失敗するテストを追加**

`tests/compact-safety.sh` の `echo ""`(`echo "結果: ..."` の直前)の前に以下を挿入する:

```bash
echo "# recovery hook"

begin "recovery/cleanup は注入せず marker を消す"
mkdir -p "$COMPACT_STATE_DIR/warn" "$COMPACT_STATE_DIR/warned"
printf '1\n' > "$COMPACT_STATE_DIR/warn/sid-2"
printf '1\n' > "$COMPACT_STATE_DIR/warned/sid-2"
OUT=$(printf '{"session_id":"sid-2"}' | bash "$HOOKS/session-start-compaction-recovery.sh" cleanup); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
check "warn 消滅" test ! -f "$COMPACT_STATE_DIR/warn/sid-2"
check "warned 消滅" test ! -f "$COMPACT_STATE_DIR/warned/sid-2"
end

begin "recovery/recover state なし"
OUT=$(printf '{"session_id":"sid-3"}' | bash "$HOOKS/session-start-compaction-recovery.sh" recover); RC=$?
check "exit 0" test "$RC" -eq 0
check "SessionStart として注入" grep -q '"hookEventName": "SessionStart"' <<<"$OUT"
check "サマリー仮説扱い指示" grep -q "仮説" <<<"$OUT"
check_not "state file には言及しない" grep -q "state file" <<<"$OUT"
end

begin "recovery/recover state あり"
mkdir -p "$COMPACT_STATE_DIR"
printf '# Compact Prep State\nPrepared: 2026-07-05T00:00:00+09:00\n' > "$COMPACT_STATE_DIR/sid-4.md"
OUT=$(printf '{"session_id":"sid-4"}' | bash "$HOOKS/session-start-compaction-recovery.sh" recover)
check "state file パスに言及" grep -q "sid-4.md" <<<"$OUT"
check "Prepared 鮮度確認指示" grep -q "Prepared" <<<"$OUT"
end

begin "recovery/TTL 30日"
mkdir -p "$COMPACT_STATE_DIR"
printf 'old\n' > "$COMPACT_STATE_DIR/old-sid.md"
touch -m -d "35 days ago" "$COMPACT_STATE_DIR/old-sid.md"
printf 'new\n' > "$COMPACT_STATE_DIR/new-sid.md"
printf '{"session_id":"sid-5"}' | bash "$HOOKS/session-start-compaction-recovery.sh" cleanup >/dev/null
check "35日前のファイルは消える" test ! -f "$COMPACT_STATE_DIR/old-sid.md"
check "新しいファイルは残る" test -f "$COMPACT_STATE_DIR/new-sid.md"
end

begin "recovery/session_id なし"
OUT=$(printf '{}' | bash "$HOOKS/session-start-compaction-recovery.sh" recover); RC=$?
check "exit 0" test "$RC" -eq 0
check "無出力" test -z "$OUT"
end
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash tests/compact-safety.sh`
Expected: `# recovery hook` のケースが `NG:`(hook 未実装)、reminder は `ok:` のまま

- [ ] **Step 3: recovery hook を実装**

`claude/hooks/session-start-compaction-recovery.sh` を以下の内容で作成する:

```bash
#!/bin/bash
# SessionStart hook。第 1 引数で動作モードを受ける(stdin の source には依存しない):
#   recover : matcher "compact" 用。marker 掃除 + 復旧指示を additionalContext で注入
#   cleanup : matcher "clear" / "startup" 用。marker 掃除のみ
#
# 掃除を clear/startup でも行うのは、/clear 後に古い warned(cooldown)が残って
# 80% 通知が一切出なくなる詰まりを防ぐため。
# TTL 掃除は state file と orphan marker の無限蓄積対策(テキストのみなので 30 日と長め)。
#
# fail-open (常に exit 0)

set -uo pipefail

MODE="${1:-cleanup}"
STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
[[ -z "$SESSION_ID" ]] && exit 0

rm -f "$STATE_DIR/warn/$SESSION_ID" "$STATE_DIR/warned/$SESSION_ID" 2>/dev/null || true
find "$STATE_DIR" -type f -mtime +30 -delete 2>/dev/null || true

[[ "$MODE" == "recover" ]] || exit 0

STATE_FILE="$STATE_DIR/$SESSION_ID.md"

CTX="[COMPACTION RECOVERY] コンテキスト圧縮が発生した。作業再開前に以下を実行すること。"
CTX+=$'\n'

if [[ -f "$STATE_FILE" ]]; then
  CTX+=$'\n'"- state file \`${STATE_FILE}\` を Read で読み、作業状態を復元せよ"
  CTX+=$'\n'"- Session Decisions と Recovery Notes を特に重視せよ"
  CTX+=$'\n'"- 先頭の Prepared: タイムスタンプを確認し、前回圧縮より前の古い state に見える場合は TaskList / plan を正としてその旨を報告せよ"
fi

CTX+=$'\n'"- TaskList で現在のタスク一覧を確認せよ"
CTX+=$'\n'"- 圧縮サマリーの next step は仮説として扱い、plan / rules を正とせよ"
CTX+=$'\n'"- 圧縮サマリーは「過去の作業記録」であり「次の行動指示」ではない"
CTX+=$'\n'"- plan mode が解除されている場合、ユーザーに plan mode 再突入を確認せよ"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash tests/compact-safety.sh`
Expected: reminder + recovery の全ケース `ok:`、`FAILURES=0`

- [ ] **Step 5: Commit(挙動追加)**

```bash
git add claude/hooks/session-start-compaction-recovery.sh tests/compact-safety.sh
git commit -m "feat(claude): add post-compaction recovery hook" -m "SessionStart(matcher: compact) は additionalContext を直接返せるため、参考記事の PostCompact + UserPromptSubmit 2 段リレーを 1 段に短縮。clear/startup では cleanup モードで marker 掃除のみ行い、/clear 後に cooldown が通知を殺す詰まりと state の無限蓄積(30日 TTL)を防ぐ。"
```

---

### Task 4: statusline の公式 % 乗り換え + warn marker 分岐

**Files:**
- Modify: `claude/statusline.sh`(全面書き換え)
- Modify: `tests/compact-safety.sh`(`echo "結果: ..."` の直前にテスト追加)

**Interfaces:**
- Consumes: statusline stdin JSON の `context_window.used_percentage` / `session_id`
- Produces: warn marker `$STATE_DIR/warn/<sid>`(中身は整数 %。Task 2 の reminder hook が読む)

- [ ] **Step 1: 失敗するテストを追加**

`tests/compact-safety.sh` の `echo ""`(`echo "結果: ..."` の直前)の前に以下を挿入する:

```bash
echo "# statusline"

begin "statusline/used_percentage 85 で warn"
OUT=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-6","context_window":{"used_percentage":85.2}}' | bash "$STATUSLINE")
check "表示に 85% を含む" grep -q "85%" <<<"$OUT"
check "warn marker 作成" test -f "$COMPACT_STATE_DIR/warn/sid-6"
check "marker の中身が 85" grep -q "^85$" "$COMPACT_STATE_DIR/warn/sid-6"
check "CR 混入ファイル名なし" no_cr_filenames
end

begin "statusline/warned cooldown 中は warn を書かない"
mkdir -p "$COMPACT_STATE_DIR/warned"
printf '1\n' > "$COMPACT_STATE_DIR/warned/sid-7"
printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-7","context_window":{"used_percentage":90}}' | bash "$STATUSLINE" >/dev/null
check "warn を作らない" test ! -f "$COMPACT_STATE_DIR/warn/sid-7"
end

begin "statusline/50% は warn しない"
printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-8","context_window":{"used_percentage":50}}' | bash "$STATUSLINE" >/dev/null
check "warn を作らない" test ! -f "$COMPACT_STATE_DIR/warn/sid-8"
end

begin "statusline/fallback は分母 200000"
TRANSCRIPT="$TMP/transcript.jsonl"
printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":100000,"output_tokens":0,"cache_creation_input_tokens":30000,"cache_read_input_tokens":30000}}}' > "$TRANSCRIPT"
OUT=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/x"},"session_id":"sid-9","transcript_path":"'"$TRANSCRIPT"'"}' | bash "$STATUSLINE")
check "160K/200K = 80% を表示" grep -q "80%" <<<"$OUT"
check "80% なので warn marker 作成" test -f "$COMPACT_STATE_DIR/warn/sid-9"
end
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash tests/compact-safety.sh`
Expected: `# statusline` の warn marker 系ケースが `NG:`(現行 statusline は marker を書かない・分母 819200)。reminder / recovery は `ok:` のまま

- [ ] **Step 3: statusline.sh を書き換え**

`claude/statusline.sh` を以下の内容に置き換える(表示フォーマットは現行維持。変更点は「公式 % 優先」「fallback 分母 200000」「warn marker 分岐」「jq 出力の CR 除去」):

```bash
#!/usr/bin/env bash

# Read JSON input from stdin
input=$(cat)

MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name' | tr -d '\r')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir' | tr -d '\r')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // empty' | tr -d '\r')
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty' | tr -d '\r')
USED_PCT_RAW=$(echo "$input" | jq -r '.context_window.used_percentage // empty' | tr -d '\r')

# Get git branch information
GIT_BRANCH=""
if git rev-parse &>/dev/null; then
  BRANCH=$(git branch --show-current)
  if [ -n "$BRANCH" ]; then
    GIT_BRANCH=" |  $BRANCH"
  else
    COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$COMMIT_HASH" ]; then
      GIT_BRANCH=" |  HEAD ($COMMIT_HASH)"
    fi
  fi
fi

# 表示用 token 数は従来どおり transcript の直近 usage から取得
total_tokens=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  total_tokens=$(tail -n 100 "$TRANSCRIPT_PATH" 2>/dev/null |
    jq -s 'map(select(.type == "assistant" and .message.usage)) |
    last |
    .message.usage |
    (.input_tokens // 0) +
    (.output_tokens // 0) +
    (.cache_creation_input_tokens // 0) +
  (.cache_read_input_tokens // 0)' 2>/dev/null | tr -d '\r')
  total_tokens=${total_tokens:-0}
fi

# 使用率: 公式 context_window.used_percentage 優先。
# 取れない場合は transcript 合計 / 200K(context の実サイズ)で fallback。
# 旧実装の分母 819200(1M の 80%)は実使用率の約 1/5 に過小表示するため廃止。
percentage=""
if [ -n "$USED_PCT_RAW" ]; then
  percentage=${USED_PCT_RAW%.*}
elif [ "$total_tokens" -gt 0 ] 2>/dev/null; then
  CONTEXT_WINDOW_SIZE=200000
  percentage=$((total_tokens * 100 / CONTEXT_WINDOW_SIZE))
fi

if [ -z "$percentage" ]; then
  TOKEN_COUNT="_ tkns. (_%)"
else
  if [ "$total_tokens" -ge 1000 ]; then
    thousands=$(echo "scale=1; $total_tokens/1000" | bc)
    token_display=$(printf "%.1fK" "$thousands")
  elif [ "$total_tokens" -gt 0 ]; then
    token_display="$total_tokens"
  else
    token_display="_"
  fi

  # Color coding for percentage
  if [ "$percentage" -ge 90 ]; then
    color="\033[31m" # Red
  elif [ "$percentage" -ge 70 ]; then
    color="\033[33m" # Yellow
  else
    color="\033[32m" # Green
  fi

  TOKEN_COUNT=$(echo -e "${token_display} tkns. (${color}${percentage}%\033[0m)")

  # 閾値超過で compact-prep 警告 marker を書く(cooldown 中でなければ)。
  # warn は reminder hook が消費し、warned は recovery hook が消す。
  COMPACT_WARN_THRESHOLD=80
  STATE_DIR="${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}"
  if [ -n "$SESSION_ID" ] && [ "$percentage" -ge "$COMPACT_WARN_THRESHOLD" ] 2>/dev/null; then
    if [ ! -f "$STATE_DIR/warned/$SESSION_ID" ]; then
      mkdir -p "$STATE_DIR/warn" 2>/dev/null || true
      printf '%s\n' "$percentage" > "$STATE_DIR/warn/$SESSION_ID" 2>/dev/null || true
    fi
  fi
fi

echo "󰚩 ${MODEL_DISPLAY} |  ${CURRENT_DIR##*/}${GIT_BRANCH} |  ${TOKEN_COUNT}"
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash tests/compact-safety.sh`
Expected: 全セクション `ok:`、`FAILURES=0`、終了コード 0

- [ ] **Step 5: Commit(挙動変更)**

```bash
git add claude/statusline.sh tests/compact-safety.sh
git commit -m "feat(claude): statusline uses official used_percentage and writes warn marker" -m "旧実装は 1M context 前提の分母 819200 決め打ちで、200K 運用では実使用率の約 1/5 に過小表示されていた。公式 context_window.used_percentage を優先し、fallback は分母 200000 の実トークン比に修正。80% 超で warn marker を書き reminder hook に通知を引き継ぐ。"
```

---

### Task 5: compact-prep skill

**Files:**
- Create: `claude/skills/compact-prep/SKILL.md`

**Interfaces:**
- Consumes: Bash tool の環境変数 `CLAUDE_CODE_SESSION_ID`(spec 検証済みの事実 4)
- Produces: state file `~/.claude/compact-state/<session_id>.md`(Task 3 の recovery hook が `recover` モードで参照する。見出し構成は下記のとおり固定)

- [ ] **Step 1: SKILL.md を作成**

`claude/skills/compact-prep/SKILL.md` を以下の内容で作成する:

```markdown
---
name: compact-prep
description: |
  Claude Code の /compact 実行前に、現セッションの作業状態を state file へ保存する。
  MANDATORY TRIGGERS: /compact-prep, compact-prep, 圧縮準備, compact 準備, コンパクト準備, 圧縮前状態保存。
  DO NOT TRIGGER: compact 後の復旧、通常の進捗報告、plan 作成、context 使用率の雑談。
argument-hint: "[復旧メモ]"
allowed-tools: Read, Write, Bash(echo:*), Bash(date:*), Bash(mkdir:*)
---

# compact-prep

Claude Code の `/compact` 前に、圧縮サマリーへ残りにくい「判断構造」と
「セッション状態」を `~/.claude/compact-state/<session_id>.md` へ保存する。
圧縮要約は「過去の作業記録」になりがちで、却下理由・現在フェーズ・委譲状態が
落ちる。この state file が圧縮直後の復旧材料になる(SessionStart hook が参照する)。

## Strict procedure

- **Hard gate**: session_id が取得できない場合は state file を推測名で作らず、
  「session_id が取得できないため準備未完了」と報告して停止する。
- **Forcing function**: 保存後にファイルを Read で読み返し、必須見出しの有無を確認する。

## 手順

1. session_id を取得する。
   - `echo "$CLAUDE_CODE_SESSION_ID"` を実行する。
   - 空の場合は Hard gate に従い停止する。
2. `mkdir -p ~/.claude/compact-state` を実行し、
   保存先を `~/.claude/compact-state/<session_id>.md` に決める。
3. 現セッションを振り返り、保存内容を収集する。
   - TaskList の in-progress / pending タスクと補足
   - active plan(あれば plan ファイルのパスと現在フェーズ)
   - セッション中の判断: 採用した案、却下した案、**却下した理由**
   - 制約・ブロッカー・未完了の検証
   - 委譲中の作業(subagent、background task、agent team の担当と状態)
   - 編集中のファイルと未保存・未検証の注意点
4. `date -Iseconds` で現在時刻を取得し、次の構成で state file を Write する。
   見出しはこの順で固定。該当なしの項目は「なし」と書く(見出し自体は省略しない)。

   # Compact Prep State
   Prepared: <ISO 8601 タイムスタンプ>

   ## Active Plan
   ## Current Phase
   ## TaskList Summary
   ## Session Decisions
   ## Constraints and Blockers
   ## Delegated Work
   ## Editing Files
   ## Recovery Notes

   Recovery Notes は「圧縮後の自分への手紙」。ユーザーから引数で復旧メモが
   渡されていればここに含める。
5. 保存後に state file を Read で読み直し、上記見出しがすべて存在することを
   確認する。欠落があれば書き直して再確認する。
6. 完了レシートを報告する。
   - state file パス
   - 保存した主要項目
   - 未確認項目と理由
   - 「準備完了。`/compact` を実行してください。」
```

- [ ] **Step 2: 必須要素の存在を機械確認**

Run: `grep -c -e "CLAUDE_CODE_SESSION_ID" -e "Prepared:" -e "## Recovery Notes" -e "Hard gate" claude/skills/compact-prep/SKILL.md`
Expected: `4` 以上(4 要素すべてヒット)

Run: `bash tests/compact-safety.sh`
Expected: 引き続き `FAILURES=0`(回帰なし)

- [ ] **Step 3: Commit(挙動追加)**

```bash
git add claude/skills/compact-prep/SKILL.md
git commit -m "feat(claude): add compact-prep skill for pre-compaction state save" -m "圧縮要約に載りにくい判断構造(却下案と理由・フェーズ・委譲状態)を固定見出しの state file に保存する。session_id は CLAUDE_CODE_SESSION_ID から取得し、取れなければ推測名で作らない Hard gate を置く。Prepared タイムスタンプは復旧時の鮮度判定用。"
```

---

### Task 6: settings.json への hook 登録と実セッション通し確認

**Files:**
- Modify: `claude/settings.json`(`"hooks"` オブジェクト)

**Interfaces:**
- Consumes: Task 2 の reminder hook / Task 3 の recovery hook(`recover` / `cleanup` 引数)

- [ ] **Step 1: settings.json の hooks を更新**

`claude/settings.json` の `"hooks"` オブジェクト(現在は `"PreToolUse"` のみ)を以下に置き換える。既存の PreToolUse エントリは変更しない:

```json
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/git-push-guard.sh",
            "timeout": 10,
            "statusMessage": "git push ガード確認中..."
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start-compaction-recovery.sh recover",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "clear",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start-compaction-recovery.sh cleanup",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start-compaction-recovery.sh cleanup",
            "timeout": 10
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/userpromptsubmit-compact-reminder.sh",
            "timeout": 10
          }
        ]
      }
    ]
  },
```

- [ ] **Step 2: JSON 妥当性と登録内容を確認**

Run: `jq -e '.hooks | keys' claude/settings.json && jq -e '.hooks.SessionStart | length' claude/settings.json && jq -e '.hooks.UserPromptSubmit | length' claude/settings.json`
Expected: `["PreToolUse","SessionStart","UserPromptSubmit"]`、`3`、`1`

Run: `bash tests/compact-safety.sh`
Expected: `FAILURES=0`(回帰なし)

- [ ] **Step 3: Commit(挙動追加)**

```bash
git add claude/settings.json
git commit -m "feat(claude): register compact safety hooks in settings" -m "SessionStart は matcher 別に hook 引数で mode を渡し、stdin の source フィールドへの依存を避ける。compact=recover(復旧指示注入)、clear/startup=cleanup(marker 掃除のみ)。"
```

- [ ] **Step 4: 実セッション通し確認(手動。新しい Claude Code セッションで実施)**

このステップは自動化できない。実装者は以下をユーザーへの完了報告に含め、確認を依頼する:

1. 新しいセッションを起動 → statusline が従来どおり表示されること(壊れていれば `_ tkns. (_%)` 表示や無表示になる)
2. `/compact-prep` を実行 → `~/.claude/compact-state/<sid>.md` が生成され、`Prepared:` 行と全見出しがあること
3. `/compact` を実行 → 直後のターンで Claude が state file / TaskList の再確認に言及すること(recovery 注入が効いている証拠)
4. session_id が compact 前後で連続していること(spec の実装時検証項目。手順 2 のファイル名と compact 後に `echo "$CLAUDE_CODE_SESSION_ID"` の一致で確認)
5. (任意)長いセッションで 80% 超えたターンに `/compact-prep` 提案が出ること

手順 4 で session_id が**非連続**だった場合: recovery hook は state file を見つけられない。spec の「実装時に検証する項目」に従い、設計の見直し(compact 直前の sid を別 pointer file で引き継ぐ等)をユーザーと相談すること。

---

## 実行後の後片付け

- 全タスク完了後、spec(`docs/superpowers/specs/2026-07-05-compact-safety-design.md`)の
  「状態:」行を「実装済み」に更新して commit する。
