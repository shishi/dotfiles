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

応答と作業の規則は、入力のたびに hook で注入しません。常時の判断基準は共通指示 (`AGENTS.md`) にあり、
出力ゲートを有効にしたマシンでは、回答が規則一覧と既定の判定を守っているかを、最終回答の事後検査で確かめます (規則は `agent-shared/bin/output-gate-rules.json`、
仕組みは `docs/output-gate.md`)。自然言語の規則と、実行を拒否するガードは別の役割です。skill や記憶を読んでも、
新しい権限や依頼範囲は生まれません。

Bash の実行前には `agent-shared/hooks/command-judge.sh` が、独立した判定役の AI にコマンドを判定させます。
判定するのは次の 3 点です。判定基準は `agent-shared/hooks/command-judge-prompt.md` にあります。

- 実行するとエージェント自身がこのマシンで作業を続けられなくなるか (再起動・シャットダウン、ログオフ、
  ネットワークの切断、エージェント自身のプロセスの終了など)。利用者の最新のメッセージがその効果を明示的に
  求めていなければ止めます。
- GitHub などへ投稿する本文を、実行前からあるファイルから読ませているか。sandbox の有無で一時ディレクトリが
  変わると、同じパスで別の残骸ファイルが読まれても投稿は失敗しないため、本文をコマンドの中に書いて標準入力から
  渡すよう求めて止めます。
- このマシンの外へ、軽微でない、または元に戻せない影響を与えるか (共有の remote への push、pull request や
  issue の作成・更新、メッセージの送信、デプロイなど)。他者へ届く・通知される、公開される、他者が受け取った複製や
  通知が残る、他者や本番が使う状態を変える影響が該当します。情報の取得だけの通信と、取り消せば元どおりになり、
  それまでも他者へ届かず他者の作業や自動処理を動かさない軽微な変更は該当しません。
  利用者がその効果を求めても許可してもいなければ、Claude では実行してよいか利用者に確認し、Codex では止めて、
  利用者の許可を得るようエージェントに伝えます。何をどこへ行うかが分からない「いいよ」だけの返事は許可として
  扱わないため、Codex では対象を書いた許可をもらうよう伝えます。前のメッセージでの許可は、撤回・変更されず同じ
  作業が続く間は有効で、許可が対象を示していればその対象に限ります。進捗の確認や補足を挟んでも続きますが、
  別の作業や、時間が経って区切りをまたいだ作業には使いません。共通指示 (`AGENTS.md`) であらかじめ許可している
  効果 (個人記憶の保存とその記憶 repository への push、委譲・レビューのための Anthropic と OpenAI の公式サービスへの送信) は、
  判定基準にも書いてあり、毎回の許可なしに通します。

コマンドの語の照合や構文解析はしません。変数や入れ子のシェルで同じ効果を起こす書き方も、何が起きるかで
判定させるためです。判定役には、シェルの種類、作業ディレクトリ、コマンド、作業エージェントが述べた目的
(Claude の `description`。Codex の hook 入力には無い)、利用者の直近のメッセージをデータとして渡します。
利用者のメッセージは UserPromptSubmit で `--record-prompt` がセッションごとに直近 20 件まで保存し、判定役へは
古い順に何分前かを添えて渡します。最新は全文を渡します。最新以外は、12 時間より前のものを渡しません。
最新以外で 4000 文字を超えるメッセージがあれば、それとそれより前のメッセージを渡しません。一部だけを渡すと、
省いた部分にある撤回が届かないためです。同じ理由で、Claude のセッションで秘密情報の検査のためにメッセージを
省略したとき (見つかった、または gitleaks で検査できなかった) は、それより前のメッセージも消します。

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
  付けません。そこへエージェントが送った依頼文は、利用者の依頼として判定役に渡ります。依頼文に push などの
  外部への操作が含まれていれば、その子セッションでは利用者の許可として扱われ、上の範囲で続きます。
- 3 点とも該当しないと判定したコマンドは、判定基準・シェル・作業ディレクトリ・コマンド・目的の説明の SHA-256 をキーに 24 時間
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

## 出力ゲート

Claude Code と Codex の回答を、表示する前に検査します。そのターンのツールの呼び出しと結果を証拠にして、
確認していないことを確認済みと書いていないか、依頼の抜けやごまかしが無いかを判定します。
応答の規則 (共通指示の「応答」の節) の違反は、置き換えて直します。
未達があれば回答を見せずにエージェントへ指摘を返し、同じセッションで作業を続けさせて、もう一度検査します。
直させるのは 1 回までで、それでも未達なら未達の項目を回答の下に明記して表示します。
検査できなかったときは、原文の先頭に理由を添えて表示します。
検査役は、Claude Code の回答を Codex (`codex exec`)、Codex の回答を Claude (`claude -p`) で検査し、
その系統が使えなければもう一方の系統で検査します。設計と制限は [docs/output-gate.md](docs/output-gate.md) にあります。

- Claude Code: `claude/mods/output-gate/` の mod を、`claude/settings.json` の
  `CLAUDE_CODE_PLUGIN_DIRS` で全てのセッションに読み込みます。mod を使えない Desktop の
  WSL セッションでは、`agent-shared/hooks/output-gate-claude.sh` の hook が表示を置き換え、
  未達の項目を明記した回答を一度表示してから Stop hook で直させます。
  検査するかはマシンごとに次のコマンドで切り替えます (既定は無効)。WSL では WSL の中でも実行します。

```sh
bash ~/.agent-shared/hooks/output-gate-claude.sh enable
```

```sh
bash ~/.agent-shared/hooks/output-gate-claude.sh disable
```

  mod そのものを外すには、`claude/settings.json` の `CLAUDE_CODE_PLUGIN_DIRS` の行を外して起動し直します。

- Codex: ローカルの中継を、組み込みの provider の `openai_base_url` に設定して使います。
  中継を使うかはマシンごとに次のコマンドで切り替えます。行は Git に入らず、hook と Git の
  フィルターが書き戻します。

```sh
bash ~/.agent-shared/hooks/output-gate-codex.sh enable
```

```sh
bash ~/.agent-shared/hooks/output-gate-codex.sh disable
```

有効にした後と、`codex/hooks.json` を更新した後は、Codex の `/hooks` で出力ゲートの hook
(Stop・SessionStart・UserPromptSubmit) を信頼し直します。hook の内容が変わると信頼が外れるためです。
未達の回答を直させるのは、セッションの開始時に出力ゲートの Stop hook が信頼済みだと確かめて、
続行を登録したセッションだけです。登録の無いセッション (hook を信頼していない、無効にした、
hook を動かさない環境) では直させず、応答の規則の置き換えを適用した回答に未達の項目を明記して表示します。
直させる前の回答が表示されないままターンが終わった場合 (Stop hook が動かなかった、直させている途中で
中断したなど) は、保存した回答 (応答の規則の置き換えを適用したもの) と未達の項目を、同じセッションの
次の入力で一度だけ表示します。
次の入力が無い単発の `codex exec` などでは、次のコマンドで表示します。保存した回答は 24 時間残します。
`session_id` には `codex exec --json` が出す thread_id を渡し、省くと全てのセッションの分を表示します。

```sh
bash ~/.agent-shared/hooks/output-gate-codex.sh held [session_id]
```

検査役は `codex exec` (読み取り専用、ツール無効) と `claude -p` (ツール無効) で、
Codex と Claude Code のログイン、gitleaks、Python 3.11 以降が必要です。
中継の圧縮送信には Python 3.14 以降を使います。委譲とレビューで起動する Codex は中継を通さず、
検査もしません。

## 委譲・背景実行の放置の検出

背景で動かした作業があるのに、確かめる予定を立てないままターンを終えることを、hook で止めます
(`agent-shared/hooks/stall-guard.sh`)。判定には CLI が hook に渡す構造化された値と時刻だけを使います。

- Claude Code: 背景の Agent・Bash が動いている間、それぞれに 20 分以内に発火する確認の予約
  (ScheduleWakeup・CronCreate) が無ければ、Stop hook がターンの終了を止めて事実を渡します。
  モデルが予約しないまま 2 回続けて終えようとしたら止めるのをやめ、代わりに見張りの Stop hook が
  確認時刻にセッションを起こします。毎回の入力にも、動いている作業の経過時間と成果物の増分を添えます。
- Codex: そのターンで起動した子の run が終わるまで、Stop hook がターンの終了を止め、
  20 分以上の `wait_agent` を求めます。短い `wait_agent` は実行前に拒否します。
  前のターンから持ち越した run は止めず、次の入力に事実を添えるだけです。

止めないもの:

- 背景作業が無いのに、やることを残してターンを終えること。
- Codex で、指示に従わないモデルが答え直しだけを続けた場合。2 回で止めるのをやめ、次の入力で事実を渡すまでになります。
- `keep` を宣言した背景 Bash。背景 Bash で起動した委譲 (`codex exec` など) も Bash の作業なので、`keep` で確認の対象から外せます。
- Claude Code で、API エラーや中断で Stop hook が発火せずに終わったターン。見張りも仕掛からないので、次の入力まで誰も起こしません。

モデルと利用者が使うコマンドです (Claude Code の Bash から実行したときは、そのセッションの台帳を使います)。

```sh
bash ~/.agent-shared/hooks/stall-guard.sh deadline <id> <1〜30 分> [--watch <path>]  # 確認の間隔を変え、成果物を登録する
bash ~/.agent-shared/hooks/stall-guard.sh keep <id>           # 意図して動かし続ける背景 Bash を確認の対象から外す
bash ~/.agent-shared/hooks/stall-guard.sh [--cli codex] status [--json] --session <id>
```

委譲の skill (codex-delegate・codex-review・claude-delegate) は、委譲先の終了後に `status --json` を読み、
終わっていない作業を委譲の失敗として扱います。`hooked` が false なら hook が動いていないと報告します。
Codex は `codex/hooks.json` を更新した後に `/hooks` で stall-guard の hook を信頼し直します。

外すときは、先に無効にしてから予約を消し、最後に登録を外します。
無効にする前に予約を消すと、Stop hook がその時点で予約を作り直させるためです。

```sh
bash ~/.agent-shared/hooks/stall-guard.sh disable
```

1. 無効にすると、記録・入力への事実・見張りは何もしなくなり、Stop hook は予約の観測だけを書きます。
2. `status` に出る予約を、会話で CronDelete (ScheduleWakeup の予約は `ScheduleWakeup{stop:true}`。利用者の /loop など他の起床も取り消します) で消します。
3. `claude/settings.json` と `codex/hooks.json` から `stall-guard.sh` の登録を外し、状態ディレクトリ
   (`${XDG_STATE_HOME:-$HOME/.local/state}/stall-guard`) を消します。

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
