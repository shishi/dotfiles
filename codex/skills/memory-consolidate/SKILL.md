---
name: memory-consolidate
description: Use when the user says 「記憶の整理」「dream」, after large refactors that invalidate stored knowledge, or roughly every 20-30 sessions when memory files accumulate duplicates, contradictions, or stale references.
---

# memory-consolidate(個人記憶の整理)

`~/.codex/memory/`(private repo)の記憶を再編し、重複・矛盾・陳腐化を除去する。

## 前提

- 対象: `MEMORY.md`(索引)、`*.md`(グローバル記憶)、`projects/*.md`(プロジェクト記憶)
- 記憶は Claude / Codex 共有(agent-memory)。詳細プロトコルは記憶 repo 直下の CONVENTIONS.md が正。
- LLM による書き換えは hallucination 混入リスクがあるため、diff レビューが安全弁。

## 開始・終了プロトコル(CONVENTIONS.md の要約)

開始(ロック取得。順序厳守):
1. local write lock: `mkdir <repo>/.git/memory-write.lock`(取れなければ中止)
2. 状態確認: `main`・clean・ahead なし
3. `git fetch --prune origin` → `git ls-remote --heads origin 'refs/heads/consolidation/*'` が**空でなければ中止**(他方が整理中/レビュー待ち)
4. `git switch -c consolidation/<YYYY-MM-DD> origin/main`
5. 一意なロック commit を積んで push: `git commit --allow-empty -m "chore(memory): consolidation lock <agent>@<host> <date>"` → `git push origin HEAD` → ls-remote でリモートが自分の commit を指すことを確認(不一致なら中止)

終了(編集・commit 後):
6. `git push origin HEAD` で整理内容を push
7. **worktree を `main` に戻し**、write lock を削除
8. ユーザーへ「ブランチ `consolidation/<date>` をレビューして」と伝える。**main へのマージはレビュー後**(マージ手順も CONVENTIONS.md に従う)

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
- [ ] consolidation ブランチを push し、worktree を main に戻し、lock を解放した
- [ ] **main にはマージしていない**(ユーザーレビュー待ちと明言した)
