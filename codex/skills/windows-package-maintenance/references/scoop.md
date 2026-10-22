# Scoop の一括更新とロック

## 対象を確定する

per-user の Scoop 本体/bucket と global app root を分け、対象環境の help と実装で確認します。
既存の更新 wrapper があるなら、その入口、除外、失敗時の継続方法を読みます。
`update *` に未確認の除外 option を足さず、除外が必要なら対象名を列挙します。
[更新処理の一次資料](https://github.com/ScoopInstaller/Scoop/blob/master/libexec/scoop-update.ps1)

hash 等で途中終了した際に、後続が実行されない/終了値が成功になる版の実測があります。
その条件ではアプリ別の子 process に分けて結果を回収する既存 wrapper を使います。
一括 command の終了値と各 app の実行済み状態を分けます。

## 実行中アプリと自己更新

- 対象の process とファイルの使用状態を読みます。診断だけの依頼で停止しません。
- pwsh 自体の更新では、Scoop を別 shell で起動しても呼出元 pwsh がファイルを保持して
  いないか確認します。必要なら承認された更新を cmd/Windows PowerShell 等から実行します。
- global 更新は対象と権限を確認し、`-g` を維持します。global 専用 installer へ user 更新を
  渡すと途中状態になり得るため、旧版撤去前に scope を確認します。
- 昇格 launcher の別 console から出力が戻らなくても成功とせず、対象の実状態を読みます。

## 更新後

`scoop status`、導入済み version、`current` の実リンク先、実行ファイルの版を照合します。
更新が残っている理由を、実行中 skip、hash/展開失敗、未実行、scope 間違いに分けます。
`current` と実 version path の違いが二重起動やショートカットへ影響する場合は、起動元の
登録と command line を調べます。OS 全アプリの自動再起動を一律に無効化しません。

Scoop uninstall だけでは、アプリ自身が作ったサービス/タスク/別配置が消えない場合が
あります。対象アプリの既存 uninstall 手順を読み、入口のショートカットと保存された
登録の寿命を区別します。固有バイナリ形式や registry を推測で直接編集しません。
