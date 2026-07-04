# パーソナル永続記憶システム 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** プライベートリポジトリに置いた個人記憶を SessionStart hook で全セッションに注入し、書き込み・同期・整理の運用ルールまで揃える。

**Architecture:** 記憶本体は private repo `shishi/claude-memory`(clone: `~/dev/claude-memory`)に置き、gitignore された symlink `claude/memory` 経由で `~/.claude/memory` として参照する。SessionStart hook(bash)がグローバル索引+現プロジェクト記憶を注入し、slug は remote URL → ghq root 相対 → path の優先順で解決する。

**Tech Stack:** bash(Git Bash / MSYS)、jq、git、gh CLI、Claude Code hooks / skills / settings.json

**Spec:** `docs/superpowers/specs/2026-07-05-personal-memory-system-design.md`

## Global Constraints

- dotfiles は **public**。個人情報を含むファイルを dotfiles に追跡させない。`claude/memory` symlink を `.gitignore` のホワイトリストへ**追加しない**。
- hook はあらゆる失敗(memory 不在・jq 不在・JSON 不正)で **無出力・exit 0**(セッション起動を阻害しない)。
- Windows の jq / git 出力は `tr -d '\r'` で CR 除去する(コミット 937ef4a と同種の問題対策)。
- slug 優先順: ① origin remote URL 正規化 → ② ghq root 相対パス → ③ path-slug。正規化は ssh/https/scp 形式と `.git` 有無を吸収する。
- 記憶リポジトリのデフォルトブランチは **`main`**(`claude/hooks/git-push-guard.sh` が `master` への push をリポジトリ問わず deny するため)。
- 索引 `MEMORY.md` は 1 記憶 1 行・200 行未満。
- 日常の記憶書き込みは即 commit(`chore(memory): <topic>`)+ push。consolidation のみ別 commit・push せずユーザーレビュー待ち。
- dotfiles 側の commit は Conventional Commits(WHY を body に書く)。

---

### Task 1: claude-memory プライベートリポジトリと symlink

**Files:**
- Create: `~/dev/claude-memory/MEMORY.md`(dotfiles 外・private repo)
- Create: `~/dev/claude-memory/projects/.gitkeep`
- Create: symlink `~/dev/dotfiles/claude/memory` → `~/dev/claude-memory`(**git 追跡しない**)

**Interfaces:**
- Produces: `~/.claude/memory/MEMORY.md` と `~/.claude/memory/projects/` が存在する(Task 2 のhookと Task 4 の運用ルールが参照する固定パス)

- [ ] **Step 1: gh 認証確認**

Run: `gh auth status`
Expected: `Logged in to github.com account shishi` を含む(失敗したらユーザーに `gh auth login` を依頼して停止)

- [ ] **Step 2: private repo 作成と clone(デフォルトブランチ main)**

```bash
gh repo create shishi/claude-memory --private --description "Claude Code personal persistent memory" 2>&1
git init -b main ~/dev/claude-memory
git -C ~/dev/claude-memory remote add origin git@github.com:shishi/claude-memory.git
```

既に repo が存在する場合(`Name already exists`)は `gh repo clone shishi/claude-memory ~/dev/claude-memory` に切り替える。

- [ ] **Step 3: 初期ファイル作成**

`~/dev/claude-memory/MEMORY.md`:

```markdown
# Memory Index

<!-- 1 記憶 1 行: - [Title](file.md) — 想起フック。200 行未満を保つ -->
```

```bash
mkdir -p ~/dev/claude-memory/projects
touch ~/dev/claude-memory/projects/.gitkeep
```

- [ ] **Step 4: 初期 commit と push**

```bash
git -C ~/dev/claude-memory add -A
git -C ~/dev/claude-memory commit -m "chore(memory): initialize memory store"
git -C ~/dev/claude-memory push -u origin main
```

Expected: push 成功(`main -> main`)

- [ ] **Step 5: symlink 作成(Windows は native symlink を強制)**

```bash
MSYS=winsymlinks:nativestrict ln -sfn ~/dev/claude-memory ~/dev/dotfiles/claude/memory
ls -la ~/dev/dotfiles/claude | grep memory
```

Expected: `memory -> /c/Users/shishi/dev/claude-memory` のような symlink 表示(`->` が無い=コピーされた場合は削除して `cmd //c "mklink /J ..."` の junction で代替)

- [ ] **Step 6: gitignore で非追跡なことを確認**

```bash
git -C ~/dev/dotfiles check-ignore claude/memory && echo IGNORED
cat ~/.claude/memory/MEMORY.md
```

Expected: `IGNORED` が出る(= public repo に乗らない)、かつ `~/.claude/memory` 経由で索引が読める

---

### Task 2: SessionStart hook `inject-memory.sh`(TDD)

**Files:**
- Create: `claude/hooks/inject-memory.sh`
- Create: `claude/hooks/inject-memory.test.sh`
- Modify: `.gitignore`(`!/claude/hooks/` ホワイトリスト追加 — 既存の追跡ファイルは ignore 対象外だが新規ファイルには必要)

**Interfaces:**
- Consumes: stdin の hook JSON(`{"cwd": "..."}`)、`~/.claude/memory/`(Task 1)
- Produces: stdout に `<personal-memory>` ブロック(索引全文+`現在のプロジェクト slug: <slug>` 行+プロジェクト記憶があればその全文)。Task 3 が settings.json に登録し、Task 4 の CLAUDE.md ルールが「注入ヘッダの slug を使え」と参照する

- [ ] **Step 1: テストスクリプトを書く(サイクル1: 注入の基本動作)**

`claude/hooks/inject-memory.test.sh`:

```bash
#!/usr/bin/env bash
# inject-memory.sh の単体テスト。fake HOME を組み立てて hook を直接叩く。
set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/inject-memory.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

run_hook() { # $1=cwd
  printf '{"cwd":"%s"}' "$1" | HOME="$TMP/home" bash "$HOOK"
}
assert_contains() { # $1=desc $2=haystack $3=needle
  if printf '%s' "$2" | grep -qF -- "$3"; then PASS=$((PASS+1)); echo "ok: $1"
  else FAIL=$((FAIL+1)); echo "NG: $1 (missing: $3)"; fi
}
assert_empty() { # $1=desc $2=output
  if [ -z "$2" ]; then PASS=$((PASS+1)); echo "ok: $1"
  else FAIL=$((FAIL+1)); echo "NG: $1 (expected empty output)"; fi
}

mkdir -p "$TMP/home"

# (c) memory ディレクトリ不在 -> 空出力・exit 0
out=$(run_hook "$TMP"); rc=$?
assert_empty "(c) no memory dir -> empty output" "$out"
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok: (c) exit 0"
else FAIL=$((FAIL+1)); echo "NG: (c) exit code $rc"; fi

# 記憶を用意
mkdir -p "$TMP/home/.claude/memory/projects"
printf '# Memory Index\n- [t](t.md) — INDEX-HOOK-LINE\n' > "$TMP/home/.claude/memory/MEMORY.md"

# (b) プロジェクト記憶なし -> 索引と slug 行のみ
out=$(run_hook "$TMP")
assert_contains "(b) index injected" "$out" "INDEX-HOOK-LINE"
assert_contains "(b) slug line present" "$out" "現在のプロジェクト slug:"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash ~/dev/dotfiles/claude/hooks/inject-memory.test.sh`
Expected: FAIL(`inject-memory.sh: No such file or directory` 由来の NG)

- [ ] **Step 3: hook を最小実装(索引注入+slug 行。slug はまず path-slug のみ)**

`claude/hooks/inject-memory.sh`:

```bash
#!/usr/bin/env bash
# SessionStart hook: 個人永続記憶(グローバル索引 + プロジェクト記憶)を注入する。
# どんな失敗でも無出力・exit 0 でセッション起動を阻害しない。
set -u

MEMORY_DIR="${HOME}/.claude/memory"
[ -f "${MEMORY_DIR}/MEMORY.md" ] || exit 0

input=$(cat 2>/dev/null || true)
cwd=""
if command -v jq >/dev/null 2>&1; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
fi
[ -n "$cwd" ] || cwd="$PWD"
if command -v cygpath >/dev/null 2>&1; then
  cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
fi

slugify() { printf '%s' "$1" | tr ':/\\' '-'; }
slug=$(slugify "$cwd")

echo "<personal-memory>"
echo "個人永続記憶。詳細は ~/.claude/memory/ 配下を必要時に Read で開くこと。"
echo "現在のプロジェクト slug: ${slug}(プロジェクト記憶: projects/${slug}.md)"
echo ""
cat "${MEMORY_DIR}/MEMORY.md"
project_file="${MEMORY_DIR}/projects/${slug}.md"
if [ -f "$project_file" ]; then
  echo ""
  echo "## プロジェクト記憶 (${slug})"
  cat "$project_file"
fi
echo "</personal-memory>"
exit 0
```

- [ ] **Step 4: テスト実行(サイクル1 green)**

Run: `bash ~/dev/dotfiles/claude/hooks/inject-memory.test.sh`
Expected: `PASS=4 FAIL=0`

- [ ] **Step 5: テスト追記(サイクル2: slug 解決の優先順)**

`inject-memory.test.sh` の `echo "---"` の**直前**に追記:

```bash
# (a)(d-1) origin あり -> remote slug
mkdir -p "$TMP/repo-ssh" && git -C "$TMP/repo-ssh" init -q -b main
git -C "$TMP/repo-ssh" remote add origin git@github.com:shishi/dotfiles.git
printf 'REMOTE-SLUG-MEMORY\n' > "$TMP/home/.claude/memory/projects/github.com-shishi-dotfiles.md"
out=$(run_hook "$TMP/repo-ssh")
assert_contains "(a)(d) remote slug from ssh origin" "$out" "REMOTE-SLUG-MEMORY"

# (e) https 形式でも同一 slug
mkdir -p "$TMP/repo-https" && git -C "$TMP/repo-https" init -q -b main
git -C "$TMP/repo-https" remote add origin https://github.com/shishi/dotfiles
out=$(run_hook "$TMP/repo-https")
assert_contains "(e) https origin -> same slug" "$out" "REMOTE-SLUG-MEMORY"

# (d-2)(f) remote なし + ghq root 配下 -> ghq 相対 slug = remote slug
HOME="$TMP/home" git config --global ghq.root "$TMP/ghq"
mkdir -p "$TMP/ghq/github.com/shishi/dotfiles"
git -C "$TMP/ghq/github.com/shishi/dotfiles" init -q -b main
out=$(run_hook "$TMP/ghq/github.com/shishi/dotfiles")
assert_contains "(d)(f) ghq-relative slug matches remote slug" "$out" "REMOTE-SLUG-MEMORY"

# (d-3) remote も ghq も無し -> path-slug
mkdir -p "$TMP/plain"
pslug=$(printf '%s' "$TMP/plain" | tr ':/\\' '-')
printf 'PATH-SLUG-MEMORY\n' > "$TMP/home/.claude/memory/projects/${pslug}.md"
out=$(run_hook "$TMP/plain")
assert_contains "(d) path-slug fallback" "$out" "PATH-SLUG-MEMORY"
```

- [ ] **Step 6: テスト実行(サイクル2 red)**

Run: `bash ~/dev/dotfiles/claude/hooks/inject-memory.test.sh`
Expected: remote/ghq 系 3 件が NG(まだ path-slug しか無い)、`FAIL=3`

- [ ] **Step 7: slug 解決を実装**

`inject-memory.sh` の `slugify() ...` と `slug=$(slugify "$cwd")` の 2 行を以下へ置換:

```bash
slugify() { printf '%s' "$1" | tr ':/\\' '-'; }

normalize_remote() {
  # ssh/https/scp 形式を host/owner/repo へ正規化(.git / user@ / scheme を除去)
  local url="$1"
  url="${url%.git}"
  url="${url#ssh://}"
  url="${url#git+ssh://}"
  url="${url#git://}"
  url="${url#https://}"
  url="${url#http://}"
  url="${url#*@}"
  url="${url//:/\/}"
  printf '%s' "$url"
}

slug=""
origin=$(git -C "$cwd" remote get-url origin 2>/dev/null | tr -d '\r' || true)
if [ -n "$origin" ]; then
  slug=$(slugify "$(normalize_remote "$origin")")
fi

if [ -z "$slug" ]; then
  ghq_root=$({ ghq root 2>/dev/null || git config --get ghq.root 2>/dev/null; } | head -1 | tr -d '\r')
  ghq_root="${ghq_root/#\~/$HOME}"
  [ -n "$ghq_root" ] || ghq_root="$HOME/ghq"
  case "$cwd" in
    "$ghq_root"/*) slug=$(slugify "${cwd#"$ghq_root"/}") ;;
  esac
fi

[ -n "$slug" ] || slug=$(slugify "$cwd")
```

- [ ] **Step 8: テスト実行(サイクル2 green)**

Run: `bash ~/dev/dotfiles/claude/hooks/inject-memory.test.sh`
Expected: `PASS=8 FAIL=0`

- [ ] **Step 9: .gitignore にホワイトリスト追加**

`.gitignore` の `!/claude/skills/**` の行の直後に追加:

```gitignore
!/claude/hooks/
!/claude/hooks/**
```

確認: `git -C ~/dev/dotfiles status --short` に `claude/hooks/inject-memory.sh` と `.test.sh` が `??` で現れ、`claude/memory` が**現れない**こと。

- [ ] **Step 10: Commit**

```bash
git add .gitignore claude/hooks/inject-memory.sh claude/hooks/inject-memory.test.sh
git commit -m "feat(claude): add personal memory SessionStart hook" -m "Inject the private memory index and per-project memory into every
session. Project identity is resolved remote URL -> ghq-root-relative
-> path so memories stay unified across machines and survive the
pre-push period of new repos. Fails silent (exit 0) so a broken or
absent memory store never blocks session startup."
```

---

### Task 3: settings.json 登録(hook + permissions)

**Files:**
- Modify: `claude/settings.json`(`hooks` と `permissions.allow`)

**Interfaces:**
- Consumes: `claude/hooks/inject-memory.sh`(Task 2)
- Produces: 全セッションで hook が走る。`git -C ~/.claude/memory ...` が許可されて auto-commit/push が無プロンプトで通る(Task 4 のルールが依存)

- [ ] **Step 1: hooks に SessionStart を追加**

`claude/settings.json` の `"hooks": {` ブロック内、`"PreToolUse"` の後に追加:

```json
"SessionStart": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "bash ~/.claude/hooks/inject-memory.sh",
        "timeout": 10,
        "statusMessage": "個人記憶を注入中..."
      }
    ]
  }
]
```

- [ ] **Step 2: permissions.allow に記憶リポジトリの git 操作を追加**

`"Bash(git push --set-upstream origin develop/*)"` の行の後に追加:

```json
"Bash(git -C ~/.claude/memory:*)"
```

- [ ] **Step 3: JSON 妥当性と push ガード通過を確認**

```bash
jq . ~/dev/dotfiles/claude/settings.json > /dev/null && echo JSON-OK
printf '{"tool_input":{"command":"git -C ~/.claude/memory push origin main"}}' \
  | bash ~/dev/dotfiles/claude/hooks/git-push-guard.sh; echo "guard exit: $?"
```

Expected: `JSON-OK`、guard は deny 出力なしで `guard exit: 0`(main への push は master ガードに掛からない)

- [ ] **Step 4: Commit**

```bash
git add claude/settings.json
git commit -m "feat(claude): register memory hook and allow memory-repo git ops" -m "SessionStart runs inject-memory.sh so memories load deterministically
instead of relying on the model to read files. The -C-scoped git
allowlist keeps memory auto-commit/push friction-free without widening
permissions for any other repository."
```

---

### Task 4: CLAUDE.md へ書き込みルール追記

**Files:**
- Modify: `claude/CLAUDE.md`(末尾に節を追加)

**Interfaces:**
- Consumes: hook の注入ヘッダ(`現在のプロジェクト slug: ...`、Task 2)、permissions(Task 3)
- Produces: 全セッションが従う記憶の読み書き規約。`memory-consolidate` skill 名(Task 5)を参照する

- [ ] **Step 1: CLAUDE.md 末尾に以下の節を追加**

```markdown
# 個人永続記憶 (personal memory)

記憶は `~/.claude/memory/`(private repo の symlink)に置く。ビルトインのプロジェクト記憶(`~/.claude/projects/<slug>/memory/`)は使わない。セッション開始時に索引(MEMORY.md)と現プロジェクトの記憶が `<personal-memory>` ブロックとして自動注入される。詳細が要るときだけ該当ファイルを Read で開く。

- 保存する: ユーザーの好み、訂正されたやり方(理由つき)、コードや git 履歴から導けない確定方針・制約、外部リソースのポインタ。「覚えて」と言われたときも、会話中に自発的に気づいたときも書く。
- 保存しない: リポジトリが既に記録していること、一回限りのデバッグメモ、経緯・失敗談そのもの(行動を変える技術的因果だけ知見として残す)。
- 形式: 1 ファイル 1 トピック。frontmatter に `name`(kebab-case)/`description`(1 行要約)/`type`(user | feedback | project | reference)。既存トピックがあれば新規作成せず更新する。相対日付は絶対日付に変換する。
- プロジェクト記憶は `projects/<slug>.md`(slug は注入ブロックのヘッダに書かれている値を使う)。
- 書き込み後は索引 `MEMORY.md` を同期し(1 記憶 1 行・200 行未満)、`git -C ~/.claude/memory` で add / commit(`chore(memory): <topic>`)/ `push origin main` まで即実行する。この commit は codex-review ゲートの対象外。
- 整理(consolidation)は memory-consolidate skill に従う。整理は日常追記と別 commit にし、push せずユーザーレビュー待ちにする。
```

- [ ] **Step 2: Commit**

```bash
git add claude/CLAUDE.md
git commit -m "docs(claude): add personal memory read/write rules" -m "Hooks make loading deterministic but writing is model behavior, so
the contract (what to save, format, index sync, auto-commit+push,
consolidation review gate) lives in CLAUDE.md where every session
sees it. Built-in project memory is retired to avoid split brains."
```

---

### Task 5: memory-consolidate skill

**Files:**
- Create: `claude/skills/memory-consolidate/SKILL.md`

**Interfaces:**
- Consumes: `~/.claude/memory/` のレイアウト(Task 1)、CLAUDE.md の記憶規約(Task 4)
- Produces: 「記憶の整理」「dream」で発動する consolidation 手順

- [ ] **Step 1: SKILL.md を作成**

```markdown
---
name: memory-consolidate
description: Use when the user says 「記憶の整理」「dream」, after large refactors that invalidate stored knowledge, or roughly every 20-30 sessions when memory files accumulate duplicates, contradictions, or stale references.
---

# memory-consolidate(個人記憶の整理)

`~/.claude/memory/`(private repo)の記憶を再編し、重複・矛盾・陳腐化を除去する。

## 前提

- 対象: `MEMORY.md`(索引)、`*.md`(グローバル記憶)、`projects/*.md`(プロジェクト記憶)
- 整理は日常追記と**別 commit**。**push しない**(ユーザーレビュー後に push)。LLM による書き換えは hallucination 混入リスクがあるため、diff レビューが安全弁。

## 4 フェーズ手順

1. **Mine**: 直近セッションで繰り返し出た指摘・確定した方針・新事実を洗い出す。一回限りのデバッグメモは拾わない。
2. **Consolidate**: 既存記憶へマージ。相対日付(「昨日」等)を絶対日付へ変換。矛盾は最新値で解決し古い記述を置換。判断がつかない矛盾はユーザーへ確認。
3. **Dedup**: 各情報の定義箇所を一つに保つ。CLAUDE.md が定めるルールを記憶側に再掲しない(黙って消す)。存在しないファイル/関数/フラグへの参照は現存確認のうえ除去または更新。
4. **Prune & Index**: 価値の無くなった記憶ファイルを削除し、`MEMORY.md` を実ファイル一覧と同期する(1 記憶 1 行・200 行未満)。

## 成果ファイルの書き方

- 残すのは「現行で正しい知見・ルール・再現手順」だけ。
- 経緯・履歴(失敗談、指摘された回数、学習日、セッション ID)や「重複させない」等のメタ注記は書かない。
- 行動を変える技術的因果(「A だと B が壊れるので C する」)は知見として残してよい。

## チェックリスト

- [ ] 相対日付をすべて絶対日付へ変換した
- [ ] CLAUDE.md のルールを記憶側から削った
- [ ] 矛盾を最新値で解決した(曖昧ならユーザー確認)
- [ ] 存在しないファイル/シンボルへの参照を除去 or 現存確認した
- [ ] 索引が実ファイルと一致し、1 記憶 1 行・200 行未満
- [ ] 変更を論理単位ごとに commit した(`chore(memory): consolidate ...`)
- [ ] **push していない**(ユーザーレビュー待ちと明言した)
```

- [ ] **Step 2: skill として認識されることを確認**

Run: `ls ~/.claude/skills/memory-consolidate/SKILL.md && head -4 ~/.claude/skills/memory-consolidate/SKILL.md`
Expected: frontmatter が表示される(新セッションで skill 一覧に `memory-consolidate` が載ることを Task 7 で最終確認)

- [ ] **Step 3: Commit**

```bash
git add claude/skills/memory-consolidate/SKILL.md
git commit -m "feat(claude): add memory-consolidate skill" -m "Appended memories accumulate duplicates, contradictions and stale
references after ~20-30 sessions and turn from recall aid into noise.
Codify the 4-phase consolidation (mine/consolidate/dedup/prune) with
a no-push review gate, since LLM rewrites can hallucinate."
```

---

### Task 6: setup.sh に clone/symlink 手順を追加

**Files:**
- Modify: `setup.sh`(claude symlink ブロックの直後、87 行目 `if [ -L ~/.codex ]` の前)

**Interfaces:**
- Consumes: private repo `shishi/claude-memory`(Task 1)
- Produces: 新マシンで `setup.sh` 実行時に `~/.claude/memory` が再現される

- [ ] **Step 1: setup.sh にブロック追加**

```bash
# claude-memory (個人永続記憶, private repo) を ~/.claude/memory として参照させる。
# symlink は dotfiles の .gitignore (claude/* デフォルト無視) により追跡されない。
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/dev/claude-memory}"
if [ -d "${CLAUDE_MEMORY_DIR}" ]; then
  if [ ! -e "${DOTDIR}/claude/memory" ] || [ -L "${DOTDIR}/claude/memory" ]; then
    MSYS=winsymlinks:nativestrict ln -sfn "${CLAUDE_MEMORY_DIR}" "${DOTDIR}/claude/memory" 2>/dev/null \
      || ln -sfn "${CLAUDE_MEMORY_DIR}" "${DOTDIR}/claude/memory"
  else
    echo "setup.sh: ${DOTDIR}/claude/memory exists as a directory; skip (manual setup required)"
  fi
else
  echo "setup.sh: ${CLAUDE_MEMORY_DIR} not found; clone first: gh repo clone shishi/claude-memory ${CLAUDE_MEMORY_DIR}"
fi
```

- [ ] **Step 2: 動作確認(冪等性)**

```bash
bash -n ~/dev/dotfiles/setup.sh && echo SYNTAX-OK
```

Expected: `SYNTAX-OK`。既に symlink がある状態で該当ブロックを手で実行しても同じ symlink が張り直されるだけで壊れない(`ln -sfn` の冪等性)。setup.sh 全体は他環境向け処理を含むためフル実行はしない。

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat(claude): wire claude-memory symlink into setup.sh" -m "New machines need the private memory repo linked before the
SessionStart hook can inject anything. Missing clone degrades to an
instruction message instead of an error so setup.sh stays runnable
on machines without the private repo."
```

---

### Task 7: 結合確認と初回記憶の書き込み

**Files:**
- Create: `~/dev/claude-memory/projects/github.com-shishi-dotfiles.md`(記憶リポジトリ側)
- Modify: `~/dev/claude-memory/MEMORY.md`

**Interfaces:**
- Consumes: Task 1〜6 のすべて

- [ ] **Step 1: hook を本物の入力で手動実行**

```bash
printf '{"cwd":"%s"}' "$HOME/dev/dotfiles" | bash ~/.claude/hooks/inject-memory.sh
```

Expected: `<personal-memory>` ブロック、`現在のプロジェクト slug: github.com-shishi-dotfiles`、索引ヘッダが出力される

- [ ] **Step 2: 初回のプロジェクト記憶を書く(運用ルールのリハーサル)**

`~/dev/claude-memory/projects/github.com-shishi-dotfiles.md`:

```markdown
---
name: dotfiles-memory-system
description: dotfiles は public。個人記憶は private repo claude-memory に置き、ビルトイン project memory は使わない
type: project
---

- dotfiles(github.com/shishi/dotfiles)は public リポジトリ。個人情報を含むファイルを追跡させない。
- 個人永続記憶システム(2026-07-05 導入): 本体 `~/dev/claude-memory`(private)、`~/.claude/memory` symlink 経由。設計は dotfiles の docs/superpowers/specs/2026-07-05-personal-memory-system-design.md。
- git-push-guard.sh が master への push をリポジトリ問わず deny するため、記憶リポジトリのデフォルトブランチは main。
```

`MEMORY.md` に索引行を追加:

```markdown
- [dotfiles memory system](projects/github.com-shishi-dotfiles.md) — public dotfiles に個人情報を置かない/記憶は private repo・main ブランチ
```

- [ ] **Step 3: 記憶リポジトリで commit + push(日常運用と同じコマンド)**

```bash
git -C ~/.claude/memory add -A
git -C ~/.claude/memory commit -m "chore(memory): dotfiles memory system"
git -C ~/.claude/memory push origin main
```

Expected: 成功。ここで permissions(Task 3)と push ガード(main)が実運用どおり通ることが確認できる

- [ ] **Step 4: 新セッションでの最終確認(ユーザー操作)**

shishi に依頼: 新しい Claude Code セッションを dotfiles で開き、(1) `<personal-memory>` が注入されているか、(2) skill 一覧に `memory-consolidate` が出るかを確認してもらう。ビルトイン記憶の旧ファイル(`claude/projects/C--Users-shishi-dev-dotfiles/memory/`)は移行不要(スコープ外)、混乱するなら手動削除を提案。

- [ ] **Step 5: 全テスト再実行**

Run: `bash ~/dev/dotfiles/claude/hooks/inject-memory.test.sh`
Expected: `PASS=8 FAIL=0`
