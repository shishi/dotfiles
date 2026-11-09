---
name: windows-backup-validation
description: Windows の VSS・rclone バックアップで、実スナップショット、除外、リンク先、スケジュール実行、復元を検証する場合に使います。
---

# Windows バックアップの実受入

保存対象と復元条件は、対象 repo の README、filter、実行 script、関連記憶から取得します。個人の remote 名や保存先を skill に固定しません。

## 対象と削除の意味

- 実際に読む設定ファイルと remote の接続先を確認します。`rclone.conf` の難読化された password も credential として扱い、本文やログへ出しません。
- `sync` は宛先の余剰データを削除します。元の保持方針を確認し、検証に本番の削除を持ち込まず隔離先や既存 DryRun を使います。`--ignore-errors` は I/O エラーがあっても削除するため、列挙失敗の対処として追加しません。
- 除外は実パスと filter の順序で確認します。広い部分一致で lockfile、LevelDB の log、利用者の文書まで落ちていないか、実データの対象集合と対比します。
- symlink/junction の保存方針を確認します。rclone の既定ではスキップされるため、リンク本体・参照先のどちらを保護するかを決め、別ジョブも含めて欠落と二重化を照合します。追従 option を無条件に追加しません。

## 実行経路と復元

1. スタブ試験、実 VSS、転送、復元を分けます。実 VSS の受入は必要な権限で snapshot を作り、mount 先の入力を実際に列挙する経路で確認します。VSS を無効にした DryRun だけでは証明できません。
2. スケジュール実行は登録された account と logon type で NAS の列挙・読み書きを確かめます。対話 shell の成功を代用しません。S4U は network と暗号化ファイルにアクセスできないため、必要な認証方式を既存方針と照合します。
3. バックアップ先から隔離した復元先へ戻し、必要なファイル内容・アプリデータ・権限と起動を確認します。WSL やデータベースは、採用している snapshot/export 方式と復元入口に合わせます。
4. 終了値に加え、列挙漏れ、skip/NOTICE、転送結果、復元結果を確認します。作成した snapshot と mount は今回の所有対象だけを片付け、予定どおり解放されたことを確認します。

[rclone sync](https://rclone.org/commands/rclone_sync/)、[filter](https://rclone.org/filtering/)、[local backend のリンク](https://rclone.org/local/#symlinks-junction-points)、[Task Scheduler の logon type](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_logon_type) を使用版と照合します。
