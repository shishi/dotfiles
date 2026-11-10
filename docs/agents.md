# エージェントの設定

Claude Code と Codex は [共通指示](../codex/AGENTS.md) と作業別の skill を使います。`setup.sh` は設定と共有ツールへのリンクを作成します。実行前に [出力ゲートの利用条件](output-gate.md#利用方法)を確認してください。共有マシンでは事前に出力ゲートの無効化が必要です。

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
| 操作の判定ルールの正本と生成 | `agent-shared/policy/action-policy.json`、`agent-shared/bin/apply-action-policy` |
| 作業別の手順 | `claude/skills/`、`codex/skills/` |
| モデル間の委譲 | [codex-delegate](../claude/skills/codex-delegate/SKILL.md)、[claude-delegate](../codex/skills/claude-delegate/SKILL.md) |
| 独立レビュー | [review-gate](../codex/skills/review-gate/SKILL.md)、[codex-review](../claude/skills/codex-review/SKILL.md)、[claude-review](../codex/skills/claude-review/SKILL.md) |

両 CLI の操作の判定は、各 CLI に組み込まれた AI の判定に任せます。Claude Code は auto mode の分類器、Codex は Auto-review が判定します。このリポジトリが追加する操作の判定役は、Claude Code で確認画面が出る場面だけで動きます。

止める操作と事前に許可する操作は `agent-shared/policy/action-policy.json` にまとめます。このファイルで両 CLI について止めるのは、エージェント自身の作業を続けられなくする操作です。push は両 CLI の組み込みの判定に任せています。Claude Code の auto mode では、作業中のリポジトリへの通常の push は通り、他人の作業を消す force push などは止まります。Codex では Auto-review の組み込みの方針が判定します。依頼のない push を止める規則は、`disabled` を付けて戻し方と一緒にこのファイルに残しています。依頼のない投稿は、Claude Code では auto mode に組み込まれたルールが止め、Codex では同じファイルの Codex 向けの規則が止めます。片方の CLI にだけ渡す規則は `targets` で絞ります。破壊的な Git 操作や認証情報の露出は、Claude Code では auto mode に組み込まれたルールが止めます。Codex の Auto-review も、組み込みの方針で取り返しのつかない破壊や認証情報の不正な取得を止めます。記憶リポジトリへの push と、Claude と Codex への委譲・レビューは許可します。同じ会話で承認済みの操作も、同じ対象と範囲なら許可します。ただし削除、履歴の書き換え、公開先への公開は、承認を持ち越しません。`agent-shared/bin/apply-action-policy` は、このファイルから `claude/settings.json` の `autoMode` と `codex/config.toml` の `[auto_review].extra_policy` を書き出します。ファイルを変えたら実行し、`--check` で設定とのずれがないことを確かめます。

Claude Code の allow は、組み込みの一覧を `$defaults` で取り込みます。組み込みの allow は soft_deny に足した規則より優先されるため、組み込みの allow を外したいときは `drop_default_allow` にそのラベルを書きます。その場合は組み込みの一覧から除いた全文を書き出し、Claude Code の更新で組み込みの一覧が変わると `--check` が差分を示します。`classifyAllShell` も有効にし、`permissions.allow` の Bash 規則が auto mode の判定を飛ばさないようにします。

auto mode でも確認画面は出ます。ホームディレクトリなど保護されたパスに対する `rm` や、symlink された設定ファイルの実体への書き込みは、組み込みの検査が確認画面を出します。分類器が拒否を重ねた後も、auto mode は確認画面に戻ります。`permission-judge.sh` は `PermissionRequest` hook としてこれらの確認画面に答えます。判定役の `claude -p` には、分類器と同じルール一式 (`claude auto-mode config`)、利用者の発言、エージェントのこれまでのツール呼び出し、保留中の操作を渡し、許可か拒否を返させます。ツールの結果とアシスタントの文章は、紛れ込んだ指示に判定を左右されないよう渡しません。判定役や hook が失敗した場合も、確認画面を出さずに拒否します。利用者への質問 (`AskUserQuestion`) と計画の承認 (`ExitPlanMode`) は判定せず、通常どおり表示します。Codex の Auto-review は承認が必要な操作をすべて審査するため、Codex 側にこの hook はありません。

外部への書き込み後は `outward-write-readback.sh` が対応する内容の取得結果を通知します。

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

## 記憶

個人の記憶は非公開リポジトリで管理し、各エージェントの `memory/` から参照します。セッション開始時に同期を試み、利用者の入力時には索引と検索候補を渡します。本文は索引から選んで取得します。

```sh
bash ~/.agent-shared/hooks/inject-memory.sh ~/.codex/memory lookup '検索語'
```

Claude Code では `~/.claude/memory` を指定します。同期できない場合はローカルの確定済み記憶を使います。

## 作業ワークフロー

変更作業は [kata](../codex/skills/kata/SKILL.md) の工程表に沿って進めます。各工程の手順は工程ごとの skill が持ちます。

| 工程 | skill |
|---|---|
| 1. 設計 | [kata-design](../codex/skills/kata-design/SKILL.md) |
| 2. 作業場所 | [kata-workspace](../codex/skills/kata-workspace/SKILL.md) |
| 3. 計画 | [kata-plan](../codex/skills/kata-plan/SKILL.md) |
| 4. 実装 | [kata-build](../codex/skills/kata-build/SKILL.md) (テストは test-red-first、不具合の調査は investigation-discipline) |
| 5. 独立レビュー | review-gate |
| 6. 完了前の確認 | [kata-verify](../codex/skills/kata-verify/SKILL.md) |
| 7. 統合と後片付け | [kata-finish](../codex/skills/kata-finish/SKILL.md) |

skill が選ばれるかはモデルが description に気づくかに左右されるため、SessionStart hook の `kata-entry.sh` が入口の kata と工程ごとの skill を毎回伝えます。

### superpowers の取り込み

工程 skill は [superpowers](https://github.com/obra/superpowers) (MIT License) の手順を取り込んだものです。plugin は両 CLI で無効にしています (アンインストールはしていません)。有効にすると、上流と自前の同じ手順を二重に読むためです。著作権表示は `claude/skills/superpowers.LICENSE` にあります。

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

取り込み済みの版は `agent-shared/superpowers-imported-version` にあります。`kata-entry.sh` は 30 日に一度上流のタグを確かめ、新しい版があれば `agent-shared/bin/superpowers-import` をバックグラウンドで起動します。この script は状態ディレクトリ (既定は `~/.local/state/agent-shared`) の `import-<版>/repo` に dotfiles を clone し、その master で Codex に次の手順を進めさせます。作業中の checkout には触れず、push もしません。

1. 上流の `git diff v<取り込み済みの版> v<新しい版> -- skills/` を読みます。
2. 作業の結果を変える変更を、表の取り込み先へ移します。共通指示と衝突するものや、共通指示・自前 skill が既に担う内容は移しません。
3. `tests/skills-sync.sh` で Claude 側と Codex 側をそろえます。
4. 独立レビューを通し、`superpowers-imported-version` を更新して commit します。移すものが無い版も値を更新します。

結果はセッションの開始時に知らせます。`import-<版>/report.md` を確かめてから、`import-<版>/repo` の master を `git-lossless-integrate` で取り込みます。取り込まないと決めた場合は、作業中の checkout の `superpowers-imported-version` をその版にして知らせを止めます。失敗・停止したら `import-<版>/codex.log` と `report.md` で原因を確かめ、`import-<版>/status` を消すと、次のセッションで clone の成果を引き継いで再実行します。

計画の実装を途中で止めないよう、`kata-completion.sh` が両 CLI の Stop hook として動きます。kata-plan の最後に `kata-active <claude|codex> start <計画ファイル>` で実装中を記録したセッションでだけ判定し、記録がなければ何もしません。ターンを終えようとするたびに、判定役の Sonnet へ計画・進捗・直近の利用者の発言・会話記録の末尾の操作と結果・最後の応答を渡し、次の 3 つのどれかを返させます。

| 判定 | 条件 | hook の動作 |
|---|---|---|
| 完了 | 全 task を検証の証拠つきで終えた、または利用者が計画を終えた・取り下げた | 記録を消し、終了させる |
| 本人待ち | 本人の認証・判断・承認が必要な理由を具体的に報告した、別の手段を試しても進めない理由と再開の条件を報告した、または利用者が一時停止や質問・説明だけを求めて答えた | 記録を残して終了させる。返答の後も計画を続ける |
| 継続 | それ以外 (途中報告、「続けますか」、証拠のない完了報告など) | 残りを進めるよう差し戻す |

判定は 1 回あたり数秒かかります。バックグラウンドのタスク (シェルのコマンド・子エージェント) を待つためのターン終了は判定せず、待ち方は下の監視 hook に任せます。判定役を呼べなかった場合と、差し戻しが 10 回続いた場合は終了させます。回数は、差し戻しを受けずに始まったターン終了から数え直します。10 回は、Claude Code が同じ hook の連続した差し戻しを打ち切る回数に合わせています。記録は `/tmp/claude-<uid>/kata/<CLI>/<セッション ID>/` に置きます。両 CLI の sandbox からエージェントが書ける場所だからです。セッションは Claude Code の `CLAUDE_CODE_SESSION_ID`、Codex の `CODEX_THREAD_ID` で区別するため、同じ checkout で動く別のセッションには影響しません。一方の CLI から他方を起動すると子の環境に親の変数も残るため、どちらの変数を使うかは `kata-active` の最初の引数と hook の登録時の引数で指定します。Claude Code の `/goal` と併用できます。

## バックグラウンド処理の確認

監視 hook は、エージェントがバックグラウンドのタスク (シェルのコマンド・子エージェント) を起動したまま、結果を待つだけになる状態を防ぎます。確認はターンの終了から 10 分後、その 20 分後、その 40 分後、以後 40 分ごとに行います。間隔を 60 分以下に保つのは、Codex で待機から戻ったエージェントが 1 時間のプロンプトキャッシュを使えるようにするためです。Claude Code では進んでいる間はエージェントを起こさないため、2 回目以降の確認で起こした場合はキャッシュが切れていることがあります。

Claude Code では `task-monitor-claude.sh` が Stop hook (`asyncRewake`) として待機します。確認のたびに、タスクの出力の末尾 (子エージェントは会話記録の直近の操作と本文) を判定役の Haiku へ渡します。判定役は前回の確認時と比べて、進んでいるか、止まっているか、判断できないかを返します。進んでいる間はエージェントを起こさないため、エージェントのトークンを使いません。止まっている・判断できない場合は、判定理由と出力の末尾を添えてエージェントを起こし、タスクを止めて原因を調べ、直すか別の方法でやり直すよう指示します。判定役の呼出しに失敗した場合も、止まったタスクを見逃さないよう、判断できないものとして起こします。タスクが終われば Claude Code 自身がエージェントを起こし、次のターン終了で数え直します。出力をすべてファイルへ向けたコマンドは判定役から進み具合が見えず、確認のたびに起こすことになるため、進み具合を標準出力にも出してください。

前面で動くコマンドの間は、エージェントもこの監視も動けません。Claude Code は上限を過ぎた前面のコマンドをバックグラウンドへ移すため、移った後はこの監視の対象になります。前面で監視されずに待つ時間を短く保つため、`claude/settings.json` で上限の最大値 (`BASH_MAX_TIMEOUT_MS`) を既定の上限と同じ 5 分にしています。

Codex は待機中のエージェントを起こせないため、`task-monitor-codex.sh` が実行中の子エージェントとバックグラウンドのコマンドを記録し、残っている間はターンの終了を止めます。止めるときは、`wait_agent` または空の `write_stdin` で予定の時間だけ待ってから最新の内容を確かめるよう指示します。`wait_agent` の待ち時間は hook が予定の値へ書き換え、戻るたびに子の rollout の直近の操作と本文を渡します。進んでいるかはエージェント自身が判断します。待ち時間は、利用者の入力、子の起動・再依頼、新しいバックグラウンドのコマンドで 10 分から数え直します。エージェントがツールを一度も呼ばないままターンを終えることが 3 回続いたら、止めるのをやめ、残っているタスクを報告させます。空の `write_stdin` で 40 分待てるよう、`codex/config.toml` の `background_terminal_max_timeout` を 40 分にしています。

Codex の hook を変更した場合は `/hooks` で信頼し直してください。
