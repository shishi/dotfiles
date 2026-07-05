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

Codex CLI を独立レビュアーとして使い、作業中のエージェント自身が書いた変更を
検証するレビューゲート。指摘が無くなる (clean) まで review→fix→re-review を反復する。

## モード選択

| マイルストーン | モード | 目的 |
|---|---|---|
| spec / PRD / plan / 設計ドキュメントの作成・更新直後 | **adversarial** | 設計判断・前提・トレードオフへの挑戦 |
| major 実装ステップ後、commit / PR / merge / release 前 | **native** | 実装欠陥の検出 |

## Prerequisites

1. `codex` CLI が PATH にある (`which codex` → 0)。無ければこの skill は
   適用不可。AGENTS.md の Review gate に従い、claude-review skill が使える
   ならそちらへ、どちらも不可ならホストエージェント自身のレビューで代替する
2. Codex が認証済み (`401 Unauthorized` を返さない)
3. sandbox が使えない環境で bypass フラグ付きの内側 `codex exec` を起動する
   には、外側セッション側の許可が要る。対応物は `~/.codex/config.toml` の
   `sandbox_mode` 設定 (例: `sandbox_mode = "danger-full-access"`、または
   `[sandbox_workspace_write] network_access = true` で内側の API 通信だけ
   許可)。最小権限の観点で常用せず、必要なプロジェクト/セッションに限定する

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
- sandbox が正常に動く環境では `--dangerously-bypass-approvals-and-sandbox`
  を外す (adversarial モードも同様。下記「bypass フラグを使う理由」参照)

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

- Codex の Linux sandbox は **bubblewrap** に依存し、unprivileged user
  namespaces を必要とする
- OrbStack devcontainer / 多くの Docker container ではこれが使えず
  `bwrap: No permissions to create a new namespace` で失敗する
  (`--sandbox read-only` 等も全て同じ失敗)
- bubblewrap は Linux 専用のため Windows では使われない。Windows で sandbox
  が機能しない場合は bwrap エラーではなく別様態の失敗になる
- container やローカルマシン自体が隔離・信頼境界を提供している場合に限り
  bypass する

## 反復

- 指摘があれば作業エージェント自身が修正し、同じモードで再実行する
- **回数上限は無し。clean になるまで反復する**
- **膠着判定で停止**: 同一指摘が 2 回連続で解消できない、またはテスト/
  リンタ失敗が 2 回連続した場合は反復を止め、未解決事項として user に報告する
- clean の判定: native は "I did not find a discrete defect" 相当の結論、
  adversarial は "safe" 相当の結論

## Troubleshooting

### 内側の `codex exec` が approval / sandbox に拒否される・API に届かない

`~/.codex/config.toml` の sandbox 設定を確認する。`sandbox_mode =
"workspace-write"` の既定では network access が遮断され、内側の Codex が
API に到達できない。`[sandbox_workspace_write] network_access = true` か
`sandbox_mode = "danger-full-access"` で許可する。

### `401 Unauthorized` または接続 hang

OpenAI auth token が期限切れ。interactive command は実行できないため
user にターミナルでの `codex login` 実行を依頼し、完了後にこの skill を
再開する。

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
