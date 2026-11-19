# Herdr アプリの設定

`herdr-app/` には Herdr アプリのキー割当と mod を置いています。`setup.sh` が Herdr アプリのホーム (`~/.config/herdr-app`、または `HERDR_APP_HOME`) へ配備します。

## macSKK の Ctrl+J (macOS)

Herdr のターミナルで、macSKK の Ctrl+J (ひらがなモードへの切り替え) を使えるようにしています。

### なぜ必要か

Herdr は、未確定文字が無いときの Ctrl 付きキーを、入力メソッドより先にターミナルのプログラムへ送ります。そのため直接入力モードで Ctrl+J を押しても macSKK には届かず、改行が入力されます。キー割当には入力メソッドへキーを渡す操作が無く、`send:` を割り当てても macSKK には届きません。Herdr アプリ 0.1.16 で確認した挙動です。

未確定文字があるときは、Herdr がすべてのキーを入力メソッドへ先に渡します。変換中の Ctrl+J (確定) と Ctrl+G (キャンセル) は、この対応が無くても macSKK に届きます。

### 仕組み

1. `keys.macos.json` が、ターミナルの `ctrl-j` を mod のコマンド `skk-kana.hiragana` に割り当てます。
2. mod `skk-kana` がコマンドを受け取り、`select-input-source` を実行します。
3. `select-input-source` が、macOS の入力ソースとして macSKK のひらがなモードを選びます。

Ctrl+J を Ctrl 無しのキーへ置き換える方法 (かなキーへの割り当てなど) もありますが、ほかのアプリと同じ Ctrl+J で操作するためにこの方法を採っています。

### 失うもの

Herdr のターミナルでは、未確定文字が無いときの Ctrl+J がプログラムへ届きません。Ctrl+J を改行として受け取るプログラムでは、Enter など別のキーを使います。

mod `skk-kana` を置いていないレイアウトでは、Ctrl+J を押してもひらがなモードへ切り替わりません。下の「配備」の手順でレイアウトへ配置します。

### 配備

`setup.sh` が mod を配備し、`swiftc` で `select-input-source` をビルドします。`swiftc` が無い場合やビルドに失敗した場合は、Xcode Command Line Tools を入れてから `setup.sh` を再実行します。

Herdr は、表示中のレイアウトにある mod にだけキーのコマンドを届けます。レイアウトへの配置は Herdr のコマンドで行うため、端末ごとに一度だけ次の手順が必要です。

1. Herdr アプリを起動した状態で、レイアウト `main` を複製します。Herdr は複製したレイアウトへ表示を切り替えます。

   ```sh
   herdr-app do layout.clone --name main --as main-skk
   ```

2. `layouts/main-skk.json` で、`"id": "status"` のブロックと同じ `children` の末尾に次のブロックを足します。

   ```json
   { "id": "skk-kana", "type": "block", "size": { "px": 1 }, "content": { "mod": "skk-kana" } }
   ```

複製したレイアウトは、Herdr の更新で `main` が変わっても追従しません。`main` の変更を取り込むときは、別の名前で複製し、そのレイアウトのファイルで手順 2 をやり直します。Herdr は既にある名前への複製を拒否します。
