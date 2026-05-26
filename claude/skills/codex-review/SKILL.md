---
name: codex-review
description: |
  Codex CLI を read-only な外部レビュアーとして使い、working tree の変更を
  反復的にレビューする (review→fix→re-review、ok: true まで)。bubblewrap
  sandbox が利用不可なホスト (OrbStack devcontainer / Docker container 等
  unprivileged user namespaces が無効な環境) でも動くように bypass フラグを
  使う。
  Triggers: spec/PRD/plan の作成・更新直後、major 実装ステップ完了後
  (>=5 files / 新規モジュール / 公開 API / infra・config 変更)、および
  git commit / PR / merge / release の前。
  キーワード: Codex レビュー, codex review, レビューゲート, codex-review,
  Codex で確認, レビューしてもらう。
---

# Codex Review (sandbox-aware)

Codex CLI を外部レビュアーとして使い、Claude Code が書いた変更を独立した
視点で検証するレビューゲート。`/codex:review` slash command や標準の
`codex-review` 系 skill が bubblewrap sandbox で失敗する環境向けの
workaround を含む。

## When to use

- 仕様書 / SPEC / PRD / 要件定義 / 設計、実装計画 (`plan.md` 等) の作成・更新直後
- major 実装ステップ完了後: **5 ファイル以上 / 新規モジュール / 公開 API / infra・config 変更**
- `git commit` / PR / merge / release の **直前**

## Prerequisites

1. `codex` CLI が PATH にある (`which codex` → 0)
2. Codex が認証済み (`codex` が `401 Unauthorized` を返さない)
3. `~/.claude/settings.json` の `permissions.allow` に
   `Bash(codex exec review --dangerously-bypass-approvals-and-sandbox:*)`
   が含まれる (Claude Code の built-in "Create Unsafe Agents" safety rule
   を bypass するため)

## Workflow

### 1. 規模判定

```bash
git diff --shortstat HEAD
```

| 規模 | 基準 | 戦略 |
|-----|------|-----|
| small | ≤3 ファイル、≤100 行 | diff 1 回 |
| medium | 4-10 ファイル、100-500 行 | arch → diff |
| large | >10 ファイル、>500 行 | arch → diff (並列) → cross-check |

ファイル数と行数で評価が食い違う場合、**変更内容の独立性** で判断する
(同一パターンの繰り返しなら medium 相当に下げて OK)。

### 2. Review 実行 (sandbox-bypass workaround)

```bash
codex exec review \
  --dangerously-bypass-approvals-and-sandbox \
  --uncommitted \
  --title "<short description of the change>"
```

なぜ `--dangerously-bypass-approvals-and-sandbox` を使うか:

- Codex 標準の sandbox 実装は **bubblewrap** に依存し、unprivileged user
  namespaces (`kernel.unprivileged_userns_clone=1`) を必要とする
- **OrbStack devcontainer / 多くの Docker container** はこれが無効で、
  Codex は `bwrap: No permissions to create a new namespace` で失敗
- `--sandbox read-only` も `--sandbox workspace-write` も全て bubblewrap
  を使うため、いずれも同じ失敗
- container 自体が外部の隔離境界を提供しているので、内側で bypass しても
  ホストへの影響は無い (= `intended solely for running in environments that
  are externally sandboxed` の条件を満たす)

#### 引数の注意点

- `--uncommitted` は staged + unstaged + untracked をまとめてレビュー
- **`--uncommitted` と `[PROMPT]` は併用不可**。レビュー意図 (review focus)
  は `--title` に短く込める。詳細プロンプトを使いたい場合は `--commit <SHA>`
  または `--base <branch>` を併用する
- `--title` はコミット時の title 風に書くと Codex が文脈を掴みやすい

### 3. 結果解釈と反復

| Codex の応答 | 次のアクション |
|---|---|
| "I did not find a discrete defect" / 同等の clean な結論 | **完了** (`ok: true` 相当) |
| 具体的な指摘 (`[P1]`/`[P2]` 等) あり | Claude Code が修正 → ステップ 2 を再実行 |
| `bwrap: ...` / "could not inspect" | bypass フラグ忘れ。コマンドを見直す |
| `401 Unauthorized` / hang on `wss://api.openai.com/v1/responses` | 認証切れ。下記トラブルシュート参照 |

反復上限は **5 回**。2 回連続でテスト/リンタ失敗が続く場合も停止し、
未解決として状況を報告する。

## Troubleshooting

### `Permission for this action has been denied. ... "Create Unsafe Agents block rule"`

`~/.claude/settings.json` の `permissions.allow` に下記を追加:

```json
"Bash(codex exec review --dangerously-bypass-approvals-and-sandbox:*)"
```

最小権限の観点で `codex *` のような広い rule にはしない。

### `401 Unauthorized` または接続 hang

OpenAI auth token が期限切れ。Claude Code は interactive command を直接
実行できないため、user に依頼する:

```
! codex login
```

(`!` prefix は Claude Code セッション内で interactive shell command を
実行する仕組み。完了後にこの skill を再開する)

### Codex 出力が空のまま数分動かない

`ps -ef | grep codex` で CPU 0% かを確認。0% で stuck している場合は
ほぼ確実に **認証問題** か **API レート制限**。`401` セクションを参照。

### bypass を使いたくないケース (kernel 設定で根本対応)

OrbStack なら OrbStack 側、それ以外なら host の Linux で:

```bash
sudo sysctl kernel.unprivileged_userns_clone=1
```

を有効化すれば bubblewrap が動作する。ただし host 設定の変更権限が必要。

## Optional: structured JSON output

`--uncommitted` と PROMPT は併用不可だが、特定 commit や branch 相手なら
PROMPT で出力スキーマを指定可能:

```bash
codex exec review \
  --dangerously-bypass-approvals-and-sandbox \
  --base master \
  --title "..." \
  "$(cat <<'PROMPT'
出力は JSON 1 つのみ。スキーマ:
{
  "ok": true|false,
  "phase": "arch|diff|cross-check",
  "summary": "string",
  "issues": [
    {"severity": "blocking|advisory", "category": "correctness|security|perf|maintainability|testing|style", "file": "path", "lines": "N-M", "problem": "...", "recommendation": "..."}
  ],
  "notes_for_next_review": "string"
}
ok: blocking が 0 件なら true。
PROMPT
)"
```

structured output は CI 統合や反復ロジックの自動化に便利。

## Error handling

Codex exec が失敗 (timeout / API 障害 / その他) の場合:

1. **1 回リトライ** (timeout の場合はファイル数を半分に分割して `--commit`
   や `--base` で範囲を絞る)
2. 再失敗 → 該当フェーズを **スキップ** し、最終レポートに「未レビュー」
   として理由を記録
3. arch をスキップした場合は diff のみで続行。diff をスキップしたファイル群
   は手動レビュー推奨

## Final report

レビュー完了時、以下を含む短いレポートを返す:

```
## Codexレビュー結果
- 規模: <small/medium/large> (<N> ファイル, <M> 行)
- 反復: <X>/5 / ステータス: ✅ ok | ❌ unresolved
- 主な指摘と修正:
  - <file>: <修正内容の要約>
- Advisory (参考):
  - <file>: <内容>
- 未レビュー (エラー時のみ):
  - <file/scope>: <理由>
```
