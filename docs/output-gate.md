# 出力ゲート

出力ゲートは、Claude Code と Codex の回答を作業の証拠と照らして検査します。確認していない主張、依頼の抜け、未解決の失敗を隠す記述、応答規則の違反を判定します。

## 利用方法

状態ファイル `${XDG_STATE_HOME:-$HOME/.local/state}/output-gate/codex.json` がない場合、Codex の hook が出力ゲートを有効にします。状態ファイルがある場合は、有効・無効の設定を維持します。`setup.sh` を先に実行した環境では、最初のセッションから検査します。検査に伴う[外部サービスへの送信](#検査役のモデル)を確認してください。

`enable` が設定を変更し、共有 daemon の稼働を確認できた場合は、daemon を再起動します。接続中のセッションは中断されます。再起動後の daemon は、`enable` を実行した環境変数を引き継ぎます。

hook が初回に設定した場合は、起動中のすべての Codex セッションを再起動してください。共有 app-server を使っている場合は、それも再起動します。設定前に開いたセッションは古い接続先を使い続けます。再起動するまでは入力せず、停止された入力は再起動後に送り直してください。対話 CLI では、画面を開いただけでは hook は動かず、最初の入力時に動きます。初回設定に失敗した場合は停止し、次の入力または起動で再試行します。

`codex exec` では、初回停止の理由が表示されない場合があります。hook の信頼と設定を確認し、起動中の全セッションを再起動してから再実行してください。

**中継は一人で使うマシンに限ります。** 共有マシンで状態ファイルがない場合は、Codex または `setup.sh` の起動前に無効状態を作成してください。既存の Codex 設定は変更しません。

```sh
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/output-gate"
printf '{"enabled": false, "port": 0}\n' > "${XDG_STATE_HOME:-$HOME/.local/state}/output-gate/codex.json"
```

既に中継を有効にしている共有マシンでは、次の `disable` を使ってください。設定後も次のコマンドで切り替えられます。切り替えた後は Codex を起動し直してください。

```sh
bash ~/.agent-shared/hooks/output-gate-codex.sh enable
bash ~/.agent-shared/hooks/output-gate-codex.sh disable
```

有効化後と `codex/hooks.json` の更新後は、Codex の `/hooks` で出力ゲートの Stop・SessionStart・UserPromptSubmit・PreCompact・PreModelRequest hook を信頼してください。中継の再起動は hook が担うため、信頼していない状態で中継が止まると Codex は接続できません。

Claude Code の出力ゲートは既定で無効です。次のコマンドで切り替えます。

```sh
bash ~/.agent-shared/hooks/output-gate-claude.sh enable
bash ~/.agent-shared/hooks/output-gate-claude.sh disable
```

Windows と WSL はそれぞれ状態を管理します。両方で使う場合は、それぞれの環境で設定してください。

検査には Python 3.11 以降、gitleaks、検査役のログインが必要です。Codex の中継が上流へ圧縮して送るには Python 3.14 以降が必要です。

## 検査と表示

検査役には、依頼、会話、回答、ツール呼び出しと結果、応答規則を渡します。送信前に gitleaks で秘密情報を検出し、伏せた後に再検査します。伏せられない場合は送信しません。

未達がある場合は、利用可能な経路では回答を保留し、指摘をエージェントへ返して同じセッションで続行します。次の回答も検査し、前回の本文・指摘・証拠と比較して進捗を判定します。未達の解消、原因の絞り込み、次の判断につながる新事実の確認を進捗とします。回答や指摘の言い換え、同じ結果の再検査、既に確認した事実の再発見は進捗に数えません。

停滞または進捗の判定不能が 3 回の修正で連続すると、より高い推論量の別の検査役が最新の証拠で再判定します。未達がなくなれば本文を表示し、進捗があれば修正を続けます。再判定でも停滞・判定不能なら、自動差し戻しを止め、未解決であることと最新本文・指摘を表示します。再判定を取得できない場合も、最初の検査で得た本文・指摘を残して停止理由を表示します。停止を検査合格とは扱いません。

進捗があれば停滞回数を戻し、修正の総回数では打ち切りません。進捗は意味による判定なので、誤判定による早すぎる停止や反復の継続は残ります。すべての無限ループを排除する保証ではありません。継続に必要な状態を保存できない場合は、自動差し戻しを続けません。通常検査そのものに失敗した場合は、確認が未完了であることと原文を表示します。

Codex はローカルの HTTP 中継で応答を検査します。修正を続ける場合は未達の回答を保留し、指摘をエージェントへ渡します。停滞で停止する場合は、上記の未解決表示を使います。中継を通さない委譲・レビューの出力は検査しません。`/review` の JSON は説明欄だけを検査し、構造を維持します。

Claude Code は mod で回答を検査します。Desktop の WSL セッションでは代わりに表示 hook と Stop hook を使います。この経路ではストリーム中の原文や Stop hook の指摘が表示される場合があります。mod 自体を外すには、`claude/settings.json` の `CLAUDE_CODE_PLUGIN_DIRS` を外して再起動します。

途中の発言、推論、音声会話などは最終回答と同じ表示前検査の対象ではありません。クラウドや Desktop・IDE の環境では、対象の設定と hook が読み込まれるかを確認してください。

## 中継の制約と復旧

中継には会話と認証ヘッダーが届きます。`127.0.0.1` で待ち受け、ヘッダーと本文はログに残しません。別のユーザーが使うマシンでは、別ユーザーのプロセスがポートを取得すると認証情報を受け取れるため、中継を有効にしないでください。Codex の認証情報はファイルに保存する設定で、同じユーザーのプロセスは中継を通さず直接読めます。

中継は WebSocket を受け付けず、Codex は HTTP に切り替えます。そのため WebSocket の事前接続と差分送信は使えません。`token_budget`、`context_management`、`output_token_replay`、`enable_request_compression` は中継の設定で無効になります。この設定は同じ `config.toml` を使う中継対象外のセッションにも適用されます。

中継が使えない場合は無効化して Codex を再起動します。一時的に中継を通さず対話 CLI を起動することもできます。この場合、回答は検査されません。

```sh
codex --no-daemon -c 'openai_base_url=""'
```

未達の回答を保留したままターンが終了した場合、同じセッションの次の入力時に中断された回答を表示します。旧版で保留した回答は、置き換え前の原文を表示します。次の入力がない場合は次のコマンドで回収できます。保存期間は 24 時間です。

```sh
bash ~/.agent-shared/hooks/output-gate-codex.sh held [session_id]
```

## 検査役のモデル

共通の検査処理は、既定で Claude の `opus` / low を試し、使えなければ Codex の `gpt-6.1-terra` / low を使います。そのため Codex と Claude Code の会話やツール出力は、通常は Anthropic に、代替時は OpenAI に送られます。gitleaks が検出した秘密情報以外は伏せません。Claude Code の mod の Claude 検査は、セッションの接続先を使います。

検査順序とモデルは `${XDG_STATE_HOME:-$HOME/.local/state}/output-gate/checker.json` で変更できます。`OUTPUT_GATE_SETTINGS` に別の設定ファイルを指定することもできます。各項目は省略可能です。

停滞時の再判定は通常の設定とは別に Codex の `gpt-6-astra` / high を試し、失敗時は Claude の `fable` / high を試します。Cyber のアクセスプログラムを使うターンでは、対応する Codex モデルを選びます。通常検査とそこからの再判定は、既定 45 秒のモデル呼び出し予算を共有します。`OUTPUT_GATE_TIMEOUT` を指定した場合はその値を使います。秘密情報検査やプロセスの後始末には別途時間がかかります。

```json
{"first":"claude","claude":{"model":"opus","effort":"low"},"codex":{"model":"gpt-6.1-terra","effort":"low"}}
```

`first` は `claude`、`codex`、`same`、`opposite` を指定できます。先に使う提供元を変更しても、失敗時にはもう一方を試します。mod の Claude 検査以外は、モデル提供元の公式サービスを接続先にします。管理者設定による接続先の上書きは除去できない場合があります。

## 実装と検証

共通の検査処理は `agent-shared/bin/output-gate-check.py`、Codex の中継は `agent-shared/bin/output-gate-relay.py`、Claude Code の mod は `claude/mods/output-gate/` にあります。検査規則は `agent-shared/bin/output-gate-rules.json` で管理します。[設計判断](ADR/20261103-213806-output-gate-post-check.md)は検査の目的と制約を説明します。

`tests/output-gate-check.py` と `tests/output-gate-relay.py` は検査処理と中継を検証します。`tests/output-gate-rules-live.py` は実際の検査役を使う手動試験で、時間と利用枠を消費します。
