# winget の導入と結果確認

## 実行する前提

`winget --version`、`winget --info`、source と `Get-Command winget` を確認します。
App Installer の appx version と CLI version を同じ値と扱いません。
初回ログオン直後は App Installer の登録が完了していない場合があるため、いきなり
別版を導入せず登録状態を調べます。更新が必要なら、その依存 installer の UAC も考慮します。

fresh Windows 向け script は Windows PowerShell 5.1 等、実在する下限環境で検証します。
非 ASCII を含む script の encoding は `windows-script-diagnostics` で確認します。
診断や DryRun の依頼では App Installer を含め更新しません。

## ID・scope・architecture

- 現在の source で `search`、`show` を行い、ID と実際に選ばれる installer を確認します。
  `--exact` は case-sensitive です。`--scope` と architecture も選択条件になります。
  [install command](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)
- scope なしなら見つかるかを読み取りで対比し、ID 不在と installer 不適合を分けます。
  scope の宣言がない package を二つの scope の列で漏らさないようにします。
- 同名でも source、ProductCode、installer type が違えば別導入になり得ます。
  `--no-upgrade` だけで、別 source の既存アプリまで冪等になると仮定しません。
- upgrade が進まないときは選択 architecture と既存登録、manifest の upgrade policy を
  確認します。tracking database を直接編集して直そうとしません。

## 結果と進捗

終了値は実行版の `winget error` または公式の定義で解釈します。
already installed/no applicable update と処理失敗を分けます。
コードの説明に 16 進が必要な版では、符号付き値を `0x` + 8 桁へ変換して照合します。

成否は同一アカウントの `Get-AppxPackage`、HKLM/HKLM WOW6432Node/HKCU の Uninstall 登録、
実ファイルの版を必要に応じて組み合わせます。権限/アカウントで列挙範囲が変わるため、
現在ユーザーの空結果から全ユーザーの不存在を判断しません。
コマンドが見つからない場合は、新規 process の PATH と実ファイルも確認します。

ログ位置は `winget --info` から解決します。調査 command もログを増やすため、対象処理の
command line、時刻、PID を照合します。最新ファイルだけを本処理としません。
[ログの公式手順](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)

MSI の 1618 は他 installer の進行も確認します。msiexec、ログ更新、I/O を観測し、
親 winget の idle を停止と取り違えません。非対話実行で window 作成 timeout がある場合は、
対話 desktop から同じ対象で比較します。サービス経由の結果を通常利用の証拠にしません。
