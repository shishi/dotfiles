# エージェントの実行環境と観測の食い違い

対象は、エージェントの shell・sandbox・プロセス環境によって取得結果が変わる場合です。
製品設定の仕様は、使用する CLI で利用できる公式資料の取得経路から該当版を確認します。
この参照は sandbox や hook の拒否を解除する権限を追加しません。

## ファイルと一時パス

- 実 OS、実シェル、cwd、実パス、読み書き可能範囲を特定します。
  ツール名が Bash でも、実行シェルや GNU/BSD の構文を推測しません。
  zsh で動く場合、`"$REV:lib/x"` の `:l` は変数の修飾子として解釈されるため、
  `"${REV}:lib/x"` と波括弧で区切ります。zsh は一致しない glob を展開時にエラーにするため、
  存在しないかもしれないパターンには `(N)` 修飾子 (`for f in pattern(N); do …; done`) を付けます。
  bash は一致しないパターンを文字列のまま残すため、`[ -e "$f" ]` で存在を確かめてから扱います。
- 一時ディレクトリは作成直後の絶対パスを控え、後の呼び出しでも同じパスを使います。
  別呼び出しの `TMPDIR` から組み直しません。外側と内側で環境が違う場合もあります。
- ディレクトリの移動に失敗したら、後続の変更操作を実行しません。
  shell では `cd "$TASK_REPO" || exit 1`、またはツールの cwd 指定を使います。
- 不自然な untracked、存在するはずのない設定ファイル、読み取り専用の device が出る場合は、
  実ファイルと bind mount を区別します。Linux では file type、`/proc/self/mounts`、
  許可された別経路での同じパスを対比します。
  観測を直すためにファイルを削除せず、証拠が一致するまで stage しません。

## 認証・通信とプロセス

- 回答の生成・出力検査・表示は、それぞれの結果を照合します。本文が表示されていても検査の成功とは限らず、検査の未完了を回答生成の失敗と扱いません。
  検査の異常では、対象ターンの状態・理由・検査役の起動記録を先に確認します。再現入力には、有効な依頼・制約の状態、原文の参照と取得結果、差分の取込位置、差し戻し時のチェックポイントを含めます。
  原文の保存、検査役への供給、意味の確認を区別し、回答の各主張と必要な証拠の対応を調べます。履歴の増加による失敗では、初回取込と差分更新を分け、情報の選択を含む全モデル入力の量と時間を測ります。
  上限の拡大や一律の古い順の削除で済ませず、有効な条件と必要な原文を保持したまま、同じ履歴の再送を減らします。
  検査役を呼ぶ前に失敗していれば、同じ入力の準備処理をローカルで再現してから、モデルの判定品質や通信を調べます。
- 実行前審査が操作を拒否したら、拒否理由を実装・宛先・取得済みの利用者承認と照合します。
  操作名から推定された影響と、確認した実処理を区別します。審査役がローカルファイルを
  読めない場合は、判断に必要な処理の本文と実際の保存先・送信先をツール入力に示します。
  読んだ実装と実行するファイルの一致も検査し、追加した証拠を通常の審査経路で再判定します。
  操作名の変更や不透明なラッパーで審査を通さず、同じ処理と承認範囲を審査可能にします。
  実際に承認や権限が不足している場合は、依存しない作業を済ませて必要な承認だけを求めます。
- 認証失敗は token 失効、keychain 到達不能、通信、proxy、実行主体を分けます。
  同じアカウントの別経路で成功しているなら、再認証を求める前に境界の違いを確かめます。
  credential をコマンド文字列やログへ出して比較しません。
  macOS の `gh` は sandbox 内で keychain に届かないと、有効な token でも
  「token invalid」と報告し、`gh auth login` を案内します。`GH_TOKEN` など
  環境変数で token を渡す呼び出しは keychain を使いません。
- sandbox の許可がコマンド・プロセス・呼び出し全体のどれに適用されるかは、CLI と版の仕様と実測で
  確認します。観測用の呼び出しへ、許可済みで sandbox 外を走るコマンドを混ぜません
  (Claude Code の具体例は下の節)。
- `ps` やセッション一覧の空出力は、観測経路の制限や応答エラーを確認してから解釈します。
  実行 handle、終了通知、アプリの実状態など、利用できる別の証拠と対比します。

## Claude Code の Bash sandbox

`sandbox.excludedCommands` の要素は、permissions の `Bash(...)` と同じ規則で照合されます。

| 書き方 | 照合 |
|---|---|
| `"gh"` | exact。コマンド文字列全体が `gh` のときだけ一致し、`gh auth status` には一致しません |
| `"gh:*"` | prefix。`gh` 単体と、`gh ` で始まるコマンドに一致します |
| `"gh *"` | wildcard |

引数付きで呼ぶコマンドを exact で書いても、エラーや警告は出ません。
除外を追加・確認するときは、引数付きの実際の呼び出しで sandbox の内外を確かめます。

除外と照合されるのは、トップレベルでコマンド位置にあるコマンドです。
`timeout`・`nice`・`nohup`・`stdbuf`・`command` などのラッパーは照合前に外されます。
`env`・`bash -c`・`xargs`・シェル関数・エイリアス・スクリプトの内側と、
`$(…)`・バッククォート・`<(…)` の中のコマンドは sandbox 内で走ります。
コマンド置換の中では、照合前に外されるラッパーを付けても sandbox 内です。

除外は一致した部分ではなく、呼び出し全体の sandbox の有無を切り替える場合があります。
Claude Code 2.1.258 (macOS) では、除外コマンドを 1 つでも含む行が、`cd` を含めて丸ごと
sandbox 外で走りました。公式資料は、行内の全コマンドが一致した場合だけ除外すると説明しています。
使用版で確かめ、除外リストを広げると同じ行の他のコマンドも sandbox 外で走り得ることを考慮します。

sandbox の挙動を測るプローブには、除外コマンドを混ぜません。状態確認のために `git status`
などを同じ行へ足すと、プローブ全体が sandbox 外で走り得ます。拒否されるはずの書込みが
成功し、再現しない場合は、まずこの混入を疑います。

`filesystem.allowWrite` は、列挙したディレクトリ自体の作成を許可しません (2.1.258 で観測)。
存在しないディレクトリへの `mkdir -p` は、親ディレクトリへの書込みとして拒否されます。
bash スクリプトとして起動する helper の書込みは、内部で呼ぶコマンドが除外対象でも sandbox 内です。
設定変更の承認がある場合も、`bash:*` の除外や呼び出しごとの sandbox 解除は必要な範囲より
広く開けるため、対象パスだけを `filesystem.allowWrite` へ加える方法と比較します。

### sandbox 設定を検証する

入れ子の `claude -p` に検証したい設定を渡し、その中で対象の操作を実行させます。

```sh
env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT AGENT_DELEGATED_SESSION=1 \
  claude -p --model haiku --permission-mode default \
  --settings '<検証する設定の JSON>' '<実行させる指示>' </dev/null
```

- 外側の sandbox が内側の sandbox を遮るため、外側の呼び出しは sandbox 外で実行します。
  sandbox の解除は通常の承認経路で求めます。
- 内側の設定に `sandbox.allowUnsandboxedCommands: false` を加え、内側のモデルが
  sandbox を外して操作を成功させる経路を塞ぎます。
- `--settings` や project settings の `sandbox`・`permissions.allow` は user settings と
  配列で結合され、user settings の `excludedCommands` は外せません (2.1.258 で観測)。
  測定する行に、user settings で除外されたコマンドを混ぜません。
- 結果は内側のモデルの自己申告ではなく、生成物 (ファイル、socket、DB) と transcript
  (`~/.claude/projects/<dir>/*.jsonl` の tool_result) で確認します。

## Codex の実行環境

- 実効の sandbox と承認方針は、`config.toml` や `codex doctor` の表示ではなく、
  rollout の各 `turn_context` にある `sandbox_policy`・`approval_policy`・`approvals_reviewer`
  で確認します。Codex Desktop でタスクごとに選ぶ権限は、永続設定より優先されます。
  Windows の Codex Desktop 0.146 系では、Full access を選んだタスクが
  `approval_policy: "never"` になり、Auto-review は動作しませんでした。
- sandbox の挙動は `codex sandbox -c sandbox_mode=workspace-write -- <cmd>` で、
  モデルを介さずに再現できます。`codex exec` は無応答のまま止まることがあるため、
  sandbox の受入判定はこの決定的な実行で取ります。Windows の elevated sandbox では
  `codex sandbox` が setup helper を起動して応答しないことがあります (0.164.0 で観測)。
  締切を決めて実行し、応答がなければ rollout の実行結果で確かめます。
- sandbox 内の全コマンドが失敗する場合は、`codex features list` で機能の状態を確かめ、
  `config.toml` に削除済み機能へ依存する設定 (Windows の `[windows] sandbox` 等) が
  残っていないか照合します。
- `codex exec` は stdin が TTY でないと追加入力を待ちます。追加入力がなければ
  `</dev/null` を付けます。diff など長い入力は、引数ではなく stdin で渡します。
  引数では `Argument list too long` になります。
- Claude Code と Codex の sandbox は、許可の単位と既定値が違います。一方の結果を他方へ流用しません。
  macOS の `workspace-write` では、`sandbox_workspace_write.network_access` が既定の
  false だと unix socket (nix daemon 等) への接続も拒否されます。`/tmp` には書けます。
  書込範囲外にある `.git` を更新する `git worktree add` は失敗します。

## 起動と表示

プロセス起動の失敗は、エラーに出た実行ファイルと引数、絶対パス、loader を確認します。
ファイルを読めることと、UI 上へ描画できることは別々に検証します。
NixOS の外部 ELF / ライブラリ不足は `nixos-binary-runtime`、
devShell のツールと PATH 継承は `missing-tools` を使います。
特定環境での手動 symlink を他環境の標準対処にしません。

設定変更が必要なら元の承認範囲と正本へ戻ります。
拒否された経路の迂回や恒久 allow の追加で観測を成立させません。
