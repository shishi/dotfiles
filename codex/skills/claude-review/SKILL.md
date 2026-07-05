---
name: claude-review
description: |
  Claude Code CLI を外部レビュアーとして使うレビューゲート (Codex ホスト用)。
  2 モード: native (欠陥検出、claude -p "/code-review") / adversarial
  (設計・前提への挑戦、懐疑プロンプトを claude -p に渡す)。clean になるまで
  review→fix→re-review を反復する。別モデル系統によるクロスレビューのため
  独立性が最も高く、Codex ホストの第一レビュー手段。
  Triggers: spec/PRD/plan の作成・更新直後 (adversarial モード)、major 実装
  ステップ完了後 (>=5 files / 新規モジュール / 公開 API / infra・config 変更)
  および git commit / PR / merge / release の前 (native モード)。
  キーワード: Claude レビュー, claude review, レビューゲート, クロスレビュー,
  Claude で確認, レビューしてもらう。
---

# Claude Review (Codex ホスト用クロスレビューゲート)

Claude Code CLI を独立レビュアーとして使い、Codex が書いた変更を**別モデル系統**
の視点で検証する。指摘が無くなる (clean) まで review→fix→re-review を反復する。

## モード選択

| マイルストーン | モード | 目的 |
|---|---|---|
| spec / PRD / plan / 設計ドキュメントの作成・更新直後 | **adversarial** | 設計判断・前提・トレードオフへの挑戦 |
| major 実装ステップ後、commit / PR / merge / release 前 | **native** | 実装欠陥の検出 |

## Prerequisites

1. `claude` CLI が PATH にある (`which claude` → 0)。無ければ AGENTS.md の
   Review gate に従い codex-review skill (内側 `codex exec`) にフォールバック
2. Claude Code が認証済み (認証エラー時は user に対話セッションでの再ログインを依頼)
3. 内側の `claude` プロセスは Anthropic API への network access が必要。
   sandbox で遮断される場合は `~/.codex/config.toml` の sandbox 設定で許可する
   (codex-review skill の Prerequisites と同じ対応)

## Native モード

Claude 組み込みの `/code-review` skill を headless で起動する。working tree の
diff を対象に、独立 subagent がバグ検出する。

```bash
claude -p "/code-review high" \
  --allowedTools "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)"
```

- effort は low/medium (少数・高確度) 〜 high/max (広カバレッジ)。ゲート用途は
  high を既定にする
- レビュー焦点を足す場合はプロンプトに続ける:
  `claude -p "/code-review high focus: codex/skills 配下の変更"`
- `--allowedTools` は headless 実行での権限プロンプト回避のため。git の
  read-only コマンドだけを許可し、それ以上は与えない

## Adversarial モード

Claude に adversarial 専用 skill は無いため、懐疑プロンプトを直接渡す。
`<FOCUS>` にはユーザー指定の焦点、指定が無ければ `the entire change` を入れる。

```bash
claude -p "$(cat <<'PROMPT'
You are performing an adversarial review. Your job is to break confidence in the change, not to validate it.
Inspect the uncommitted changes in this repository yourself: run `git status --short --untracked-files=all` and `git diff HEAD`, and read untracked files.
Focus: <FOCUS>
Stance: default to skepticism. Question whether the chosen approach is the right one, what assumptions it depends on, and where the design fails under real-world conditions. Happy-path-only behavior is a weakness. Do not give credit for good intent or likely follow-up work.
Prioritize failures that are expensive or hard to detect: auth and trust boundaries, data loss or corruption, rollback/retry/partial failure, race conditions and ordering assumptions, empty/null/timeout/degraded paths, version skew and migration hazards, observability gaps.
Report only material findings you can defend from the actual files. For each finding give: what can go wrong, why this code path is vulnerable, the likely impact, and a concrete change that reduces the risk. No style or naming feedback. Prefer one strong finding over several weak ones. If the change looks safe, say so directly.
PROMPT
)" --allowedTools "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)"
```

## 反復

- 指摘があれば作業エージェント自身が修正し、同じモードで再実行する
- **回数上限は無し。clean になるまで反復する**
- **膠着判定で停止**: 同一指摘が 2 回連続で解消できない、またはテスト/
  リンタ失敗が 2 回連続した場合は反復を止め、未解決事項として user に報告する
- clean の判定: native は指摘 0 件の結論、adversarial は "safe" 相当の結論

## Troubleshooting

### claude が git diff を読めず浅いレビューしか返らない

`--allowedTools` の指定漏れか書式ミス。スペース区切りで複数指定する
(`--allowedTools "Bash(git status:*)" "Bash(git diff:*)" ...`)。

### 認証エラー / ログイン要求で止まる

headless では対話ログインできない。user に対話セッションで claude の
再ログインを依頼し、完了後にこの skill を再開する。

### API に到達できず hang する

sandbox の network 遮断が原因。Prerequisites 3 の config.toml 設定を確認する。

### timeout / 出力が途中で切れる

`--effort low` に下げるか、レビュー範囲をプロンプトで絞って複数回に分ける。

## Final report

レビュー完了時、以下を含む短いレポートを返す:

```
## Claude レビュー結果
- モード: native | adversarial / 反復: <X> 回
- ステータス: ✅ clean | ⚠️ 膠着で停止 (未解決あり)
- 主な指摘と修正:
  - <file>: <修正内容の要約>
- 未解決・未レビュー (ある場合のみ):
  - <file/scope>: <理由>
```
