# ロック・撤去・再起動

## 解放と登録

変更前に、対象パス、登録値、scope、退避先、自分が追加した resource 参照を控えます。
ファイルが在る間に対応する Remove API を呼び、登録を取り除いてからファイルを削除します。
登録が消えた後も、控えとの照合で削除待ちの対象を追跡します。

`RemoveFontResource` 後も使用中の device context や他 session があればロードが残ります。
公式の置換例は成功した Remove 数と同じ回数だけ再追加しています。既存 installer の
参照所有を確認せず、第三者の参照を drain する loop を独自に足しません。
[RemoveFontResourceW](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-removefontresourcew)

## 使用中ファイル

sharing violation と access denied を区別し、必要なら承認された handle 調査で保有元を
確認します。昇格しても共有違反は解消しません。診断対象以外のアプリを一括終了したり、
handle を強制 close して解決した扱いにしたりしません。

ログオン時にロードされたフォントや他 session の参照がある場合、同じ session 内だけの
uninstall 試験では最終状態を確認できないことがあります。必要なら再ログオン/再起動を
検証条件にし、既存プロジェクトの「実機 lifecycle を実行しない」制約も維持します。

## 再起動時の削除

その対象の削除と必要な昇格・再起動が承認済みで、通常の解放では完了できない場合に使います。
`MoveFileExW` の `MOVEFILE_DELAY_UNTIL_REBOOT` と新パス NULL は、ローカルファイルの
削除を予約します。戻り値は予約登録の成否であり、後日の削除成否ではありません。
[MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)

- `PendingFileRenameOperations` の MULTI_SZ を手書きで置換せず API を使います。
- PowerShell の P/Invoke では NULL が空文字へ変換されない signature を使います。
  `IntPtr` の `[IntPtr]::Zero` 等で native NULL を表し、戻り値と last error を確認します。
- 同じ仮想 registry view の readback だけで実機への予約を証明しません。
- 再起動後は予約の消費と実ファイル不在を照合します。予約値が消えたことだけでは
  実削除成功としません。user/global の不要な登録も別に確認します。
