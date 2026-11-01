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
| イベント処理と実行前ガード | `agent-shared/hooks/`。登録したイベントで実行 |
| 特定作業の手順・検証方法 | 各 `skills/<name>/SKILL.md`。該当作業で読む |
| 個人の価値観・環境の観測・プロジェクト制約 | private の `agent-memory`。索引から関連本文を取得 |

`task-policy.sh` と `wording-policy.sh` は両エージェントの `UserPromptSubmit` で短い要点を
渡します。詳細規則を hook に重複定義しません。自然言語の注入と、実行を拒否するガードは
別の役割です。skill や記憶を読んでも、新しい権限や依頼範囲は生まれません。

Bash の実行前には `agent-shared/hooks/command-judge.sh` が、独立した判定役の AI にコマンドを判定させます。
判定するのは次の 2 点です。判定基準は `agent-shared/hooks/command-judge-prompt.md` にあります。

- 実行するとエージェント自身がこのマシンで作業を続けられなくなるか (再起動・シャットダウン、ログオフ、
  ネットワークの切断、エージェント自身のプロセスの終了など)。利用者の最新のメッセージがその効果を明示的に
  求めていなければ止めます。
- GitHub などへ投稿する本文を、実行前からあるファイルから読ませているか。sandbox の有無で一時ディレクトリが
  変わると、同じパスで別の残骸ファイルが読まれても投稿は失敗しないため、本文をコマンドの中に書いて標準入力から
  渡すよう求めて止めます。

コマンドの語の照合や構文解析はしません。変数や入れ子のシェルで同じ効果を起こす書き方も、何が起きるかで
判定させるためです。判定役には、シェルの種類、コマンド、作業エージェントが述べた目的 (Claude の `description`。
Codex の hook 入力には無い)、利用者の最新のメッセージ (UserPromptSubmit で `--record-prompt` が保存) を
データとして渡します。

- 判定役は両エージェントとも `codex exec` (gpt-6-luna、推論 high、読み取り専用、ツール無効) です。Claude Desktop
  のセッションから起動した子の `claude -p` は認証できない (Windows、Claude Code 2.1.302 で確認) ため、Claude 側でも
  codex を使います。新しいコマンドごとに判定役の応答を待ち、判定 1 件ごとに Codex の利用枠を使います。Windows で
  5 件を並行して判定したときは 1 件あたり 6〜12 秒でした。判定役の応答期限は 25 秒で、失敗時の確認 (12 秒) と
  後始末を含めても hook の timeout (60 秒) に収まります。判定役の認証は `codex login` で選んだものだけを使い、
  環境変数の API キーには切り替えません。
- Claude のセッションでは、判定役 (OpenAI) へ送る前に gitleaks で秘密情報を検査します。コマンドか目的の説明に
  見つかれば送らずに実行してよいか利用者に確認し、利用者のメッセージに見つかればそのメッセージを保存しません。
  Codex のセッションでは、同じ内容が既に Codex のモデルに渡っているため検査しません。
- 委譲・レビューの skill (codex-delegate、codex-review、claude-delegate、claude-review) と検証用の入れ子の
  `claude -p` は、子セッションに環境変数 `AGENT_DELEGATED_SESSION=1` を付けます。その子セッションでは、
  エージェントが書いた依頼文を利用者の依頼として扱いません。herdr のペインで起動した子は利用者も直接入力するため
  付けません。そこへエージェントが送った依頼文は、利用者の依頼として判定役に渡ります。
- 2 点とも該当しないと判定したコマンドは、判定基準・シェル・コマンド・目的の説明の SHA-256 をキーに 24 時間
  再利用します。保存先は `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/command-judge-<UID>` (0700) です。
- 判定役を動かせない (codex・python・jq が無い、Claude のセッションで gitleaks が無い、hook の入力や状態
  ディレクトリを扱えないなど) ときは、判定せずに通したことを警告します (同じ原因は 10 分に 1 回)。止めると、
  ガード自身がエージェントの作業を止めてしまうためです。
- 判定に失敗した (timeout、codex exec の失敗、出力を読めない) ときは、判定役に簡単な問いを 1 つ送って、判定役
  そのものが動くかを確かめます。答えなければ、ログイン切れ・利用枠切れ・通信断など全コマンドに共通の障害として、
  判定せずに通したことを警告します (この警告も同じ原因は 10 分に 1 回)。その後 1 分間は判定を試さずに通し、
  止まった判定役を毎回待たないようにします。答えれば、Claude では実行してよいか利用者に確認し、Codex ではその
  コマンドを止めます (Codex の PreToolUse は `ask` を受け付けず、hook の失敗としてコマンドを通してしまうため)。
  再実行すれば判定し直すので、一時的な失敗ならそこで判定が得られます。書き換えても、判定が得られない限り同じ
  扱いです。
- hook の内容を変えたら、Codex では `/hooks` で承認し直す必要があります。

Bash の実行後には `agent-shared/hooks/outward-write-readback.sh` が、`git push` と `gh pr|issue create|edit|comment`
を検出し、送信先の実物を取得した結果だけを知らせます。検出するのはコマンドの位置に直接書いた呼び出しだけで、
別のシェルへ渡した文字列の中、PowerShell の構文、`gh api` は見ません。起動できる python が無い、検出処理が失敗した、
コマンドを解析できないときは、確認していないことを知らせます。

設計・計画・実行・調査・テストは、両エージェントで有効な superpowers の対応手順を使います。
[superpowers-local](codex/skills/superpowers-local/SKILL.md) が、目的・設計 → 作業場所 → 計画 →
実装・検証 → 独立レビュー → 証拠確認・commit → 統合・後片付けの順序と通過条件を定めます。
着手時と工程の切替時に適用し、既存の承認範囲で進めます。上流の配布物は編集せず、plugin 管理機能で更新します。
原因調査は `investigation-discipline`、テスト作成は `test-red-first` が固有要求を補います。
独立レビューの運営は `review-gate` が担います。依頼側は `requesting-code-review`、指摘受領側は
`receiving-code-review`、完了を主張する担当は `verification-before-completion` を各段階で使います。
同じ工程を重ねず、独立レビュー、
指摘の検証、完了前の証拠確認を維持します。
Claude は marketplace の本体を有効にし、Codex は現行 remote 版を使います。
旧 `openai-api-curated` 版の無効設定は、古い配布物を併用しないために残します。
plugin の更新は起動時の標準機能を使います。Claude は `FORCE_AUTOUPDATE_PLUGINS` と各 marketplace の
`autoUpdate` を有効にし、CLI 本体の自動更新や不要な通信の抑止は維持します。
Claude の更新は対話セッションの最初の入力後、最大10分の待ち時間を挟んで実行されます。
Codex は app-server 起動時に Git marketplace と remote plugin を更新します。
通常の shell wrapper は `--no-daemon` を渡すため、CLI 起動ごとにこの処理が走ります。
更新はバックグラウンドで行われ、取得した版は次の起動や再読込で適用される場合があります。
失敗した場合は既存の配布物で作業を続け、更新を確認済みとは扱いません。
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

`codex-verified.sh` は作業前に Claude が元の依頼から要件を抽出し、Codex の作業後に
別の検査コンテキストで各要件と実行証拠・回答を照合します。goal の完了状態や
テストの成功件数だけを達成の証拠にしません。要件の欠落や未検証がある判定は通しません。
未達なら同じ Codex セッションで1回だけ修正し、再検査します。通過した回答だけを
1回表示します。再検査でも未達の場合や検査失敗時には、草稿を表示せず停止します。
作業中に加えたファイルの変更は自動で取り消しません。

```sh
bash ~/.agent-shared/bin/codex-verified.sh '実行する依頼'
```

Codex と Claude Code の既存のサブスクリプション認証、gitleaks、jq、Python 3.11 以降が必要です。
既存の実行ガードと承認を維持します。この入口は非対話 CLI 用で、標準 Desktop 画面や
通常の対話 CLI の表示を置き換えません。対話画面の Stop hook は回答を表示した後に動き、
block しても表示済みの回答は残るため、表示前の検査には使えません。

## 個人記憶の参照

記憶本文は private repo `agent-memory` に置き、両エージェントの `memory/` から参照します。
セッション開始時は他端末の変更を同期し、共通方針と現在のプロジェクト記憶を読み込みます(Codex は索引も)。
Claude Code は hook 出力 1 つあたりの文字数上限に収めるため、共通方針とプロジェクト記憶を別の hook で渡します。
プロジェクト記憶の hook は同期を待たずに読み、同期でプロジェクト記憶が変わった場合は共通方針の hook が取得し直すよう伝えます。
同期の通信は書き込みロックの外で行って3秒で打ち切り、更新があったときだけロックを取って反映します。
書き込み中・未保存の変更・通信失敗などで同期できなければ、未同期の表示とともにローカルの確定済み記憶を読み込みます。
新しい記憶は commit 後から自動で検索対象になります。Python 3 と既存の Git・jq が必要です。

各ユーザー入力の前に、hook がローカルの確定済み索引と語句検索の候補のパスを添付します。この hook は本文を渡しません。
エージェントは索引から必要な記憶を選び、下の手動検索か、表示された commit と索引のパスを指定した `git show` で本文を取得します。
候補は索引のタイトル・説明、ファイル名・見出し・本文との語句一致で選び、現在のプロジェクトも順位に使います。
語句一致なので、関連する記憶をすべて候補に挙げる保証はありません。索引は一致がない場合も毎回添付します。
起動時に全文を渡した記憶は、同じコンテキストで同じ版なら既読として示します。再開・圧縮時はこの記録をリセットします。

手動検索は1回につき上位3ファイル・本文合計16,000文字までの本文を返し、上限で取得しなかった候補はパスを示します。
索引の相対パスを渡すと、語句の順位によらずその記憶を取得します。手動検索は既読の記録で本文を省きません。
追加検索は対象・操作・制約の語で絞ります。

原則は全文取得です。共通条件を冒頭に置き、各 `##` 節だけで適用できる技術リファレンスは、
frontmatter に `retrieval: sections` を付けると一致した節と共通条件を取得します。
共通条件への一致・節を特定できない場合は全文を取得します。
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
