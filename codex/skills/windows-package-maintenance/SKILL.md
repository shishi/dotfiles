---
name: windows-package-maintenance
description: winget・Scoop の導入、一括更新、自己更新ロック、終了コードと導入状態の不一致を扱う。Scoop manifest の更新は scoop-manifest を使う。
---

# Windows パッケージの導入と更新

対象一覧と既存の実行スクリプトを正本から読み、各パッケージの実状態で成否を確認します。
この skill の選択だけでは、導入、全件更新、昇格、起動中アプリの停止を承認したことになりません。

## 対象と実行元

1. 対象の package ID、source、user/global scope、実バイナリと版、更新前の状態を確認します。
   既存の一覧や wrapper を複製せず使います。
2. winget は [導入と結果確認](references/winget.md)、Scoop は
   [一括更新とロック](references/scoop.md) を読みます。併用時も両者の scope と exit code を混同しません。
3. 非対話・初期セットアップでは利用可能な runtime を確認します。
   まだ存在しない pwsh/gsudo を bootstrap の前提にしません。
4. 更新中の自己ロック、UAC、installer の UI 待ちを確認し、必要な人間の操作は表示前に予告します。

## 実行と照合

- 承認された対象を実行し、対象ごとの出力、終了値、最終状態を保持します。
  一件の失敗で後続が消えた場合を、後続の成功に数えません。
- 非ゼロ終了だけで再導入せず、MSIX 登録、Uninstall 登録、実行ファイル/版と更新一覧を照合します。
  逆にコード 0 だけで全件成功としません。
- 進捗は子 installer、ログ、I/O も確認します。親の CPU が 0 というだけで kill しません。
- 再試行前に現在の実状態を読み、重複導入や別 source からの置換を避けます。
  hash 不一致を通常の更新として無視せず、配布物と manifest の原因を調べます。
- 終了後は更新済み、未実行、失敗、再起動/新規セッション待ちを分け、同じ対象の版を再取得します。

不足 CLI をどこから供給するかは `missing-tools`、Scoop の checkver/autoupdate/hash は
`scoop-manifest`、シェルやレジストリの観測差は `windows-script-diagnostics` が扱います。
