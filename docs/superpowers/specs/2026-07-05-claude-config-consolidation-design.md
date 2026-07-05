# Claude 設定(CLAUDE.md / rules / skills / agents)重複・矛盾整理 設計

日付: 2026-07-05
状態: 実装済み (2026-07-05)

## 目的

`claude/CLAUDE.md`・`claude/rules/`・`claude/skills/`・`claude/agents/` の間、および superpowers / codex plugin との間にある重複と矛盾を解消する。整理の基準は `claude/rules/claude/config-maintenance.md` が既に定義している原則に従う:

- 常時必要な context だけ CLAUDE.md に置く(context bloat 禁止)
- 条件付きの詳細手順は skill へ
- 重複する内容は 1 箇所に統合する

## 決定事項(ユーザー承認済み)

1. **スコープ**: 自作分の統合に加え、plugin との棲み分けも明文化する
2. **棲み分け方針**: plugin を正とし、自作は plugin に無い差分(固有知見)のみ残す
3. **scrum**: スイート全削除(`claude/skills/scrum-*`・`codex/skills/scrum-*`・`claude/rules/scrum/`・`claude/agents/scrum/`)。`scrum.ts` を使うプロジェクトが `~/dev`・`~/ghq` に存在せず未使用のため。復元は git 履歴から可能。「チケット取り出し→チームエージェント実行」の代替は: バックログは実チケットシステム(GitHub Issues は `gh` CLI、Linear/Jira は MCP コネクタ)、実行は superpowers:writing-plans → subagent-driven-development、並列化は Agent tool の worktree isolation / background 実行で賄う
4. **plan.md 指示**: CLAUDE.md 冒頭の「Always follow plan.md / "go" ワークフロー」は削除し、superpowers:writing-plans / executing-plans に寄せる
5. **codex レビューは方針 2 の例外**: adversarial レビューを plugin なしで使えるようにするため、自作 `skills/codex-review` を正とする(native/adversarial の使い分け・bypass workaround を内蔵)。codex plugin のコマンドは補助扱い。plugin 自体はアンインストールしない — `codex-rescue` agent(行き詰まり時に Claude が自発的に Codex へ作業委譲する機能)はレビューと別用途で、自作 skill では代替しないため

## 現状の問題(調査結果)

### 重複

| # | 内容 | 箇所 |
|---|------|------|
| 1 | codex-review。技術詳細(bypass フラグ・`--uncommitted` と PROMPT 併用不可・401 対処)は CLAUDE.md「Workaround」節と `skills/codex-review` で重複、レビューゲートの一般規範は CLAUDE.md「Review gate」節と `rules/codex-review.md`(9 行の一般論)で重複 | CLAUDE.md / `rules/codex-review.md` / `skills/codex-review/SKILL.md` / codex plugin |
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

- ROLE 宣言: Kent Beck の TDD / Tidy First に従う senior engineer である旨 + コード品質原則を 2〜3 行。「実装は superpowers:test-driven-development skill、構造改善は tidying skill に従う」と skill 名を明記する(config-maintenance.md の discoverability 原則。規範は常時ロードの CLAUDE.md に残り、手順詳細だけ skill へ委譲される)
- Review gate: トリガー条件(spec/plan 更新直後・major 実装ステップ後 ≥5 files/公開 API/infra-config・commit/PR/release 前)+ レビュー手段のフォールバック順を明記した短い段落:
  1. codex CLI が使える環境 → codex-review skill(native/adversarial の使い分け・bypass workaround を内蔵。下記 3 参照)
  2. codex CLI が無い環境 → Claude 自身のレビュー機能で代替: `/code-review` skill(無ければ superpowers:requesting-code-review)で review→fix→re-review を clean まで反復。外部レビュアー同様、独立視点を保つため subagent ベースで実行する
  いずれの手段でも「clean になるまで反復」のゲート自体は必須とする(レビュー手段が無い場合のみスキップし、その旨を報告する)
- 個人永続記憶セクション: 現状のまま(常時必要・スキル化不適)

### 2. `claude/rules/` の整理

- `rules/codex-review.md` を削除(レビューゲートの一般規範が CLAUDE.md の Review gate と二重に全セッション注入されているため、CLAUDE.md 側に一本化)
- `rules/scrum/` を削除(scrum スイート全削除の一部。トリガー対象の `scrum.ts` がどのプロジェクトにも存在しない)
- `rules/claude/config-maintenance.md`・`rules/rust/no-mod-rs.md` は現状維持

### 3. `claude/skills/` の整理

- `skills/tdd/` を削除(superpowers:test-driven-development が正。壊れた `/tdd-*` 参照も消滅)
- `skills/scrum-*` を全削除(dashboard + event×4 + team×3 の 8 skill。未使用のまま description が毎セッション注入されていた)
- `skills/tidying/SKILL.md` は保持(Tidy First の三タイミング・DRY 判断・behavior contract は plugin に無い差分)。`/tidy-first` `/tidy-after` の壊れ参照をコマンドでない文言(例:「Tidy First のタイミングで」)に修正
- `skills/codex-review/` を拡張し、plugin なしで完結するレビューゲートの正とする:
  - **2 モードの使い分け**を定義: spec/plan/設計ドキュメント更新後は **adversarial モード**(設計・前提への挑戦)、実装ステップ後・commit/PR/release 前は **native モード**(欠陥検出)
  - native モード: 従来どおり `codex exec review --uncommitted`(+ bypass workaround)
  - adversarial モード: plugin の `prompts/adversarial-review.md` 相当の懐疑プロンプトを skill 内に持ち、素の `codex exec "<プロンプト>"` で実行(`review --uncommitted` はカスタムプロンプト併用不可のため)。focus テキストを渡せる
  - **反復上限を撤廃**: clean になるまで反復する。ただし同一指摘が解消できず膠着した場合は反復を止めてユーザーに報告する(回数制限ではなく進展判定)
  - **規模判定を簡素化**: small/medium/large の戦略表をやめ、「diff が大きすぎて分割(`--base`/`--commit`)が要るか」「arch パスを先行させるか」の 2 判断だけ残す
- `skills/git-commit/` は保持しつつスリム化する(plugin に commit crafting 相当は無く置換不可):
  - Claude が既に知っている内容(Conventional Commits の型一覧・`git commit` 構文・長文サンプル)を削除し、固有の運用ルールだけ残す: t-wada の WHY 哲学(code=HOW / tests=WHAT / log=WHY / comments=WHY NOT)、breaking change は `feat!`/`fix!` のみ、命令形 50 字以内、`git add -p` による論理単位の分割ステージング、短い品質チェックリスト(目安: 165 行 → 40 行前後)
  - `` !`...` `` の動的コンテキスト注入(コマンド用前処理)をやめ、codex ミラーと同じ「bash で自分で `git status`/`git diff` を確認する」形式に統一
  - skill で効果が疑わしい `model: sonnet` frontmatter を削除
  - 対話口調(「show me ...」)を自律実行向けの記述に修正
- `skills/memory-consolidate/`・`skills/compact-prep/`・`skills/adr/`・`skills/logging/`・`skills/missing-tools/` は保持(plugin に無い差分、または固有システム向け)

### 4. `claude/agents/` の整理

- `agents/scrum/` を削除(scrum スイート全削除の一部。決定事項 3 参照)
- `agent-architect.md`・`agent-improver.md`・`agent-reviewer.md`・`claude-skills-architect.md` は現状維持(重複なし)

### 5. `codex/skills/` ミラーへの同期

- `codex/skills/tidying/SKILL.md` にも同じ壊れ参照があるため、claude 側と同じ修正を反映する
- `codex/skills/git-commit/SKILL.md` にも claude 側と同じスリム化を反映する(コンテキスト確認の bash 形式は codex 側が既に正しいので、そこは claude 側を codex 側に合わせる)
- `codex/skills/codex-review/SKILL.md` にも claude 側の改修(native/adversarial 2 モード・反復上限撤廃・規模判定簡素化)を同期する。同期しないと「反復上限 5 回・規模戦略表」が正反対の規範として codex 側に残る
- `codex/skills/scrum-*` は scrum スイート全削除の一部として削除する
- `codex/skills/tdd/` は**保持**する。claude 側の削除理由(superpowers:test-driven-development が正)は Codex CLI に superpowers plugin が無いため成立しない。内容は既に `/tdd-*` 参照なしに書き直し済みで自己完結している
- Codex CLI は `claude/` を読めないため、ミラー構造自体は意図的なものとして維持する(削除・統合しない)

## 矛盾の解消結果

- コミット形式: COMMIT DISCIPLINE 節の削除により git-commit skill(Conventional Commits)が単一規範になる。structural/behavioral の区別は tidying skill の `refactor:` vs `feat:/fix:` 運用に吸収済み
- レビュー手順: CLAUDE.md の短縮 Review gate が「codex CLI あり → codex-review skill(native/adversarial 使い分け・bypass 内蔵)、codex CLI なし → Claude 自身のレビュー skill で代替」というフォールバック順を明示し、二重規範を解消。codex plugin が無くても adversarial レビューを含むゲート全体が機能する
- 壊れた `/tdd-*` `/tidy-*` 参照: 削除・文言修正で全て解消

## スコープ外

- plugin 側ファイル(`claude/plugins/` 配下)は編集しない(更新で上書きされるため)
- `codex/skills/` のミラー構造そのもの(統合・廃止)の見直しはしない(内容の同期は「5. codex/skills/ ミラーへの同期」のとおり実施する)
- `.gitconfig.win` の未コミット変更(本整理と無関係)

## 検証

検索系のチェックは **git 追跡ファイルのみ**を対象にする(`git grep` を使う。`claude/` 配下には gitignore 済みの session transcript・backup が大量にあり、旧名を含むため通常の grep では誤検出する)。

削除・除去の確認:

- `git grep -E '/tdd-red|/tdd-green|/tdd-refactor|/tidy-first|/tidy-after'` が 0 件(本 spec 自身を除く)
- `claude/CLAUDE.md` に TDD 詳細手順・コミット規律・sandbox workaround の重複記述が残っていないこと
- 削除した `skills/tdd`(claude 側)・scrum スイート(`skills/scrum-*`・`agents/scrum`・`rules/scrum`)・`rules/codex-review.md` への参照が git 追跡ファイルに残っていないこと(本 spec 自身を除く)
- `claude/skills/git-commit/SKILL.md` に `` !`...` `` 動的注入と `model:` frontmatter が残っていないこと

追加・書き換えの確認:

- `claude/CLAUDE.md` の Review gate 段落にフォールバック順(codex CLI あり → codex-review skill / なし → `/code-review` または superpowers:requesting-code-review)が存在すること
- `claude/CLAUDE.md` の ROLE 宣言に superpowers:test-driven-development と tidying skill の名前が明記されていること
- `claude/skills/codex-review/SKILL.md` に native/adversarial 2 モードの使い分け・膠着判定(回数上限なし)・簡素化した規模判定が存在すること
- `codex/skills/` の tidying・git-commit・codex-review が claude 側と意図どおり同期していること(diff で確認、bash コンテキスト確認形式などの意図差分のみ)
- `codex/skills/tdd/` が保持されていること
