# dotfiles

## 外部 skill の管理

自作または改変した skill は、従来どおり `claude/skills/` と `codex/skills/` で
Git 管理します。GitHub で配布されている未改変の skill は、
`managed-skills.sh` で導入・更新します。

```bash
bash ~/.agent-shared/bin/managed-skills.sh add OWNER/REPO SKILL
```

導入先を省略すると、Claude Code と Codex の両方へ導入します。片方だけへ
導入するときは、末尾に `claude` または `codex` を指定します。

```bash
bash ~/.agent-shared/bin/managed-skills.sh add OWNER/REPO SKILL claude
bash ~/.agent-shared/bin/managed-skills.sh add OWNER/REPO SKILL codex
```

`setup.sh` は登録済み skill の不足分を導入し、固定していない skill を更新します。
手動で同期するときは、次を実行します。

```bash
bash ~/.agent-shared/bin/managed-skills.sh sync
```

登録内容と導入状態は `list` で確認します。

```bash
bash ~/.agent-shared/bin/managed-skills.sh list
```

管理対象から削除するときは `remove` を使います。

```bash
bash ~/.agent-shared/bin/managed-skills.sh remove NAME
```

外部 skill を改変するときは、編集前に `fork` で Git 管理へ移します。導入先を
省略すると、現在登録されているすべての導入先を移します。

```bash
bash ~/.agent-shared/bin/managed-skills.sh fork NAME
```

`fork` は現在の内容を保持し、GitHub の更新情報と管理印を外します。skill は次の
`git status` から未追跡ファイルとして表示されます。
