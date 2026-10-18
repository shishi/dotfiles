# dotfiles

## エージェント共通指示

Claude Code と Codex の共通指示は `codex/AGENTS.md` の 1 ファイルに置きます。
`claude/CLAUDE.md` は `@~/.codex/AGENTS.md` の import 1 行だけで、`~/.codex` の link を
`setup.sh` が作ることが前提です。Claude Code はユーザーレベルの `AGENTS.md` を直接読まないため、
この import が必要です。

情報は重要度ではなく、使うタイミングと役割で配置します。

| 内容 | 正本と読込のタイミング |
|---|---|
| 全作業に共通する判断・応答・権限の規則 | `codex/AGENTS.md`。両エージェントで常時参照 |
| イベント処理と機械的な実行前ガード | `agent-shared/hooks/`。登録したイベントで実行 |
| 特定作業の手順・検証方法 | 各 `skills/<name>/SKILL.md`。該当作業で読む |
| 個人の価値観・環境の観測・プロジェクト制約 | private の `agent-memory`。索引から関連本文を取得 |

`task-policy.sh` と `wording-policy.sh` は両エージェントの `UserPromptSubmit` で短い要点を
渡します。詳細規則を hook に重複定義しません。自然言語の注入と、実行を拒否するガードは
別の役割です。skill や記憶を読んでも、新しい権限や依頼範囲は生まれません。

レビューは `review-gate`、全件調査は `investigation-discipline`、必要なテストの作成は
`test-red-first` に集約します。作業全体へ固定の承認段階・反復回数を課す superpowers は、
Claude では plugin 本体、Codex では配布中の各 skill を名前で無効にします。
Codex の remote plugin はインストールを維持し、更新で skill が追加された場合は対象を見直します。
委譲を重複制御する Claude Herdr plugin も無効にし、自作の手順を使います。
Herdr の明示操作は `herdr`、Claude からの委譲は `codex-delegate` が担当します。

GitHub 投稿は `github-writing`、Scoop manifest の更新は `scoop-manifest`、Windows の GPU
調査は `windows-gpu-diagnostics` で扱います。再利用する手順を記憶へ重複保存せず、
端末固有の制約や観測値だけを private 記憶に残します。

## エージェント間の委譲とレビュー

別のモデルの調査・実装や独立した確認が必要なとき、最上位の司令塔が CLI をまたいで
担当を割り当てます。同じ CLI 内の子エージェントも使い、短い操作は司令塔が処理します。
調査・変更・検証を一まとまりで渡し、受託側から別 CLI へ送り返しません。

| 呼出元 | 探索・定型変更・実装 | 独立レビュー |
|---|---|---|
| Claude Code | [codex-delegate](claude/skills/codex-delegate/SKILL.md) | [codex-review](claude/skills/codex-review/SKILL.md) |
| Codex | [claude-delegate](codex/skills/claude-delegate/SKILL.md) | [claude-review](codex/skills/claude-review/SKILL.md) |

通常の CLI 直接起動に加えて、これらの skill が担当範囲・権限・構造化結果・実物の照合を
定めます。自動選択のほか、Claude Code では `/codex-delegate`、Codex では
`$claude-delegate` のように明示できます。レビュー観点・必要な結果・代替条件は
[review-gate](codex/skills/review-gate/SKILL.md) が管理します。

両 CLI の認証と、CLI 自身の通信・状態保存を許可した実行環境が必要です。
委譲時の秘密情報検査に gitleaks、結果処理に jq、Codex の枠取得に Python 3 を使います。
skill と共通 helper は既存の `setup.sh` のリンクから配備されます。
CLI の実績は `${XDG_STATE_HOME:-$HOME/.local/state}/agent-runs` の JSONL に保存します。
応答本文を含めず、取得できた使用量と実検証結果を担当選択に使います。
利用枠の取得失敗は不明として扱い、呼出回数を残量に換算しません。

## 検査後に回答を表示する CLI

`codex-verified.sh` は Codex の作業出力と回答草稿を保持し、Claude が依頼・実行証拠・
回答を照合した後に、検査を通った回答だけを表示します。未達なら同じ Codex セッションで
作業を続けます。検査失敗時には草稿を表示しません。

```sh
bash ~/.agent-shared/bin/codex-verified.sh '実行する依頼'
```

Codex と Claude Code の既存のサブスクリプション認証、gitleaks、jq、Python 3.11 以降が必要です。
既存の実行ガードと承認を維持します。この入口は非対話 CLI 用で、標準 Desktop 画面や
通常の対話 CLI の表示を置き換えません。

## 個人記憶の参照

記憶本文は private repo `agent-memory` に置き、両エージェントの `memory/` から参照します。
セッション開始時は他端末の変更を同期し、索引・共通方針・現在のプロジェクト記憶を読み込みます。
同期は既存の書き込みロックを共用し、通信待ちは3秒で打ち切ります。書き込み中・未保存の変更・
通信失敗などで同期できなければ、未同期の表示とともにローカルの確定済み記憶を読み込みます。
各ユーザー入力の前に hook がローカルの確定済み索引を必ず添付し、関連する本文を渡します。
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
