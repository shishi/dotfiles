# dotfiles

## エージェント共通指示

Claude Code と Codex の共通指示は `codex/AGENTS.md` の 1 ファイルに置きます。
`claude/CLAUDE.md` は `@~/.codex/AGENTS.md` の import 1 行だけで、`~/.codex` の link を
`setup.sh` が作ることが前提です。Claude Code はユーザーレベルの `AGENTS.md` を直接読まないため、
この import が必要です。

## 個人記憶の参照

記憶本文は private repo `agent-memory` に置き、両エージェントの `memory/` から参照します。
セッション開始時は他端末の変更を同期し、索引・共通方針・現在のプロジェクト記憶を読み込みます。
同期は既存の書き込みロックを共用し、通信待ちは3秒で打ち切ります。書き込み中・未保存の変更・
通信失敗などで同期できなければ、未同期の表示とともにローカルの確定済み記憶を読み込みます。
各ユーザー入力の前に hook がローカルの確定済み索引を必ず添付し、関連する本文を渡します。
この hook は、不明点を自分で調べてから実行・検証・後片付けを進め、元要件の未達には再指示を待たず是正する作業順序も毎回渡します。
規則は検索が 0 件の場合や記憶本文が既読で省略される場合も注入します。
新しい記憶は commit 後から自動で検索対象になります。Python 3 と既存の Git・jq が必要です。

自動取得は1入力につき上位3ファイル・本文合計16,000文字です。索引はこの本文上限に含めません。
索引のタイトル・説明、ファイル名・説明・見出しに一致する候補を自動取得し、現在の
プロジェクトも順位に使います。本文だけの一致は候補のパスを示し、索引から関連性を判断します。
既読の枠を下位候補で埋めません。同じコンテキストで
同じ版を繰り返し渡さず、再開・圧縮時は取得履歴をリセットします。検索は語句一致なので、
関連情報をすべて取得する保証はありません。上限で取得しなかった候補はパスを示します。
索引は一致ゼロ・本文が既読の場合も毎回添付します。必要な本文は表示された commit と
索引のパスで取得できます。追加検索は対象・操作・制約の語で絞ります。
手動検索は本文だけの一致も取得対象に含め、既読抑制せず上限内の本文を返します。

原則は全文取得です。共通条件を冒頭に置き、各 `##` 節だけで適用できる技術リファレンスは、
frontmatter に `retrieval: sections` を付けると一致した節と共通条件を取得します。
既読も節単位で管理します。共通条件への一致・節を特定できない場合は全文を取得します。
条件の欠落が疑われる文書には指定を付けません。確実な参照をコンテキスト節約より優先します。

```bash
bash ~/.agent-shared/hooks/inject-memory.sh ~/.codex/memory lookup 'gh sandbox'
```

Claude では引数の `~/.codex/memory` を `~/.claude/memory` に置き換えます。
検索に失敗すると hook は入力をブロックします。`[記憶検索]` または `<personal-memory-index>` が届かない経路では、
共通指示に従って作業前に上のコマンドを実行します。
Codex の新規・定義変更した hook は、[/hooks で内容を確認して信頼](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks)
するまでスキップされます。通常設定の trust を自動で書き換えることはしません。

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
