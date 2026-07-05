# Claude 設定重複・矛盾整理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** spec `docs/superpowers/specs/2026-07-05-claude-config-consolidation-design.md` に従い、CLAUDE.md・rules・skills・agents の重複と矛盾を解消する。

**Architecture:** すべて Markdown 設定ファイルの編集・削除。コードのユニットテストは無く、各タスクの検証は `git grep` / `diff` / 目視確認で行う。`claude/` 配下(Claude Code 用)と `codex/` 配下(Codex CLI 用ミラー)の両方を扱う。

**Tech Stack:** Markdown, git, bash (Git Bash on Windows)

## Global Constraints

- リポジトリ: `C:\Users\shishi\dev\dotfiles`(public repo。個人情報を含めない)
- `claude/plugins/` 配下は編集禁止(third-party、更新で上書きされる)
- `.gitconfig.win` の未コミット変更に触れない(本整理と無関係)
- 検索系の検証は必ず `git grep`(git 追跡ファイルのみ)を使う。`claude/` 配下に gitignore 済み transcript/backup があり、通常の grep は誤検出する
- コミットは 1 タスク 1 コミット。message は Conventional Commits + WHY を含む body
- `codex/skills/tdd/` は削除しない(Codex CLI に superpowers plugin が無いため保持)
- spec・本 plan 自身は旧名(`/tdd-red` 等)を記録として含むため、grep 検証では `:!docs/superpowers/` で除外する

---

### Task 1: claude/skills/codex-review を 2 モード化して書き換え

**Files:**
- Modify: `claude/skills/codex-review/SKILL.md`(全置換)

**Interfaces:**
- Produces: native / adversarial の 2 モード定義。Task 2 がこのファイルを codex 側へ複製し、Task 3 の CLAUDE.md Review gate がこの skill 名を参照する

- [ ] **Step 1: SKILL.md を以下の内容で全置換**

````markdown
---
name: codex-review
description: |
  Codex CLI を外部レビュアーとして使うレビューゲート。2 モード:
  native (欠陥検出、codex exec review) / adversarial (設計・前提への挑戦、
  懐疑プロンプト付き codex exec)。clean になるまで review→fix→re-review を
  反復する。bubblewrap sandbox が使えないホストでも動く bypass フラグ対応。
  Triggers: spec/PRD/plan の作成・更新直後 (adversarial モード)、major 実装
  ステップ完了後 (>=5 files / 新規モジュール / 公開 API / infra・config 変更)
  および git commit / PR / merge / release の前 (native モード)。
  キーワード: Codex レビュー, codex review, レビューゲート, codex-review,
  adversarial review, Codex で確認, レビューしてもらう。
---

# Codex Review (native / adversarial)

Codex CLI を独立レビュアーとして使い、Claude Code が書いた変更を検証する
レビューゲート。指摘が無くなる (clean) まで review→fix→re-review を反復する。

## モード選択

| マイルストーン | モード | 目的 |
|---|---|---|
| spec / PRD / plan / 設計ドキュメントの作成・更新直後 | **adversarial** | 設計判断・前提・トレードオフへの挑戦 |
| major 実装ステップ後、commit / PR / merge / release 前 | **native** | 実装欠陥の検出 |

## Prerequisites

1. `codex` CLI が PATH にある (`which codex` → 0)。無ければこの skill は
   適用不可。CLAUDE.md の Review gate に従い Claude 自身のレビューで代替する
2. Codex が認証済み (`401 Unauthorized` を返さない)
3. sandbox が使えない環境では `~/.claude/settings.json` の
   `permissions.allow` に
   `Bash(codex exec review --dangerously-bypass-approvals-and-sandbox:*)`
   が必要 (built-in "Create Unsafe Agents" safety rule の bypass)。
   最小権限の観点で `codex *` のような広い rule にはしない

## 規模判定 (2 つだけ)

`git diff --shortstat HEAD` を見て判断する:

1. **分割が要るか**: diff が巨大 (目安: >10 ファイルかつ互いに独立な変更) なら
   `--base <branch>` / `--commit <SHA>` で範囲を絞り複数回に分ける。
   同一パターンの繰り返しなら分割不要
2. **arch パスを先行させるか**: 新規モジュールや構造変更を含むなら、先に
   adversarial モードで設計妥当性を 1 回見てから native モードに入る

## Native モード

```bash
codex exec review \
  --dangerously-bypass-approvals-and-sandbox \
  --uncommitted \
  --title "<short description of the change>"
```

- `--uncommitted` は staged + unstaged + untracked をまとめてレビュー
- **`--uncommitted` と `[PROMPT]` は併用不可**。レビュー意図は `--title` に
  短く込める。特定範囲なら `--commit <SHA>` / `--base <branch>` (PROMPT 併用可)
- `--title` はコミット title 風に書くと Codex が文脈を掴みやすい

## Adversarial モード

素の `codex exec` に懐疑プロンプトを渡す (`review --uncommitted` はカスタム
プロンプト併用不可のため)。`<FOCUS>` にはユーザー指定の焦点、指定が無ければ
`the entire change` を入れる。

```bash
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  "$(cat <<'PROMPT'
You are performing an adversarial review. Your job is to break confidence in the change, not to validate it.
Inspect the uncommitted changes in this repository yourself: run `git status --short --untracked-files=all` and `git diff HEAD`, and read untracked files.
Focus: <FOCUS>
Stance: default to skepticism. Question whether the chosen approach is the right one, what assumptions it depends on, and where the design fails under real-world conditions. Happy-path-only behavior is a weakness. Do not give credit for good intent or likely follow-up work.
Prioritize failures that are expensive or hard to detect: auth and trust boundaries, data loss or corruption, rollback/retry/partial failure, race conditions and ordering assumptions, empty/null/timeout/degraded paths, version skew and migration hazards, observability gaps.
Report only material findings you can defend from the actual files. For each finding give: what can go wrong, why this code path is vulnerable, the likely impact, and a concrete change that reduces the risk. No style or naming feedback. Prefer one strong finding over several weak ones. If the change looks safe, say so directly.
PROMPT
)"
```

## bypass フラグを使う理由

- Codex 標準の sandbox は **bubblewrap** に依存し、unprivileged user
  namespaces を必要とする
- OrbStack devcontainer / 多くの Docker container / Windows ではこれが
  使えず `bwrap: No permissions to create a new namespace` で失敗する
  (`--sandbox read-only` 等も全て同じ失敗)
- container やローカルマシン自体が隔離・信頼境界を提供している場合に限り
  bypass する

## 反復

- 指摘があれば Claude Code が修正し、同じモードで再実行する
- **回数上限は無し。clean になるまで反復する**
- **膠着判定で停止**: 同一指摘が 2 回連続で解消できない、またはテスト/
  リンタ失敗が 2 回連続した場合は反復を止め、未解決事項として user に報告する
- clean の判定: native は "I did not find a discrete defect" 相当の結論、
  adversarial は "safe" 相当の結論

## Troubleshooting

### `Permission for this action has been denied. ... "Create Unsafe Agents block rule"`

`~/.claude/settings.json` の `permissions.allow` に下記を追加:

```json
"Bash(codex exec review --dangerously-bypass-approvals-and-sandbox:*)"
```

### `401 Unauthorized` または接続 hang

OpenAI auth token が期限切れ。interactive command は実行できないため
user に `! codex login` を依頼し、完了後にこの skill を再開する。

### Codex 出力が空のまま数分動かない

`ps -ef | grep codex` で CPU 0% なら、ほぼ確実に認証問題か API レート制限。
上の `401` セクションを参照。

### Codex exec 自体の失敗 (timeout / API 障害)

1. 1 回リトライ (timeout なら `--commit` / `--base` で範囲を絞る)
2. 再失敗 → そのフェーズをスキップし、最終レポートに「未レビュー」として
   理由を記録する

## Final report

レビュー完了時、以下を含む短いレポートを返す:

```
## Codex レビュー結果
- モード: native | adversarial / 反復: <X> 回
- ステータス: ✅ clean | ⚠️ 膠着で停止 (未解決あり)
- 主な指摘と修正:
  - <file>: <修正内容の要約>
- 未解決・未レビュー (ある場合のみ):
  - <file/scope>: <理由>
```
````

- [ ] **Step 2: 検証**

Run: `grep -c "adversarial" claude/skills/codex-review/SKILL.md && grep -c "反復上限" claude/skills/codex-review/SKILL.md || true`
Expected: adversarial が複数回ヒット、「反復上限」は 0 件(「回数上限は無し」に置き換わっている)

Run: `grep -n "5 回\|small\|medium\|large" claude/skills/codex-review/SKILL.md || echo CLEAN`
Expected: `CLEAN`(旧・反復上限と規模戦略表が消えている)

- [ ] **Step 3: Commit**

```bash
git add claude/skills/codex-review/SKILL.md
git commit -m "refactor(claude): rework codex-review skill into two modes" -m "Adversarial design review previously required the codex plugin. Embedding a skeptical prompt (adapted from the plugin's adversarial-review) makes the skill self-sufficient: adversarial mode for specs/plans, native mode for defect gates. The 5-iteration cap becomes progress-based stall detection, and the small/medium/large strategy table shrinks to two decisions (split large diffs, arch-first for structural changes)."
```

---

### Task 2: codex/skills/codex-review へ同期

**Files:**
- Modify: `codex/skills/codex-review/SKILL.md`(全置換)

**Interfaces:**
- Consumes: Task 1 の `claude/skills/codex-review/SKILL.md`

- [ ] **Step 1: claude 側の内容をコピー**

```bash
cp claude/skills/codex-review/SKILL.md codex/skills/codex-review/SKILL.md
```

注: codex 側の従来ファイルも frontmatter は name/description のみで、claude 側と同形式。差分を作る理由が無いため完全同一でよい。

- [ ] **Step 2: 検証**

Run: `diff claude/skills/codex-review/SKILL.md codex/skills/codex-review/SKILL.md && echo IDENTICAL`
Expected: `IDENTICAL`

- [ ] **Step 3: Commit**

```bash
git add codex/skills/codex-review/SKILL.md
git commit -m "refactor(codex): sync codex-review skill with claude side" -m "Without this sync the mirror would keep the opposite rules (5-iteration cap, size strategy table) after the claude-side rework, leaving two contradictory review standards."
```

---

### Task 3: CLAUDE.md スリム化 + rules/codex-review.md 削除

**Files:**
- Modify: `claude/CLAUDE.md`(全置換)
- Delete: `claude/rules/codex-review.md`

**Interfaces:**
- Consumes: Task 1 の codex-review skill(Review gate から名前で参照)
- Produces: 全セッション注入される規範。他タスクからの依存なし

- [ ] **Step 1: CLAUDE.md を以下の内容で全置換**

**重要**: `# 個人永続記憶 (personal memory)` セクション(見出しから末尾まで)は現行ファイルから**一字も変えずに**コピーして末尾に残すこと。以下の `[個人永続記憶セクションを現行のまま維持]` をその内容で置き換える。

```markdown
# ROLE AND EXPERTISE

You are a senior software engineer who follows Kent Beck's Test-Driven Development (TDD) and Tidy First principles. Prefer the simplest solution that could possibly work, eliminate duplication ruthlessly, express intent clearly, and keep methods small with a single responsibility.

- 実装(feature / bugfix)は superpowers:test-driven-development skill に従う
- 構造改善は tidying skill に従い、structural change と behavioral change を別コミットにする
- コミットは git-commit skill に従う(Conventional Commits・WHY-focused body)

# Review gate

At key milestones — right after creating or updating specs/PRDs/plans, after major implementation steps (≥5 files / new module / public API / infra-config changes), and before commit/PR/merge/release — run an external review and iterate review→fix→re-review until clean:

1. If the codex CLI is available: use the codex-review skill (native mode for defect gates, adversarial mode for specs/plans; sandbox workaround included).
2. If the codex CLI is unavailable: substitute Claude's own review — the `/code-review` skill (or superpowers:requesting-code-review if that is unavailable) — executed subagent-based to keep an independent perspective.

The iterate-until-clean gate is mandatory whichever reviewer is used. Skip it only when no review mechanism exists at all, and report that it was skipped.

[個人永続記憶セクションを現行のまま維持]
```

- [ ] **Step 2: rules/codex-review.md を削除**

```bash
git rm claude/rules/codex-review.md
```

- [ ] **Step 3: 検証**

Run: `grep -n "plan.md\|COMMIT DISCIPLINE\|TIDY FIRST APPROACH\|bubblewrap\|Always write one test" claude/CLAUDE.md || echo CLEAN`
Expected: `CLEAN`

Run: `grep -c "個人永続記憶" claude/CLAUDE.md && grep -n "test-driven-development\|code-review" claude/CLAUDE.md | head -5`
Expected: 個人永続記憶が 1 件以上、skill 名の参照が存在

Run: `git diff --cached --stat -- claude/CLAUDE.md`(コミット前に diff を目視し、個人永続記憶セクションに変更が無いこと)
Expected: 削除行は TDD/commit/workaround 節のみ

- [ ] **Step 4: Commit**

```bash
git add claude/CLAUDE.md
git commit -m "refactor(claude): slim CLAUDE.md to always-needed norms" -m "60+ lines of TDD/Tidy First/commit procedure duplicated what superpowers:test-driven-development, the tidying skill, and the git-commit skill already own, and the codex workaround section duplicated the codex-review skill. Per config-maintenance.md, CLAUDE.md keeps only the always-needed role declaration (with explicit skill pointers for discoverability) and the review gate with its no-codex fallback. rules/codex-review.md is removed because its general review mandate was injected redundantly alongside the gate every session."
```

---

### Task 4: claude/skills/tdd 削除

**Files:**
- Delete: `claude/skills/tdd/`(SKILL.md のみ)

**Interfaces:**
- Consumes: なし。superpowers:test-driven-development(plugin)が代替として存在することは確認済み

- [ ] **Step 1: 削除**

```bash
git rm -r claude/skills/tdd
```

注: `codex/skills/tdd/` は削除**しない**(Codex CLI に superpowers が無いため保持)。

- [ ] **Step 2: 検証**

Run: `ls claude/skills/ | grep -x tdd || echo GONE; ls codex/skills/ | grep -x tdd`
Expected: `GONE` の後に `tdd`(codex 側は残存)

- [ ] **Step 3: Commit**

```bash
git add -A claude/skills/tdd
git commit -m "refactor(claude): drop own tdd skill in favor of superpowers" -m "superpowers:test-driven-development is the authority for the TDD cycle. The own skill added nothing beyond it and pointed at /tdd-red, /tdd-green and /tdd-refactor slash commands that have never existed in this repo. The codex mirror keeps its tdd skill because Codex CLI cannot load superpowers."
```

---

### Task 5: scrum スイート全削除

**Files:**
- Delete: `claude/skills/scrum-dashboard/` `claude/skills/scrum-event-backlog-refinement/` `claude/skills/scrum-event-sprint-planning/` `claude/skills/scrum-event-sprint-retrospective/` `claude/skills/scrum-event-sprint-review/` `claude/skills/scrum-team-developer/` `claude/skills/scrum-team-product-owner/` `claude/skills/scrum-team-scrum-master/`
- Delete: `codex/skills/scrum-dashboard/` ほか同名 8 ディレクトリ
- Delete: `claude/agents/scrum/`
- Delete: `claude/rules/scrum/`

**Interfaces:**
- Consumes: なし(独立削除)

- [ ] **Step 1: 削除**

```bash
git rm -r claude/skills/scrum-* codex/skills/scrum-* claude/agents/scrum claude/rules/scrum
```

- [ ] **Step 2: 検証**

Run: `ls claude/skills/ codex/skills/ claude/agents/ claude/rules/ | grep -i scrum || echo GONE`
Expected: `GONE`

Run: `git grep -li scrum -- ':!docs/superpowers/' ':!claude/plugins/' || echo NO-REFS`
Expected: `NO-REFS`(git 追跡ファイルに scrum 参照が残っていない)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove unused scrum suite" -m "No project under ~/dev or ~/ghq contains a scrum.ts, so the received framework (8 skills x2 hosts, agents, path rule) never ran while its 8 skill descriptions were injected into every session. Ticket-driven team-agent execution is covered by real trackers plus superpowers plan skills and Agent worktree isolation, as recorded in the spec. Restorable from git history."
```

---

### Task 6: tidying の壊れ参照修正(claude + codex)

**Files:**
- Modify: `claude/skills/tidying/SKILL.md:27-28`
- Modify: `codex/skills/tidying/SKILL.md:27-28`

**Interfaces:**
- Consumes: なし

- [ ] **Step 1: 両ファイルの The Three Timings 表を修正**

両ファイルで、この 2 行:

```markdown
| **Tidy First** | Code is hard to change | `/tidy-first` → `refactor:` commit → behavioral change → `feat:/fix:` commit |
| **Tidy After** | Feature revealed better structure | behavioral change → `feat:/fix:` commit → `/tidy-after` → `refactor:` commit |
```

を、この 2 行に置換(存在しない slash command 参照を平文に):

```markdown
| **Tidy First** | Code is hard to change | structural tidying → `refactor:` commit → behavioral change → `feat:/fix:` commit |
| **Tidy After** | Feature revealed better structure | behavioral change → `feat:/fix:` commit → structural tidying → `refactor:` commit |
```

- [ ] **Step 2: 検証**

Run: `git grep -nE '/tidy-first|/tidy-after' -- ':!docs/superpowers/' || echo CLEAN`
Expected: `CLEAN`

Run: `diff claude/skills/tidying/SKILL.md codex/skills/tidying/SKILL.md && echo IDENTICAL`
Expected: `IDENTICAL`(元々同一内容のミラーのため)

- [ ] **Step 3: Commit**

```bash
git add claude/skills/tidying/SKILL.md codex/skills/tidying/SKILL.md
git commit -m "fix(skills): replace phantom /tidy-* command references in tidying" -m "The timing table pointed at /tidy-first and /tidy-after slash commands that have never existed in this repo; plain wording describes the same flow without implying an invocable command."
```

---

### Task 7: git-commit skill スリム化(claude + codex)

**Files:**
- Modify: `claude/skills/git-commit/SKILL.md`(全置換)
- Modify: `codex/skills/git-commit/SKILL.md`(全置換)

**Interfaces:**
- Consumes: なし。CLAUDE.md(Task 3)が skill 名で参照

- [ ] **Step 1: claude/skills/git-commit/SKILL.md を以下で全置換**

````markdown
---
name: git-commit
description: "Stage meaningful diffs and create Conventional Commits with WHY-focused messages"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git restore:*), Bash(git show:*)
---

# Git Commit

Create Conventional Commits (1.0.0) with WHY-focused messages.

## Context

Inspect the repository state first:

```bash
git status --short
git diff --stat            # unstaged
git diff --cached --stat   # staged
git log --oneline -10      # style reference
```

## Rules beyond what the Conventional Commits spec says

- **Breaking changes**: only `feat!:` / `fix!:` may carry `!`. If a
  refactor/style/docs/chore changed behavior, it is misclassified —
  recategorize as feat or fix.
- **Message philosophy (t-wada)**: code describes HOW, tests describe WHAT,
  commit log describes **WHY**, code comments describe WHY NOT. The body
  explains reasoning and motivation — what problem, why now, why this
  approach over alternatives — not a restatement of the diff.
- Subject: imperative mood, under 50 characters.
- One logical unit per commit. Use `git add -p <file>` when a file mixes
  unrelated changes, and split into multiple commits, one at a time.

## Checklist before committing

- [ ] Staged changes serve a single purpose (verify with `git diff --cached`)
- [ ] Type matches the nature of the change (`refactor:` has no behavior change)
- [ ] Body answers: what problem, why now, why this approach
- [ ] Breaking changes are marked `feat!:` / `fix!:`
````

- [ ] **Step 2: codex/skills/git-commit/SKILL.md を以下で全置換**

claude 側と同一だが、frontmatter は codex 側の従来形式(name / description のみ、allowed-tools なし)に合わせる:

````markdown
---
name: git-commit
description: "Stage meaningful diffs and create Conventional Commits with WHY-focused messages"
---

# Git Commit

Create Conventional Commits (1.0.0) with WHY-focused messages.

## Context

Inspect the repository state first:

```bash
git status --short
git diff --stat            # unstaged
git diff --cached --stat   # staged
git log --oneline -10      # style reference
```

## Rules beyond what the Conventional Commits spec says

- **Breaking changes**: only `feat!:` / `fix!:` may carry `!`. If a
  refactor/style/docs/chore changed behavior, it is misclassified —
  recategorize as feat or fix.
- **Message philosophy (t-wada)**: code describes HOW, tests describe WHAT,
  commit log describes **WHY**, code comments describe WHY NOT. The body
  explains reasoning and motivation — what problem, why now, why this
  approach over alternatives — not a restatement of the diff.
- Subject: imperative mood, under 50 characters.
- One logical unit per commit. Use `git add -p <file>` when a file mixes
  unrelated changes, and split into multiple commits, one at a time.

## Checklist before committing

- [ ] Staged changes serve a single purpose (verify with `git diff --cached`)
- [ ] Type matches the nature of the change (`refactor:` has no behavior change)
- [ ] Body answers: what problem, why now, why this approach
- [ ] Breaking changes are marked `feat!:` / `fix!:`
````

- [ ] **Step 3: 検証**

Run: `grep -n 'model:' claude/skills/git-commit/SKILL.md || echo NO-MODEL`
Expected: `NO-MODEL`

Run: `grep -n '^!' claude/skills/git-commit/SKILL.md codex/skills/git-commit/SKILL.md || echo NO-INJECTION`
Expected: `NO-INJECTION`(`` !`...` `` 動的注入が無い)

Run: `grep -n "show me\|we'll" claude/skills/git-commit/SKILL.md || echo NO-DIALOG`
Expected: `NO-DIALOG`

- [ ] **Step 4: Commit**

```bash
git add claude/skills/git-commit/SKILL.md codex/skills/git-commit/SKILL.md
git commit -m "refactor(skills): slim git-commit to rules Claude doesn't know" -m "165 lines taught Claude things it already knows (Conventional Commits type list, git syntax, long examples) via command-era mechanisms that don't work in skills (! context injection, model frontmatter, interactive voice). What remains is the actual house style: WHY-focused bodies per t-wada, feat!/fix!-only breaking changes, 50-char imperative subjects, and add -p partial staging per logical unit. Context gathering adopts the codex mirror's run-git-yourself form, which works in both hosts."
```

---

### Task 8: 全体検証 + レビューゲート

**Files:**
- なし(検証と最終レビューのみ)

**Interfaces:**
- Consumes: Task 1〜7 の全変更

- [ ] **Step 1: spec の検証項目を一括実行**

```bash
cd ~/dev/dotfiles
git grep -nE '/tdd-red|/tdd-green|/tdd-refactor|/tidy-first|/tidy-after' -- ':!docs/superpowers/' || echo PASS-1
git grep -ln 'rules/codex-review' -- ':!docs/superpowers/' || echo PASS-2
git grep -li scrum -- ':!docs/superpowers/' ':!claude/plugins/' || echo PASS-3
grep -n "bubblewrap\|COMMIT DISCIPLINE\|plan.md" claude/CLAUDE.md || echo PASS-4
grep -c "adversarial" claude/skills/codex-review/SKILL.md   # >0 であること
grep -n "test-driven-development" claude/CLAUDE.md           # ヒットすること
diff claude/skills/codex-review/SKILL.md codex/skills/codex-review/SKILL.md && echo PASS-5
diff claude/skills/tidying/SKILL.md codex/skills/tidying/SKILL.md && echo PASS-6
ls codex/skills/tdd/SKILL.md   # 存在すること
```

Expected: PASS-1〜6 がすべて出力され、adversarial カウント >0、test-driven-development がヒット、`codex/skills/tdd/SKILL.md` が存在。

失敗した項目があれば該当タスクに戻って修正し、再実行する。

- [ ] **Step 2: レビューゲート実行(codex CLI 無し環境のフォールバック)**

このマシンに codex CLI は無いため、新 Review gate のフォールバックに従い Claude 自身のレビューで代替する: `/code-review` skill(または superpowers:requesting-code-review)で、この plan の全コミット(`git diff master 開始時点..HEAD`)を subagent ベースでレビューし、指摘があれば修正 → 再レビューを clean まで反復する。

- [ ] **Step 3: spec の状態を更新して final commit**

`docs/superpowers/specs/2026-07-05-claude-config-consolidation-design.md` の `状態: レビュー待ち` を `状態: 実装済み (2026-07-05)` に変更。

```bash
git add docs/superpowers/specs/2026-07-05-claude-config-consolidation-design.md
git commit -m "docs(claude): mark consolidation spec as implemented"
```
