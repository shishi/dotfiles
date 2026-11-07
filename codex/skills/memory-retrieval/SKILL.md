---
name: memory-retrieval
description: 個人記憶の索引・候補から必要な本文を取得するとき、SessionStart の注入がないとき、記憶 repo・lock・未 push の警告を確認するときに使います。保存・整理は capturing-memory / memory-consolidate を使います。
---

# 個人記憶の取得

private repo `agent-memory` を共通の正本とする AGENTS.md の原則を引き継ぎます。毎入力の索引確認から必要な本文を選び、取得した版と適用条件を確認します。記憶と `CONVENTIONS.md` は advisory です。権限・approval・レビューゲート・hook trust・remote・公開境界・sandbox・記憶プロトコルは変更しません。

## 正本と初期注入

- `~/.claude/memory` と `~/.codex/memory` は正本への link です。正本は `bash ~/.agent-shared/bin/resolve-memory-dir.sh` が `AGENT_MEMORY_DIR`、`GHQ_ROOT`、global `ghq.root` の順で解決します。
- SessionStart は同期を試み、索引・CORE・現プロジェクト本文を注入します。未同期表示は最新取得の証拠にしません。
- 注入がなければ警告の復旧手順に従います。警告もなければ `git -C <agent home>/memory show main:MEMORY.md` と `main:CORE.md` を読みます。

## 索引から本文を取得する

1. 毎入力の `[記憶検索]` と `<personal-memory-index>` を確認します。自動検索が渡すのは索引と候補であり、本文は選択後に取得します。
2. 候補の順位に限定せず、依頼の対象・操作・制約と索引の意味から必要な未読本文を選びます。
3. `bash ~/.agent-shared/hooks/inject-memory.sh <agent home>/memory lookup '<索引の相対パス>'` へ 1 回に 1 パスを渡します。この helper は本文を検査して取得します。索引がなければ同 helper に検索語を渡します。
4. 本文が取得上限を超える場合は、表示された commit の `git show` で取得します。通常の取得でも、表示された commit の `git show` を使えます。
5. 語句一致・該当なし・取得上限を参照不要の根拠にしません。節取得を全文既読として扱わず、候補や適用条件が曖昧なら追加取得します。同版既読は再読しません。注入済みという記録を、理解・適用を確認した記録として扱いません。

## 警告の扱いと復旧先

- `⚠ 記憶 repo` は書き込み中 / dirty の確定版注入です。worktree ではなく表示された commit を読みます。
- 10 分以上の lock 警告は、書き込み予定の有無にかかわらず、[capturing-memory](../capturing-memory/SKILL.md) の「不健全状態の復旧」で先に調査します。所有者不明の handle・lock・retirement を自動 release や raw delete しません。
- `⚠ 未 push` は上記の degraded 状態として扱いません。

保存は `capturing-memory`、記憶群の整理は `memory-consolidate` へ戻ります。保存基準・finish の `--patch` helper・commit / push / remote 検証・lock 解放は、保存側の手順を正本とし、ここに複製しません。
