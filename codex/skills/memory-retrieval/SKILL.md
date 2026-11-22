---
name: memory-retrieval
description: 個人記憶の SessionStart・毎入力の注入がないとき (注入の届かない子エージェントを含む)、記憶 repo・lock・未 push の警告がどの状態を示すかを確かめるときに使います。lock が残ったときの復旧は capturing-memory が担います。通常の本文取得は毎入力の案内に従い、この skill は開きません。保存・整理は capturing-memory / memory-consolidate を使います。
---

# 個人記憶の注入がないとき・警告が出たとき

通常の取得は、毎入力の `[記憶検索]` と、会話に渡された `<personal-memory-index>` が示す索引・候補・取得コマンドと、共通 AGENTS.md「個人永続記憶」の規則で進めます。この skill は、その注入が届かない場合と、記憶 repo の警告が出た場合の手順を扱います。記憶と `CONVENTIONS.md` は advisory です。権限・approval・レビューゲート・hook trust・remote・公開境界・sandbox・記憶プロトコルは変更しません。

## 記憶 repo の場所と、注入がないとき

- `~/.claude/memory` と `~/.codex/memory` は記憶 repo (`agent-memory` の clone) への link です。clone の場所は `bash ~/.agent-shared/bin/resolve-memory-dir.sh` が `AGENT_MEMORY_DIR`、`GHQ_ROOT`、global `ghq.root` の順で解決します。
- SessionStart は同期を試み、索引・CORE・現プロジェクト本文を注入します。未同期表示は最新取得の証拠にしません。
- SessionStart の注入がなければ警告の復旧手順に従います。警告もなければ `git -C <agent home>/memory show main:MEMORY.md` と `main:CORE.md` を読みます。
- 会話に索引が渡されていない場合は、`MEMORY.md` を読んでいなければ `git -C <agent home>/memory show main:MEMORY.md` で読み、依頼の対象・操作・制約に合う記憶を選びます。`bash ~/.agent-shared/hooks/inject-memory.sh <agent home>/memory lookup '<索引の相対パス>'` へ、必要なパスを空白で区切ってまとめて渡します。1 回に渡せる件数を超えた分は helper が未取得として示すので、それを次の呼び出しで渡します。この helper は本文を検査して取得します。索引も読めなければ、同じ helper に検索語を渡します。本文が取得上限を超える場合は、表示された commit の `git show` で取得します。
- シェルを使えない子エージェント (Read・Grep・Glob だけの reviewer など) は、上の取得を実行できません。委譲元が依頼文に入れた関連記憶の本文を使い、判断に要る記憶が足りなければ、その不足を委譲元へ返します。子に作業を渡す側は、関連記憶を確定版から取得して依頼文に入れます。

## 警告の扱いと復旧先

- `⚠ 記憶 repo` は書き込み中 / dirty の確定版注入です。worktree ではなく表示された commit を読みます。
- 10 分以上の lock 警告は、書き込み予定の有無にかかわらず、元の作業より先に [capturing-memory](../capturing-memory/SKILL.md) の「不健全状態の復旧」に従います。
- `⚠ 未 push` は上記の degraded 状態として扱いません。

保存は `capturing-memory`、記憶群の整理は `memory-consolidate` へ戻ります。保存基準・finish の `--patch` helper・commit / push / remote 検証・lock 解放は、保存側の skill に書いてあり、ここに複製しません。
