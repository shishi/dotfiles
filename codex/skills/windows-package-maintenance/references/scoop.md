# Scoop の導入・一括更新とロック

## 導入時の自動更新

`scoop install` は、前回の更新から 3 時間以上たっている場合 (前回の記録が無い場合を含む)、
導入の前に Scoop 本体と全 bucket を `git pull` で更新します。git に
`url.<base>.insteadOf` の設定があれば、この通信は SSH などの別経路と認証を使います。
導入する manifest が手元の bucket にあり、その版で足りる場合は、`scoop install -u`
(`--no-update-scoop`) で導入し、依頼にない更新と通信を起こしません。

manifest の有無と版は、通信しない command で確かめます。

- `scoop cat <bucket>/<app>` は手元の bucket の manifest を読みます。URL や、URL から
  導入したアプリを渡した場合だけ取得の通信をします。
- `scoop search` は手元に一致があれば手元だけで終わりますが、一致が無いと GitHub API で
  未追加の bucket を検索します。有無が分からない名前の確認には `scoop cat` を使います。
- 導入後の照合は `scoop list <app>`、`current` の実リンク先、実行ファイルの版で行います。
  `scoop status` は本体と各 bucket に `git fetch` を実行します。`-l` (`--local`) は
  この fetch だけを止め、URL から導入したアプリがあればその manifest を取得します。

manifest が見つからない場合は、更新の前に原因を分けます。名前の誤りなら正しい名前で
確かめ直します。bucket が未追加なら、`scoop bucket known` で追加先を確かめ、追加することを
伝えてから `scoop bucket add` を実行します。既存 bucket の更新では未追加の bucket の
manifest は得られません。既存 bucket が古く新しい版が要る場合だけ、更新することと
通信先を先に伝えてから `scoop update` を実行します。`scoop update <app>` も
同じ条件で本体と全 bucket を同期し、止める option はありません。
[導入処理の一次資料](https://github.com/ScoopInstaller/Scoop/blob/master/libexec/scoop-install.ps1)

## 一括更新の対象を確定する

per-user の Scoop 本体/bucket と global app root を分け、対象環境の help と実装で確認します。
既存の更新 wrapper があるなら、その入口、除外、失敗時の継続方法を読みます。
`update *` に未確認の除外 option を足さず、除外が必要なら対象名を列挙します。
[更新処理の一次資料](https://github.com/ScoopInstaller/Scoop/blob/master/libexec/scoop-update.ps1)

hash 等で途中終了すると、後続が実行されず終了値が成功になる場合があります。
対象版の実装と結果を確認し、その条件ではアプリごとの子 process で結果を回収する既存 wrapper を使います。
一括 command の終了値と各 app の実行済み状態を分けます。

## 実行中アプリと自己更新

- 対象の process とファイルの使用状態を読みます。診断だけの依頼で停止しません。
- pwsh 自体の更新では、Scoop を別 shell で起動しても呼出元 pwsh がファイルを保持して
  いないか確認します。必要なら承認された更新を cmd/Windows PowerShell 等から実行します。
- global 更新は対象と権限を確認し、`-g` を維持します。global 専用 installer へ user 更新を
  渡すと途中状態になり得るため、旧版撤去前に scope を確認します。
- 昇格 launcher の別 console から出力が戻らなくても成功とせず、対象の実状態を読みます。

## 更新後

各アプリの結果は、導入後と同じく `scoop list <app>`、`current` の実リンク先、実行ファイルの版で照合します。
既存の wrapper で更新した場合は、その wrapper の成否の判定 (実行前後の `scoop status` の比較など) に従います。
更新が残っていないかは、本体と bucket を同期した後の手元の manifest で判定します。`scoop status` は
アプリの版を手元の manifest と比べるので、bucket が古いとリモートにだけある新版が一覧に出ません。
`scoop update` は bucket ごとの `git pull` の失敗を終了結果に反映しないので、成功の表示だけでは
対象アプリの bucket が同期できたとは判断しません。対象の bucket のディレクトリ (既定は
`~/scoop/buckets/<bucket>`) で `git fetch` を実行し、その終了コードが 0 のときだけ `git status -sb` で
リモートより遅れていないことを確かめ、`scoop status -l` で一覧を取ります。`git fetch` が失敗した bucket は
追跡先が古いままで遅れが表示されないので、遅れていた bucket と同じく同期をやり直し、
成功を確かめるまで「残る更新なし」と判定しません。
更新が残っている理由を、実行中 skip、hash/展開失敗、未実行、scope 間違いに分けます。
`current` と実 version path の違いが二重起動やショートカットへ影響する場合は、起動元の
登録と command line を調べます。OS 全アプリの自動再起動を一律に無効化しません。

Scoop uninstall だけでは、アプリ自身が作ったサービス/タスク/別配置が消えない場合が
あります。対象アプリの既存 uninstall 手順を読み、入口のショートカットと保存された
登録の寿命を区別します。固有バイナリ形式や registry を推測で直接編集しません。
