# Claude 設定(CLAUDE.md / rules / skills / agents)重複・矛盾整理 設計

日付: 2026-07-05
状態: レビュー待ち

## 目的

`claude/CLAUDE.md`・`claude/rules/`・`claude/skills/`・`claude/agents/` の間、および superpowers / codex plugin との間にある重複と矛盾を解消する。整理の基準は `claude/rules/claude/config-maintenance.md` が既に定義している原則に従う:

- 常時必要な context だけ CLAUDE.md に置く(context bloat 禁止)
- 条件付きの詳細手順は skill へ
- 重複する内容は 1 箇所に統合する

## 決定事項(ユーザー承認済み)

1. **スコープ**: 自作分の統合に加え、plugin との棲み分けも明文化する
2. **棲み分け方針**: plugin を正とし、自作は plugin に無い差分(固有知見)のみ残す
3. **scrum**: skill に一本化し、`agents/scrum/` は削除する
4. **plan.md 指示**: CLAUDE.md 冒頭の「Always follow plan.md / "go" ワークフロー」は削除し、superpowers:writing-plans / executing-plans に寄せる

## 現状の問題(調査結果)

### 重複

| # | 内容 | 箇所 |
|---|------|------|
| 1 | codex-review(bypass フラグ・`--uncommitted` と PROMPT 併用不可・401 対処) | CLAUDE.md「Review gate + Workaround」節 / `rules/codex-review.md` / `skills/codex-review/SKILL.md` / codex plugin |
| 2 | TDD / Tidy First の詳細手順 | CLAUDE.md の約 60 行(CORE PRINCIPLES〜EXAMPLE WORKFLOW) / `skills/tdd` / `skills/tidying` / superpowers:test-driven-development |
| 3 | コミット規律 | CLAUDE.md「COMMIT DISCIPLINE」節 / `skills/git-commit` |
| 4 | scrum ワークフロー | `agents/scrum/`(events + team) / `skills/scrum-*`(同名・同 description で agent と skill の二重登録) |

### 矛盾・壊れた参照

| # | 内容 |
|---|------|
| 1 | レビュー手順の二重規範: CLAUDE.md は「`/codex:review` を使え」、skill は「常に bypass フラグで `codex exec review` 直叩き」 |
| 2 | コミットメッセージ形式: CLAUDE.md「structural か behavioral かを明記」 vs git-commit skill「Conventional Commits」 |
| 3 | 存在しない slash command への参照: `/tdd-red` `/tdd-green` `/tdd-refactor`(`skills/tdd`・`skills/scrum-team-developer`・`agents/scrum/team/developer.md`)、`/tidy-first` `/tidy-after`(`skills/tidying`)。`commands/` ディレクトリ自体が存在しない |
| 4 | CLAUDE.md 冒頭の plan.md 指示がグローバル設定なのに全プロジェクトに plan.md を前提とする |
| 5 | config-maintenance.md が定める「CLAUDE.md の context bloat 禁止」に CLAUDE.md 自身が違反 |

## 変更内容

### 1. `claude/CLAUDE.md` のスリム化

削除:

- 冒頭の plan.md / "go" 段落
- 「CORE DEVELOPMENT PRINCIPLES」「TDD METHODOLOGY GUIDANCE」「TIDY FIRST APPROACH」「COMMIT DISCIPLINE」「CODE QUALITY STANDARDS」「REFACTORING GUIDELINES」「EXAMPLE WORKFLOW」の各節(superpowers:test-driven-development・自作 tidying・git-commit skill に委譲)
- 「Workaround when Codex's bubblewrap sandbox is unavailable」節(`skills/codex-review` に同内容あり。参照 1 行に置換)
- 末尾の「Always write one test at a time, ...」段落(TDD 重複)

残す(圧縮):

- ROLE 宣言: Kent Beck の TDD / Tidy First に従う senior engineer である旨 + コード品質原則を 2〜3 行
- Review gate: トリガー条件(spec/plan 更新直後・major 実装ステップ後 ≥5 files/公開 API/infra-config・commit/PR/release 前)+ レビュー手段のフォールバック順を明記した短い段落:
  1. codex CLI が使える環境 → `/codex:review`(sandbox が使えない場合は codex-review skill の workaround)
  2. codex CLI が無い環境 → Claude 自身のレビュー機能で代替: `/code-review` skill(無ければ superpowers:requesting-code-review)で review→fix→re-review を clean まで反復。外部レビュアー同様、独立視点を保つため subagent ベースで実行する
  いずれの手段でも「clean になるまで反復」のゲート自体は必須とする(レビュー手段が無い場合のみスキップし、その旨を報告する)
- 個人永続記憶セクション: 現状のまま(常時必要・スキル化不適)

### 2. `claude/rules/` の整理

- `rules/codex-review.md` を削除(CLAUDE.md の短縮 Review gate に一本化。現状ほぼ同内容が 2 系統で全セッションに注入されている)
- `rules/claude/config-maintenance.md`・`rules/rust/no-mod-rs.md`・`rules/scrum/scrum-ts.md` は現状維持

### 3. `claude/skills/` の整理

- `skills/tdd/` を削除(superpowers:test-driven-development が正。壊れた `/tdd-*` 参照も消滅)
- `skills/tidying/SKILL.md` は保持(Tidy First の三タイミング・DRY 判断・behavior contract は plugin に無い差分)。`/tidy-first` `/tidy-after` の壊れ参照をコマンドでない文言(例:「Tidy First のタイミングで」)に修正
- `skills/scrum-team-developer/SKILL.md` の `/tdd-red` 等の参照を superpowers:test-driven-development skill への参照に書き換え
- `skills/codex-review/`・`skills/git-commit/`・`skills/memory-consolidate/`・`skills/compact-prep/`・`skills/adr/`・`skills/logging/`・`skills/missing-tools/`・`skills/scrum-*` は保持(plugin に無い差分、または固有システム向け)

### 4. `claude/agents/` の整理

- `agents/scrum/` を削除(skill に一本化)
- `agent-architect.md`・`agent-improver.md`・`agent-reviewer.md`・`claude-skills-architect.md` は現状維持(重複なし)

### 5. `codex/skills/` ミラーへの同期

- `codex/skills/tidying/SKILL.md` と `codex/skills/scrum-team-developer/SKILL.md` にも同じ壊れ参照があるため、claude 側と同じ修正を反映する
- Codex CLI は `claude/` を読めないため、ミラー構造自体は意図的なものとして維持する(削除・統合しない)

## 矛盾の解消結果

- コミット形式: COMMIT DISCIPLINE 節の削除により git-commit skill(Conventional Commits)が単一規範になる。structural/behavioral の区別は tidying skill の `refactor:` vs `feat:/fix:` 運用に吸収済み
- レビュー手順: CLAUDE.md の短縮 Review gate が「codex CLI あり → `/codex:review`(sandbox 不可なら codex-review skill)、codex CLI なし → Claude 自身のレビュー skill で代替」というフォールバック順を明示し、二重規範を解消。codex が無い環境でもゲート自体は維持される
- 壊れた `/tdd-*` `/tidy-*` 参照: 削除・文言修正で全て解消

## スコープ外

- plugin 側ファイル(`claude/plugins/` 配下)は編集しない(更新で上書きされるため)
- `codex/skills/` のミラー構造の見直し(今回は壊れ参照の同期修正のみ)
- `nushell/config.nu` の未コミット変更(本整理と無関係)

## 検証

- 変更後、`claude/`・`codex/` 配下(`claude/plugins/` を除く)に `/tdd-red|/tdd-green|/tdd-refactor|/tidy-first|/tidy-after` への参照が残っていないこと(grep で確認)
- `claude/CLAUDE.md` に TDD 詳細手順・コミット規律・sandbox workaround の重複記述が残っていないこと
- 削除した `skills/tdd`・`agents/scrum`・`rules/codex-review.md` への参照が他ファイルに残っていないこと
