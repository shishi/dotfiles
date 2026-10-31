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

実行前ガード (`reboot-guard.sh`・`control-loss-guard.sh`・`gh-body-file-guard.sh`) と、実行後に push・gh の
書き込みを確かめる `outward-write-readback.sh` は、以前の判定 (b337715 のガードの判定コード) と構文木の判定を
合わせて使います。以前の判定は `agent-shared/hooks/lib/head_judge.py` に判定のソースを 1 文字も変えずに写してあり、
`agent-shared/hooks/lib/head-judge-cases.py` が b337715 の本文と一致することを照合します。入力は以前と同じく
jq が出す UTF-8 のバイト列にし、NUL と末尾の改行を除いて、同じ環境の既定の符号化 (Windows では cp932、
UTF-8 モードなら UTF-8) で読ませます。

以前の判定の読み方は hook ごとに違います。再起動と操作不能化のガードは、ヒアドキュメントの本文の行も含め、
各行をコマンドとして読みます。gh の本文渡しのガードは、ヒアドキュメントの本文を除き、コマンドの位置にある `gh` から
次の区切りまでの語をつないで、正規表現で `--body-file` を探します。readback は、ヒアドキュメントの本文を除き、
コマンドの位置にある `git`・`gh` の呼び出しを集め、その語に `push` や `gh pr create` 等を照合します。

判定は次の順で合成します。

1. 以前の判定が対象を見つけたら止めます。理由には以前の判定の読み方を書きます。再起動のガードの以前の判定は、
   対象を見つけた場合と bash -c 等の入れ子が 4 段を超えた場合を区別しないので、「入れ子が 4 段を超えた場合も
   含む」と書きます。操作不能化のガードは、入れ子が 4 段を超えて止めた場合はそう書きます。
2. 以前の判定がコマンドを分割できない (shlex が引用符の対応を取れない) ときは、以前と同じく止めます。コマンドを
   書き換えて判定し直すことはしません。理由には、以前の判定が閉じられなかった引用符が何行目のどの文字か
   (`bash -c` 等の文字列の中ならその文字列も)、または末尾の `\` を書き、避け方を添えます。行は元のコマンドの行で
   数えます (gh と readback は本文を除いてから読みますが、行番号は元の行に戻します)。避け方には、3 つのガードを
   どれも通る書き方を示します。本文の引用符が対になる書き方にするか、引用符を使わない書き方にします。例として、
   本文に `"` が無ければ `-m "$(cat <<'EOF' … EOF)"` や `--body "$(cat <<'EOF' … EOF)"` (以前の判定はこれを
   1 語として読みます)、`--shell powershell` では本文に `"`・`$`・バッククォートが無ければ `-m @"…"@` を示します。
   git の本文は、ファイル編集のツールで書いたファイルを `-F` で渡しても通ります。ファイルを書くだけなら、
   シェルではなくファイル編集のツールを使います。
3. 以前の判定に対象が無いとき、構文木の判定が対象を見つけたら止めます。以前の判定が見逃す形を塞ぐ分です。
4. それ以外は通します。

以前の判定はそのまま実行し、その結果を置き換えません。以前の判定が止めるもの (分割できないものを含む) は
すべて止め、構文木の判定は止めるものを足すだけです。

構文木の判定は、以前の判定が見逃す次の形を読みます。bash は shfmt、PowerShell は pwsh 7 (PATH と既知の場所の
どちらにも無いときだけ powershell.exe 5.1) の構文解析器で読みます。

- 起動されるコマンドを構文木全体から集めます。コマンド置換 (二重引用の中を含む)・`${ cmd; }`・`"${x:-'$(cmd)'}"`、
  未引用のヒアドキュメントの中の `$(...)`、コメントと区別した URL の `#` の後ろ、行継続や `$'…'` で作る語を読みます。
- 前置きを剥がします: `sudo`・`doas` の値を取るオプション、`env -S`、`su -c`、`timeout`、`nix develop`/`nix shell` の
  `-c`、`docker`/`podman exec`、`pkexec`、`setsid`、`wsl`。
- 文字列を別のシェルで実行する引数を読み直します: シェルの `-c` (`-c --` を含む)、`eval`、`trap`、`ssh` の遠隔コマンド、
  `pwsh -Command`/`-EncodedCommand`、`powershell.exe` の位置引数、`iex` の引数、`cmd /c` (cmd の構文を bash として近似)。
- 本文がそのまま bash 系シェル (`bash`・`sh`・`zsh`) のスクリプトになるヒアドキュメントを読みます。受け手は引数なしの
  シェル・`-s`・`/dev/stdin`・`source /dev/stdin` と、`cat <<'EOF' | bash` の形です。以前の gh の判定が本文を除くためです。
- `Start-Process` の FilePath と、引用した 1 つの文字列の ArgumentList を、PowerShell の束縛と Windows の引数の規則で読みます。
- 再起動の判定では `shutdown //r` と大文字の `.EXE` も見ます。gh の判定では `--body-file=x` と `-F x` も見ます
  (値を取るオプションの値は見ず、`--template` をファイルとして見るのは `gh pr create` だけです)。
- 構文エラーのテキストは構文木では読みません (以前の判定が別に全体を読みます)。

読まないものは次のとおりです。引用した引数の中身 (`echo 'reboot' | sh` の `reboot`)、ファイル経由で実行する
中身、値が実行時に決まるコマンド名 (`$cmd`)、エイリアス・関数経由の呼び出し。関数定義の本体は、呼ばれるかに
関係なく数えます。構文木で読み直す入れ子は 6 段まで、読み直す文字列・本文は 1 回の判定で 64 個までで、超えた分は
構文木では読みません。`wsl`・`docker`/`podman exec`・`pkexec` の値を取るオプションは主なものだけを知っています。
それ以外のオプションの値は、コマンド (`docker`/`podman exec` ではコンテナ名) として読み違えることがあります。

以前の判定の誤検知もそのまま残ります。例: `command -v reboot`、任意のヒアドキュメントの本文にある `reboot` の行、
gh の `--body "--body-file x"`、再起動と操作不能化のガードでヒアドキュメントの本文に対にならない `'` がある形
(`cat <<'EOF' > note.txt` の本文の `don't` など。以前の判定は本文の行もコマンドとして読むため、分割できずに止めます)。

これは hook が timeout (10 秒) 内に終わる場合の保証です。構文解析の締切は 1 回の判定全体で 6 秒です。締切を
超えたら、3 では足すものが無いものとします。1 と 2 は構文解析器を使わないので、締切に関係なく以前どおり止めます。

Codex は Windows で PowerShell を使うため、`codex/hooks.json` の `commandWindows` で `--shell powershell` を渡します。
hook の入力にはシェルの種別が無く、Codex は呼び出しごとに別のシェルを選べます。そのため構文木では外側を
PowerShell と bash の両方として読み、外側を bash として読むと対象の操作を実行する形は、PowerShell の構文木で
見つからなくても止めて、理由にそう書きます。

Python 3 と jq に加えて shfmt が必要です。shfmt が見つからないときは bash の構文木を読めないので、3 では
何も足さず (`--shell powershell` では PowerShell の構文木だけを読みます)、止める理由と通知に導入状況を書きます。
このときは nix・scoop・brew のいずれかでバックグラウンド導入を始めて通知します。
導入に失敗したら 60 分は再試行しません。導入中かは、導入を担う子プロセスが持つ OS の排他ロックで判定します。
PowerShell は自動導入しません (Windows には powershell.exe が常にあります)。
readback は、push・gh の書き込みの判定を済ませた後で、解析器が使えない等で検出が完全でなかったことを
10 分に 1 回知らせます。検出処理の出力を読めなかったときも、確認していないことを 10 分に 1 回知らせます。
python があっても起動できない (Microsoft Store の別名など) ときは、python が無いときと同じく、
gh の本文渡しと readback は判定せずに通して通知し、再起動と操作不能化のガードは理由を書いて止めます。
導入の状態とログは `${XDG_STATE_HOME:-$HOME/.local/state}/agent-guards` に置きます。

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
