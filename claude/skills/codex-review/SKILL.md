---
name: codex-review
description: |
  Codex CLI をレビューエンジンとして実行するアダプタ。観点(correctness /
  adversarial)は ~/.claude/agents/ の観点ファイルから読み、codex 用前置きと
  合成して素の codex exec (stdin 渡し) で実行する。review-gate から呼ばれる、
  または /codex-review [correctness|adversarial] で明示発動(デフォルト
  correctness)。マイルストーン判断は持たない。
---

# Codex Review (engine adapter)

Codex CLI を独立レビューエンジンとして使う。観点はこの skill には無い —
`~/.claude/agents/<perspective>-reviewer.md` が単一ソース(Claude エンジンと共用)。

## モード(= 観点)

| モード | 観点ファイル | 用途 |
|---|---|---|
| correctness(デフォルト) | `~/.claude/agents/correctness-reviewer.md` | 実装欠陥の検出 |
| adversarial | `~/.claude/agents/adversarial-reviewer.md` | 設計・前提への挑戦 |

対象が spec/plan 等の文書なら adversarial を提案してから実行する。

## Prerequisites

1. `codex` CLI が PATH にある(`which codex` → 0)。無ければこの skill は適用不可
   (review-gate 経由なら gate がエンジンを Claude に差し替える)
2. Codex が認証済み(`401 Unauthorized` を返さない)
3. **secrets-scan を先行させ、検出ゼロを確認してから codex に送る**(単独発動でも必須。
   secrets 入りの内容を外部 API に送らない。gitleaks 不能なら停止してユーザーへ報告)
4. sandbox が使えない環境では `~/.claude/settings.json` の `permissions.allow` に
   `Bash(codex exec --dangerously-bypass-approvals-and-sandbox:*)` が必要。
   sandbox が正常に動くホストでは bypass 無しの形を使い、この広い grant を置かない

## 実行手順(プロンプト合成の機構 — 変えない)

観点本文にはバッククォートや `$` が含まれるため、シェル文字列へのインライン埋め込みは
禁止。必ず一時ファイル + stdin で渡す:

1. 観点ファイル(`~/.claude/agents/<mode>-reviewer.md`)を Read し、2 つ目の `---` までの
   frontmatter を除去して観点コアを得る
2. 下記の codex 前置き + 観点コアを、**リポジトリ外**の一時ファイル
   (例: `$TMPDIR/codex-review-prompt.md`。repo 内に置くと untracked としてレビュー対象に
   混入する)に Write ツールで書く
3. 実行(stdin 渡し。`$(cat ...)` のコマンド置換形は permission の prefix マッチに
   失敗しうるため使わない):
   ```bash
   codex exec --dangerously-bypass-approvals-and-sandbox - < "$TMPDIR/codex-review-prompt.md"
   ```
4. 実行後に一時ファイルを削除する

### codex 前置き(観点コアの前に置く)

```text
Task under review: <変更の短い説明(あればタスク記述の逐語引用)>
Focus: <呼び出し側指定の焦点。無ければ the entire change>
Inspect the changes yourself: run `git status --short --untracked-files=all` and
`git diff HEAD`, and read the full content of untracked files. The review target is
the combination of that diff and those untracked files.
The perspective definition follows. Follow its 出力形式 and 制約 exactly.
---
```

## 反復と clean 判定

- **review-gate 経由では 1 パスのみ**(反復ループ・修正適用・引用検証は gate の責務)
- **単独発動時のみ**この skill が反復を回す: 指摘の引用を検証(引用不一致は棄却・記録)→
  blocker/should を修正 → secrets-scan → 同モード再実行。clean 判定:
  correctness = blocker/should ゼロ(note は任意対応)/ adversarial = safe 相当の結論
- 膠着判定: 同一指摘 2 回連続未解消、またはテスト/リンタ失敗 2 回連続 → 停止して
  ユーザーへ報告

## bypass フラグを使う理由

- Codex の Linux sandbox は bubblewrap に依存し、unprivileged user namespaces を
  必要とする。OrbStack devcontainer / 多くの Docker container ではこれが使えず
  `bwrap: No permissions to create a new namespace` で失敗する
- bubblewrap は Linux 専用のため Windows では使われない。Windows で sandbox が
  機能しない場合は bwrap エラーではなく別様態の失敗になる
- container やローカルマシン自体が隔離・信頼境界を提供している場合に限り bypass する
- この呼び出し形(承認なし・sandbox なしの任意プロンプト実行)は本 skill 経由に限る。
  他の用途で `codex exec --dangerously-bypass-approvals-and-sandbox` を使わない

## 規模判定

diff が巨大(目安: >10 ファイルかつ互いに独立な変更)なら、前置きの Focus で範囲を
指示して複数回に分ける。同一パターンの繰り返しなら分割不要。

## Troubleshooting

### `Permission for this action has been denied. ... "Create Unsafe Agents block rule"`

`~/.claude/settings.json` の `permissions.allow` に下記を追加:

```json
"Bash(codex exec --dangerously-bypass-approvals-and-sandbox:*)"
```

### `401 Unauthorized` または接続 hang

OpenAI auth token が期限切れ。interactive command は実行できないため user に
`! codex login` を依頼し、完了後にこの skill を再開する。

### Codex 出力が空のまま数分動かない

`ps -ef | grep codex` で CPU 0% なら、ほぼ確実に認証問題か API レート制限。
上の `401` セクションを参照。

### codex exec 自体の失敗(timeout / API 障害)

1. 1 回リトライ(timeout なら Focus で範囲を絞る)
2. 再失敗 → review-gate 経由ならエンジンを Claude に差し替え(gate の責務)。
   単独発動なら失敗として報告する

## Final report(単独発動時)

```
## Codex レビュー結果
- モード: correctness | adversarial / 反復: <X> 回
- ステータス: ✅ clean | ⚠️ 膠着で停止(未解決あり)
- 修正した指摘: [ID] と要約
- 棄却した指摘: [ID] + 理由(引用不一致 等)
- 未対応 note: [ID]
```
