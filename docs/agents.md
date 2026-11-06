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
| 作業別の手順 | `claude/skills/`、`codex/skills/` |
| モデル間の委譲 | [codex-delegate](../claude/skills/codex-delegate/SKILL.md)、[claude-delegate](../codex/skills/claude-delegate/SKILL.md) |
| 独立レビュー | [review-gate](../codex/skills/review-gate/SKILL.md)、[codex-review](../claude/skills/codex-review/SKILL.md)、[claude-review](../codex/skills/claude-review/SKILL.md) |

`command-judge.sh` は両 CLI のツール呼び出しを実行前に判定します。ツール名・引数と利用者の依頼から、操作の影響と承認の有無を判定します。Codex の `write_stdin` による追加入力など、実行前 hook が発火しない経路は対象外です。判定役が利用できない場合は警告して通し、個別の判定が失敗した場合は確認または停止することがあります。外部への書き込み後は `outward-write-readback.sh` が対応する内容の取得結果を通知します。対象と制限は各スクリプトを参照してください。

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

## 背景作業の確認

`stall-guard.sh` は、背景作業の進捗確認が行われないままターンが終わることを検出します。Claude Code と Codex では終了を止める条件が異なります。`deadline` は確認間隔を設定し、`keep` は意図して継続する背景 Bash を確認対象から外します。`deadline` と `keep` は対象セッションの Claude Code の Bash から実行します。

```sh
bash ~/.agent-shared/hooks/stall-guard.sh deadline <id> <1〜30 分> [--watch <path>]
bash ~/.agent-shared/hooks/stall-guard.sh keep <id>
bash ~/.agent-shared/hooks/stall-guard.sh [--cli codex] status [--json] --session <id>
bash ~/.agent-shared/hooks/stall-guard.sh disable
```

Codex の hook を変更した場合は `/hooks` で信頼し直してください。

hook を取り外す場合は、先に `disable` を実行し、`status` に表示された予約を削除してから、Claude Code と Codex の設定から hook を外します。`CronCreate` の予約は `CronDelete` で削除します。`ScheduleWakeup{stop:true}` はほかの起床予約も取り消します。不要になった状態ディレクトリは削除できます。
