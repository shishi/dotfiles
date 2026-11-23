# エージェントの設定

Claude Code と Codex は [共通指示](../codex/AGENTS.md) と作業別の skill を使います。`setup.sh` は設定と共有ツールへのリンクを作成します。

```sh
bash setup.sh
```

リンク先が異なる既存のエージェント用ディレクトリは `.back` に退避します。マウントされた `~/.claude` は保持します。fish、nvim、helix、Emacs、wezterm、ghostty をリンクする場合、既存の実設定ディレクトリは削除します。ghostty のリンクは macOS と Linux が対象です。

## 構成

| 用途 | 場所 |
|---|---|
| 共通の指示 | `codex/AGENTS.md` |
| Claude Code の共通指示の読み込み | `claude/CLAUDE.md` |
| 実行前ガードとイベント処理 | `agent-shared/hooks/` |
| 操作の判定ルールの元ファイルと生成 | `agent-shared/policy/action-policy.json`、`agent-shared/bin/apply-action-policy` |
| 作業別の手順 | `claude/skills/`、`codex/skills/` |
| skill の由来の一覧 | `agent-shared/skill-sources.tsv` |
| モデル間の委譲 | [codex-delegate](../claude/skills/codex-delegate/SKILL.md)、[claude-delegate](../codex/skills/claude-delegate/SKILL.md) |
| 独立レビュー | [review-gate](../codex/skills/review-gate/SKILL.md)、[codex-review](../claude/skills/codex-review/SKILL.md)、[claude-review](../codex/skills/claude-review/SKILL.md) |

## 操作の判定ルール

両 CLI の操作の判定は、各 CLI に組み込まれた AI の判定に任せます。Claude Code は auto mode の分類器、Codex は Auto-review が判定します。このリポジトリが追加する操作の判定役は、Claude Code で確認画面が出る場面だけで動きます。

操作を止める規則と事前に許可する規則は `agent-shared/policy/action-policy.json` にまとめます。片方の CLI に向けた規則は `targets` で指定します。依頼のない push を止める独自ルールは、`disabled` を付けて戻し方と一緒に残しています。

Claude Code の組み込みルールは、作業中のリポジトリへの通常の push を許可し、破壊的な Git 操作や認証情報の露出、依頼のない投稿を判定します。独自ルールは、エージェント自身が作業を続けられなくなる操作を止めます。記憶リポジトリへの push、Claude Code と Codex への委譲・レビュー、同じ会話で承認済みの操作の繰り返しは許可します。削除、履歴の書き換え、公開先への公開には承認を持ち越しません。利用者自身のリポジトリへの通常の push は、作業中のリポジトリ以外やデフォルトブランチへの push も許可します。この許可は宛先に限り、組織や他人のリポジトリには適用しません。force push や push する内容は引き続き審査します。

Codex は組み込みの Auto-review ポリシーを使います。`codex_custom_policy` が `false` の間、`apply-action-policy` と Codex の起動時に実行する `codex-review-policy.sh` は `config.toml` から以前のポリシー上書きを取り除きます。Claude Code の `autoMode` は、引き続き同じルールから生成します。`apply-action-policy --check` で設定との差分を確認できます。

Codex に独自ルールを再適用するには、`codex_custom_policy` を `true` にして `python3 agent-shared/bin/apply-action-policy --codex` を実行します。`python3` には Python 3.11 以降を使います。`[auto_review].policy` は組み込みのポリシー全体を置き換えるため、生成時に `codex debug models` からその時点の組み込みポリシーを取得し、独自ルールを足します。起動フックがポリシーを更新した場合、Codex は次のセッションから新しい内容を読み込みます。

Claude Code の allow は、組み込みの一覧を `$defaults` で取り込みます。組み込みの allow は soft_deny に足した規則より優先されるため、組み込みの allow を外したいときは `drop_default_allow` にそのラベルを書きます。その場合は組み込みの一覧から除いた全文を書き出し、Claude Code の更新で組み込みの一覧が変わると `--check` が差分を示します。`classifyAllShell` も有効にし、`permissions.allow` の Bash 規則が auto mode の判定を飛ばさないようにします。

auto mode でも確認画面は出ます。ホームディレクトリなど保護されたパスに対する `rm` や、symlink された設定ファイルの実体への書き込みは、組み込みの検査が確認画面を出します。分類器が拒否を重ねた後も、auto mode は確認画面に戻ります。`permission-judge.sh` は `PermissionRequest` hook としてこれらの確認画面に答えます。判定役の `claude -p` には、分類器と同じルール一式 (`claude auto-mode config`)、利用者の発言、エージェントのこれまでのツール呼び出し、保留中の操作を渡し、許可か拒否を返させます。ツールの結果とアシスタントの文章は、紛れ込んだ指示に判定を左右されないよう渡しません。判定役や hook が失敗した場合も、確認画面を出さずに拒否します。利用者への質問 (`AskUserQuestion`) と計画の承認 (`ExitPlanMode`) は判定せず、通常どおり表示します。Codex の Auto-review は承認が必要な操作をすべて審査するため、Codex 側にこの hook はありません。

同梱ポリシーのライセンスは [Apache License 2.0](../agent-shared/policy/codex-policy.LICENSE) です。

外部への書き込み後は `outward-write-readback.sh` が対応する内容の取得結果を通知します。

## commit 前の可搬性検査

`setup.sh` は、この checkout の通常の `git commit` に可搬性検査を登録します。
既存の `core.hooksPath` を尊重し、既存の pre-commit hook があれば保存して、検査成功後に呼び出します。
共有の hooks ディレクトリを使う他のリポジトリでは、検査を有効にしません。

検査対象は作業ツリーではなく stage 済みの内容です。追加・変更した symlink はリポジトリ内の
追跡対象を相対パスで参照する必要があります。Claude・Codex の hook 設定に追加したコマンドの
直接の引数にも、`/dev/null` 以外の絶対パスを書けません。実行時のホームディレクトリや PATH から解決します。
Hunk の手順も、固定した配布先への symlink ではなく、実行版の `hunk skill show` から取得します。

拒否時は対象ファイルを表示します。エージェントが修正して stage し直し、同じ commit を再実行します。
この検査はコマンドの直接の引数と symlink の参照を扱います。入れ子のスクリプトの本文や、実行時に
組み立てる値は解析しません。生成処理による作業ツリーへの書き込みを
止めるものではなく、変更の目的・既存機能との整合性は引き続き独立レビューで確かめます。

## skill の由来と編集先

skill には、この repo で書いたものと、外部の成果物に由来するものがあります。由来によって、直してよいファイルと上流の更新の取り込み方が違います。取り違えると、同期や生成で変更が消えたり、自前の変更を上流の本文で置き換えたりします。各 skill の種類と出所は由来の一覧 `agent-shared/skill-sources.tsv` にまとめ、`tests/skill-sources.sh` で実物と照合します。skill を追加・編集・更新する前に、由来の一覧で種類を確かめます。

| 種類 | 内容 | 編集先 | 上流の更新 |
|---|---|---|---|
| own | この repo で書いた skill | `claude/skills/`・`codex/skills/` の本文 | 無し |
| adapted | 外部の本文を取り込んで書き直し、Git で管理する skill | 同上 | 上流のファイルで置き換えず、上流の差分を読んで必要な内容を移す。superpowers は[下の手順](#superpowers-の取り込み)に従う |
| managed | `managed-skills.sh` が取得し、Git で管理しない skill | 直接編集しない。変更するときは `fork NAME` で導入先をすべて Git 管理へ移し、由来の一覧で種類を adapted にする。両側に導入した skill の片側だけを fork すると、両側を同じ内容に保つ規約を満たさないので、片側だけの fork は使わない | `managed-skills.sh sync` |
| generated | 端末の CLI が出力する手引きから生成し、Git で管理しない skill | `agent-shared/skill-overlays/<skill 名>.md`。生成した SKILL.md は直接編集しない | `herdr-skills.sh sync` |
| entry | 本文を実行時に CLI から取得する、この repo で書いた入口 | 入口の SKILL.md | CLI の更新で反映される |

外部に由来する skill の出所と著作権表示は `claude/skills/*.LICENSE` にあります。plugin が配布する skill と Codex の system skill はこの由来の一覧の対象外で、修正は [skill-source-overrides](../codex/skills/skill-source-overrides/SKILL.md) の手順で配布物とは別の場所に修正版を置きます。

外部の skill をそのまま導入するときは、次の節の `managed-skills.sh add` を使います。`npx skills add` や `gh skill install` を直接実行しません。`setup.sh` が作る `~/.claude/skills` と `~/.agents/skills` はこの repo の `claude/skills` と `codex/skills` を指すため、これらのコマンドが利用者全体へ導入すると、同じ名前の skill をこの repo の中で置き換えます。CLI が同名の skill の導入を案内していても (Hunk の `hunk-review` など)、この repo の入口を使います。skill を新設・fork・廃止したら、同じ変更で由来の一覧も直します。

## 外部 skill

外部 skill は `managed-skills.sh` で管理します。追加時に導入先を省略すると Claude Code と Codex の両方に導入します。

```sh
bash ~/.agent-shared/bin/managed-skills.sh add OWNER/REPO SKILL
bash ~/.agent-shared/bin/managed-skills.sh list
bash ~/.agent-shared/bin/managed-skills.sh sync
bash ~/.agent-shared/bin/managed-skills.sh remove NAME
bash ~/.agent-shared/bin/managed-skills.sh fork NAME
```

片方だけに導入するときは `add` の末尾に `claude` または `codex` を指定します。外部 skill を変更するときは、`fork NAME` で Git 管理に移してから編集します。`setup.sh` は登録済みの skill を同期します。

次の外部 skill は、既存の skill や既定の動作で足りるため導入しません。`add` で入れ直さず、同じ用途は右の列の skill を使います。

| 導入しない skill | 出所 | 代わりに使うもの |
|---|---|---|
| grill-me | mattpocock/skills | grilling |
| grill-with-docs | mattpocock/skills | grilling と domain-modeling |
| show-me | humanlayer/skills | 指定なし (図や要約は skill なしで書ける) |

### Herdr の skill

Herdr Core の端末で作業すると、エージェントは独立して進められる仕事を子端末に割り当て、親から進捗を確認して結果を回収します。作業や成果を画面に表示する依頼には Herdr App を使います。委譲の判断は [agent-delegation](../codex/skills/agent-delegation/SKILL.md)、端末と画面の手順は生成された各 skill にあります。

herdr-core と herdr-app の skill は、各 CLI が `--skill` で出力する手引きを本文にして、`setup.sh` が生成します。手引きは端末に入っている CLI の版で変わるため、生成した SKILL.md は Git で管理しません。いつ使うかを決める description と、この repo の補足は `agent-shared/skill-overlays/<skill 名>.md` に書き、手引きの前に置きます。上流の手引きを取り込み直しても、この上書きは毎回重なります。CLI を更新したら、次のコマンドで手引きを取り込みます。

```sh
bash ~/.agent-shared/bin/herdr-skills.sh sync
```

CLI が入っていない端末では何もしません。手引きを取得できなかったときは、既存の skill を残して失敗を報告します。生成した skill は Git に含まれないため、clone した直後の端末や、この仕組みを取り込んだ直後の端末では、`setup.sh` か上のコマンドを実行するまで herdr-core と herdr-app の skill がありません。

## 記憶

個人の記憶は非公開リポジトリで管理し、各エージェントの `memory/` から参照します。セッション開始時に同期を試み、利用者の入力時には検索候補と、その会話にまだ渡していない版の索引を渡します。本文は索引から選んで取得します。

```sh
bash ~/.agent-shared/hooks/inject-memory.sh ~/.codex/memory lookup '検索語'
```

Claude Code では `~/.claude/memory` を指定します。同期できない場合はローカルの確定済み記憶を使います。

## 作業ワークフロー

作業は [kata](../codex/skills/kata/SKILL.md) の入口で、結果・操作範囲・未決事項・確認方法から必要な準備を選びます。既存の情報で直接完了できる場合は、実行と結果確認へ進みます。設計や計画などの判断が必要になった場合に、詳細工程と該当する skill を読みます。作業名ごとの例外は設けません。

| 工程 | skill |
|---|---|
| 1. 設計 | [kata-design](../codex/skills/kata-design/SKILL.md) |
| 2. 作業場所 | [kata-workspace](../codex/skills/kata-workspace/SKILL.md) |
| 3. 計画 | [kata-plan](../codex/skills/kata-plan/SKILL.md) |
| 4. 実装 | [kata-build](../codex/skills/kata-build/SKILL.md) (テストは test-red-first、不具合の調査は investigation-discipline) |
| 5. 独立レビュー | review-gate |
| 6. 完了前の確認 | [kata-verify](../codex/skills/kata-verify/SKILL.md) |
| 7. 統合と後片付け | [kata-finish](../codex/skills/kata-finish/SKILL.md) |

SessionStart hook の `kata-entry.sh` が kata と工程ごとの skill を案内します。`kata-first.sh` は利用者の入力ごとに、最初に kata を開いて調査の要否を判断するよう伝えます (UserPromptSubmit)。kata を開くまで、PreToolUse の対象になる通常のツールを止めます。子エージェントのツール呼出しと委譲された子のセッションにはこの停止を適用しません。委譲先には、担当範囲で調査を進め、設計・統合・利用者への質問は司令塔へ返すよう案内します。Codex で hook の登録を追加・変更した場合は、`/hooks` で信頼し直すまで動きません。

調査・真偽判定・方式選定などでは、kata が [investigation-discipline](../codex/skills/investigation-discipline/SKILL.md#外部情報と現物を並行して調べる) の入口になります。エージェントは外部の資料を手元の実物と照合してから、結論・設計・実装へ進みます。hook が制御するのは kata を開く順序で、資料の関連性や照合の成否はエージェントが判断します。

### superpowers の取り込み

工程 skill は [superpowers](https://github.com/obra/superpowers) (MIT License) の手順を取り込んだものです。plugin は両 CLI の設定で無効にしています (アンインストールはしていません)。有効にすると、上流と自前の同じ手順を二重に読むためです。ただし Codex は、アカウントに導入された plugin について、この無効化を反映しません。そのため Codex では、`codex/config.toml` の `[[skills.config]]` で superpowers の skill を一つずつ一覧から外しています。著作権表示は `claude/skills/superpowers.LICENSE` にあります。

| 上流の skill | 取り込み先 |
|---|---|
| brainstorming | kata-design |
| using-git-worktrees | kata-workspace |
| writing-plans | kata-plan |
| executing-plans・subagent-driven-development | kata-build |
| test-driven-development | test-red-first |
| systematic-debugging | investigation-discipline |
| requesting-code-review・receiving-code-review | review-gate |
| verification-before-completion | kata-verify |
| finishing-a-development-branch | kata-finish |
| using-superpowers | kata・`kata-entry.sh` |
| dispatching-parallel-agents | agent-delegation |
| writing-skills | create-rule・improving-skills・empirical-prompt-tuning |
| diagnosing-superpowers | 取り込まない (superpowers 自体の不具合を報告するための skill) |

brainstorming のうち、ブラウザで図を見せる visual companion は取り込まず、kata-design ではテキストの図を使います。

取り込み済みの版は `agent-shared/superpowers-imported-version` にあります。`kata-entry.sh` は 30 日に一度上流のタグを確かめ、新しい版があれば `agent-shared/bin/superpowers-import` をバックグラウンドで起動します。この script は状態ディレクトリ (既定は `~/.local/state/agent-shared`) の `import-<版>/repo` に dotfiles を clone し、その master で Codex に次の手順を進めさせます。作業中の checkout には触れず、push もしません。

1. 上流の `git diff v<取り込み済みの版> v<新しい版> -- skills/` を読みます。
2. 作業の結果を変える変更を、表の取り込み先へ移します。共通指示と衝突するものや、共通指示・自前 skill が既に担う内容は移しません。上流で表に無い skill が増えた場合、無人の取り込みでは自前の skill を新設しません。表の既存の取り込み先へ移すか、取り込まない判断と理由、新設が要ると考える理由を報告に書き、利用者の判断に回します。表の skill を統合・削除した場合も、この表の取り込み先を書き換えて、上流の取り込みで元の skill が作り直されないようにします。
3. `tests/skills-sync.sh` で Claude 側と Codex 側をそろえます。
4. 独立レビューを通し、`superpowers-imported-version` を更新して commit します。移すものが無い版も値を更新します。

取り込みが完了・失敗・停止すると、次のセッションで結果ごとに一度だけ、依頼への回答の後に知らせます。`import-<版>/report.md` を確かめてから、`import-<版>/repo` の master を `git-lossless-integrate` で取り込みます。取り込まないと決めた場合は、作業中の checkout の `superpowers-imported-version` をその版にします。失敗・停止したら `import-<版>/codex.log` と `report.md` で原因を確かめ、`import-<版>/status` を消すと、次のセッションで clone の成果を引き継いで再実行します。

依頼された作業を途中で止めないよう、`kata-completion.sh` が両 CLI の Stop hook として動きます。エージェントがターンを終えようとするたびに、判定役の Sonnet へ、計画・進捗・このセッションのやり取り・会話記録の末尾の操作と結果・最後の応答を渡し、次の 3 つのどれかを返させます。計画は、kata-plan の最後に `kata-active <claude|codex> start <計画ファイル>` で実装中を記録したセッションだけにあります。計画が無いセッションでは、利用者がそのセッションで頼んだことが作業の範囲です。後から質問されても、前の依頼は終わるか取り下げられるまで残ります。計画が無いセッションを判定するのは、Claude Code の対話のセッションだけです。やり取りは、利用者の発言ごとに、その発言と、そのターンでエージェントが最後に書いた文を古い順に渡します。前の依頼を終えたのか一時停止したのかを、判定役が知るためです。長い発言は先頭と末尾を残し、全体が 6 万字を超えたら古いターンから省きます。そのため、長い発言の中ほどにだけ書いた指示や、省いた古いターンの依頼は、判定役に届かないことがあります。バックグラウンドのタスクの完了通知、圧縮後の要約、コマンドの出力は、利用者の発言として渡しません。計画が無いときは、Codex のセッション、委譲された子のセッション (`lib/delegated-session.sh` の判定)、プログラムから起動した実行 (`claude -p`、`codex exec`) は判定しません。Codex は下のとおり判定のたびに利用者を待たせるため、委譲された子とプログラムからの実行は、完了を呼び出し元が確かめ、続けさせると呼び出し元が受け取る出力が変わるためです。

| 判定 | 条件 | hook の動作 |
|---|---|---|
| 完了 | 作業を検証の証拠つきで終えた、利用者が作業を終えた・取り下げた、または利用者が質問・説明だけを求め、答えて、前の依頼も残っていない | 記録を消し、終了させる |
| 本人待ち | 本人の認証・判断・承認が必要な理由を具体的に報告した、別の手段を試しても進めない理由と再開の条件を報告した、または利用者が一時停止や説明だけを求めて応じた | 記録を残して終了させる。返答の後も作業を続ける |
| 継続 | それ以外 (途中報告、「続けますか」、証拠のない完了報告、このセッションで自分が作ったものの不足を挙げて「直すなら言って」と止まったなど) | 残りを進めるよう差し戻す |

Claude Code では `asyncRewake` で登録し、ターンを終えてから判定します。利用者は判定を待たず、続けさせる場合だけ hook がエージェントを起こします。判定の間に利用者が発言した場合と、次のターンが終わった場合は起こしません。Codex は待機中のエージェントを起こせないため、ターンの終わりに判定し、そのぶん終了が遅れます。hook 全体の所要時間は、測ったところ短い会話で約 2〜3 秒、長いセッション (会話記録 17 MB) で約 7〜11 秒でした。バックグラウンドのタスク (シェルのコマンド・子エージェント) を待つためのターン終了は判定せず、待ち方は下の監視 hook に任せます。判定役を呼べなかった場合と、利用者の同じ発言のあいだに差し戻しが 10 回続いた場合は終了させます。回数は、利用者が新しく発言すると数え直します。10 回は、Claude Code が同期の hook の連続した差し戻しを打ち切る回数に合わせています。記録は `/tmp/claude-<uid>/kata/<CLI>/<セッション ID>/` に置きます。両 CLI の sandbox からエージェントが書ける場所だからです。セッションは Claude Code の `CLAUDE_CODE_SESSION_ID`、Codex の `CODEX_THREAD_ID` で区別するため、同じ checkout で動く別のセッションには影響しません。一方の CLI から他方を起動すると子の環境に親の変数も残るため、どちらの変数を使うかは `kata-active` の最初の引数と hook の登録時の引数で指定します。Claude Code の `/goal` と併用できます。

## バックグラウンド処理の確認

監視 hook は、エージェントがバックグラウンドのタスク (シェルのコマンド・子エージェント) を起動したまま、結果を待つだけになる状態を防ぎます。確認はターンの終了から 10 分後、その 20 分後、その 40 分後、以後 40 分ごとに行います。間隔を 60 分以下に保つのは、Codex で待機から戻ったエージェントが 1 時間のプロンプトキャッシュを使えるようにするためです。Claude Code では進んでいる間はエージェントを起こさないため、2 回目以降の確認で起こした場合はキャッシュが切れていることがあります。

Claude Code では `task-monitor-claude.sh` が Stop hook (`asyncRewake`) として待機します。確認のたびに、タスクの出力の末尾 (子エージェントは会話記録の直近の操作と本文) を判定役の Haiku へ渡します。判定役は前回の確認時と比べて、進んでいるか、止まっているか、判断できないかを返します。進んでいる間はエージェントを起こさないため、エージェントのトークンを使いません。止まっている・判断できない場合は、判定理由と出力の末尾を添えてエージェントを起こし、タスクを止めて原因を調べ、直すか別の方法でやり直すよう指示します。判定役の呼出しに失敗した場合も、止まったタスクを見逃さないよう、判断できないものとして起こします。タスクが終われば Claude Code 自身がエージェントを起こし、次のターン終了で数え直します。出力をすべてファイルへ向けたコマンドは判定役から進み具合が見えず、確認のたびに起こすことになるため、進み具合を標準出力にも出してください。

前面で動くコマンドの間は、エージェントもこの監視も動けません。Claude Code は上限を過ぎた前面のコマンドをバックグラウンドへ移すため、移った後はこの監視の対象になります。前面で監視されずに待つ時間を短く保つため、`claude/settings.json` で上限の最大値 (`BASH_MAX_TIMEOUT_MS`) を既定の上限と同じ 5 分にしています。

Codex は待機中のエージェントを起こせないため、`task-monitor-codex.sh` が実行中の子エージェントとバックグラウンドのコマンドを記録し、残っている間はターンの終了を止めます。Linux と macOS では、hook がターン終了時にコマンドの呼び出し ID を実行中のプロセスと照合します。起動を拒否されたコマンドや終了済みのコマンドは待機対象から外します。OS がプロセスの環境変数を隠す場合や、ほかの OS でプロセスを照合できない場合、hook は Codex の終了記録を確認します。状態が分からない呼び出しが残れば、hook はエージェントに元のツールの返答を一度だけ確認させます。エージェントは返答にある実行中のセッション ID で結果を回収します。止めるときは、`wait_agent` または空の `write_stdin` で予定の時間だけ待ってから最新の内容を確かめるよう指示します。`wait_agent` の待ち時間は hook が予定の値へ書き換え、戻るたびに子の rollout の直近の操作と本文を渡します。進んでいるかはエージェント自身が判断します。待ち時間は、利用者の入力、子の起動・再依頼、新しいバックグラウンドのコマンドで 10 分から数え直します。エージェントがツールを一度も呼ばないままターンを終えることが 3 回続いたら、止めるのをやめ、残っているタスクを報告させます。空の `write_stdin` で 40 分待てるよう、`codex/config.toml` の `background_terminal_max_timeout` を 40 分にしています。kata の計画を実装中は、この判定を計画の完了確認の hook (`kata-completion.sh`) が呼び、止めない場合だけ計画の完了を確かめます。2 つの hook が別々に判定すると、その間にコマンドが終わったときにどちらも止めず、計画の確認が抜けるためです。このため、Codex の `/hooks` では両方の Stop hook を信頼しておいてください。

Codex の hook を変更した場合は `/hooks` で信頼し直してください。
