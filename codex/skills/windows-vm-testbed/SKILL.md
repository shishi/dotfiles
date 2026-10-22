---
name: windows-vm-testbed
description: Windows の初期セットアップ、再起動を伴う導入・撤去、ホストを壊す変更を使い捨て VM で検証する。VirtualBox の無人導入、guestcontrol、GUI 入力と結果回収を扱う。
---

# Windows の検証用 VM

検証したい Windows の条件を再現し、入力から最終結果まで回収できる VM を使います。
既存 VM が要件を満たせば再利用します。この skill の選択だけでは VM 作成、ISO 取得、
ホストの仮想化設定変更、UAC policy の変更を承認したことになりません。

## 用意する

1. 必要な OS、Store/winget、再起動、管理者、GUI を確認します。
   Windows Sandbox 等で条件を満たせるかは実構成で判断します。
2. 既存 VM と使用中の資源を確認し、対象 UUID、ディスク、媒体、ログの範囲を決めます。
   他の VM や稼働サービスを巻き込みません。
3. 新規作成や無人導入は [作成と OS 導入](references/provisioning.md) を読みます。
   ホスト/VirtualBox/ゲストの版を記録し、過去の回避策を既定へ固定しません。

## 実行して回収する

4. [ゲストとの入出力](references/guest-io.md) で、Guest Additions の実動作に応じて
   ファイル配置、実行、結果回収の経路を確保します。GUI/UAC が必要なら対話 desktop を使います。
5. 元の検証 script を同じ shell/権限/起動入口から実行します。guestcontrol での成功を
   対話起動や初回ログオン時の成功に置き換えません。
6. 遅い・無反応・撮影不能の場合は [観測と復旧](references/observation.md) を読み、
   画面、I/O、ログ、CPU を照合してから介入します。
7. 結果、再起動後の保持、実際の利用経路を確認します。終了コード、操作反応、完了時刻を分けます。
8. 結果をホストへ回収し、通常の guest shutdown と VM の停止を確認します。
   成果を保全して、今回作った不要な VM/媒体だけを承認済み範囲で片付けます。

guest credential は skill、ログ、公開文書へ書きません。自動昇格のためにホストや通常の
VM の UAC を無効化しません。パッケージの結果判定は `windows-package-maintenance`、
文字コード/シェルの差は `windows-script-diagnostics` を使います。
