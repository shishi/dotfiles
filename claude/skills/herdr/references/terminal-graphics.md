# ターミナルのグラフィックス表示を診断する

Herdr 内のブラウザーが動いていても、人間へピクセルが届くとは限りません。server、browser process、表示 client、SSH/terminal の描画経路を分けます。Herdr の操作条件は SKILL.md に従います。

## 表示 client と経路

1. `HERDR_ENV=1` は管理 pane 内の証拠であり、表示 client の接続証明ではありません。実行版の `herdr status` の help を確認し、client/server の状態と人間が見ている terminal を対応づけます。
2. DOM の取得とピクセル描画を別々に確認します。同じ terminal で、使用する Kitty graphics 等の protocol に対応した小さな既知の画像を表示し、browser 以外でも経路を切り分けます。
3. SSH、multiplexer、terminal の各境界を確認します。一つの版で転送できなかった観測を現行版の非対応とせず、対象版の対応情報と実表示を照合します。

## terminal-browser と継承環境

- split の作成は、実行版の `terminal-browser --help` と `open` の help を確認し、対応する親 pane から製品の split 機能を使います。裸の browser process を別 pane に置いたことだけで統合が成立したとしません。
- browser 一覧の schema を確認し、親 terminal と split の対応を調べます。過去の `parentTty` や `splitDir` が現行版にもあると仮定しません。
- WezTerm の制御が終了済み GUI の socket を参照している場合は、対象 process の `WEZTERM_UNIX_SOCKET` と現行 GUI の接続先を対比します。必要なら一回の診断 process だけで変数を外し、session 全体の環境を書き換えません。
- 新しく起動した terminal GUI が `HERDR_*` を継承し、既存 session への接続を nested 起動と判定される場合があります。既存 server と接続先を先に確認し、許可された attach process の継承だけを調整します。新しい server の起動や既存 server の停止を診断の既定にしません。

最後に利用者が見る client で実画像を確認します。browser の登録、DOM 応答、API の成功通知だけで表示成功にしません。

製品の操作と対応 terminal は [terminal-browser の公式 README](https://github.com/zenbu-labs/terminal-browser) と使用版の help を確認します。版限定の制約・クラッシュ・報告先は関連する個人記憶から取得します。
