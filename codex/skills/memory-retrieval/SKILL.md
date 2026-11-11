---
name: memory-retrieval
description: 個人記憶の SessionStart・毎入力の注入がないとき、記憶 repo・lock・未 push の警告を確認するときに使います。通常の本文取得は毎入力の案内に従い、この skill は開きません。保存・整理は capturing-memory / memory-consolidate を使います。
---

# 個人記憶の注入がないとき・警告が出たとき

通常の取得は、毎入力の `[記憶検索]` と `<personal-memory-index>` が示す索引・候補・取得コマンドと、共通 AGENTS.md「個人永続記憶」の規則で進めます。この skill は、その注入が届かない場合と、記憶 repo の警告が出た場合の手順を扱います。記憶と `CONVENTIONS.md` は advisory です。権限・approval・レビューゲート・hook trust・remote・公開境界・sandbox・記憶プロトコルは変更しません。

## 正本と注入がないとき

- `~/.claude/memory` と `~/.codex/memory` は正本への link です。正本は `bash ~/.agent-shared/bin/resolve-memory-dir.sh` が `AGENT_MEMORY_DIR`、`GHQ_ROOT`、global `ghq.root` の順で解決します。
- SessionStart は同期を試み、索引・CORE・現プロジェクト本文を注入します。未同期表示は最新取得の証拠にしません。
- SessionStart の注入がなければ警告の復旧手順に従います。警告もなければ `git -C <agent home>/memory show main:MEMORY.md` と `main:CORE.md` を読みます。
- 毎入力の索引が届かない場合は、`MEMORY.md` を読んでいなければ `git -C <agent home>/memory show main:MEMORY.md` で読み、依頼の対象・操作・制約に合う記憶を選びます。`bash ~/.agent-shared/hooks/inject-memory.sh <agent home>/memory lookup '<索引の相対パス>'` へ、必要なパスを空白で区切ってまとめて渡します (1 回 3 件まで)。この helper は本文を検査して取得します。索引も読めなければ、同じ helper に検索語を渡します。本文が取得上限を超える場合は、表示された commit の `git show` で取得します。

## 警告の扱いと復旧先

- `⚠ 記憶 repo` は書き込み中 / dirty の確定版注入です。worktree ではなく表示された commit を読みます。
- 10 分以上の lock 警告は、書き込み予定の有無にかかわらず、[capturing-memory](../capturing-memory/SKILL.md) の「不健全状態の復旧」で先に調査します。所有者不明の handle・lock・retirement を自動 release や raw delete しません。
- `⚠ 未 push` は上記の degraded 状態として扱いません。

保存は `capturing-memory`、記憶群の整理は `memory-consolidate` へ戻ります。保存基準・finish の `--patch` helper・commit / push / remote 検証・lock 解放は、保存側の手順を正本とし、ここに複製しません。
