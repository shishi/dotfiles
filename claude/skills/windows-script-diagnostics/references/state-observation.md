# レジストリ・プロセスの実状態

## 空の結果を解釈する

- `-ErrorAction SilentlyContinue` の再帰列挙は読めない subtree を隠します。
  不在を判断する前に対象ルートを `-ErrorAction Stop` で開き、列挙エラーも回収します。
- 非昇格から昇格プロセスの `CommandLine`/`ExecutablePath` が読めないことがあります。
  空値を終了済みや保護プロセスの証明にせず、PID、生成時刻、取得可能な情報を使います。
- Procmon に現れないことは、IPC や共有メモリを使っていない証拠にはなりません。
  ドライバーや昇格が必要な採取は、既存の承認範囲を確認して行います。
- binary の文字列調査では Unicode の採取方式も確認します。ASCII 寄りの `strings` の
  空結果を不存在とせず、対応する encoding option や Sysinternals の実行版で対比します。

## 仮想化とビュー

MSIX の仮想化対象アプリでは、レジストリの読取りが実ハイブとパッケージのマージに、
HKCU の書込みがアプリ専用領域になる場合があります。アプリの package identity と設定を
確認し、すべての Windows CLI が同じ方式だと決めつけません。
[パッケージ化 desktop app の実行](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)

`reg.exe` と .NET を同じ子プロセス境界から実行しても、独立した実ハイブの検査には
ならない場合があります。UI、承認された外側プロセス、WMI `StdRegProv` 等から照合します。
WMI でも実行アカウント・hive・32/64-bit view を確認し、HKCU が目的ユーザーを指すか検証します。
`StdRegProv` の return value と列挙結果を分け、成功通知だけで一致としません。
[WMI のレジストリ操作](https://learn.microsoft.com/en-us/windows/win32/wmisdk/wmi-tasks--registry)

Explorer の shell と folder window が別プロセスの場合は片方の再起動だけで揃いません。
再起動を試す前に対象 PID/起動時刻とレジストリ更新時刻を照合します。
コンテキストメニューの API 列挙では hwnd 等の条件で欠落し得るため、問題が UI 表示なら
実メニューも確認します。

## PowerShell の測定値

| 条件 | 確認する内容 |
|---|---|
| `@($null).Count` が 1 | 欠落と 1 要素配列を分け、null を明示的に扱います |
| JSON 配列の反復がおかしい | 実行版の pipeline 列挙を確認し、変数へ受けて各要素を `foreach` で読みます |
| `foreach` の結果へ別値が混ざる | block 内の外部 stdout も結果になります。必要なら表示と戻り値を分けます |
| 外部 command の stderr で中断 | script の `$ErrorActionPreference` と PowerShell の版を確認し、外部の終了値も採取します |
| pipeline 後の成功 | 最後の段だけの結果か確認し、対象 command 直後の `$LASTEXITCODE` を保持します |
| `-LiteralPath` と `-Include` | 既知の複数拡張子の入力で本当に絞れたか確認します |
| P/Invoke に null を渡す | `[string]` への変換で空文字にならないよう、native NULL と signature を照合します |
| 関数が呼ばれない | `Get-Command` で alias と function の解決順を確認します |

PowerShell 5.1 の構文を想定する場合は、その実行版でも parse/実行します。
代入以外の式の位置に置いた `if` は subexpression が必要な場合があるため、
PowerShell 7 だけの成功を互換性の証拠にしません。

`Stop-Service` の例外だけで停止失敗とせず、対象サービスの状態を期限つきで再取得します。
NTFS LastAccessTime は即時更新を保証しないため、直後の不変値を未アクセスの証拠にしません。

UAC が必要な承認済み操作は表示前に予告します。キャンセル例外だけでは本人拒否、
timeout、非対話 desktop による表示不能を区別できません。実行元と UI の有無を照合し、
許可されていない昇格や恒久的な UAC 無効化へ置き換えません。
昇格のキャンセルで独立した非昇格処理まで中断する場合は、既存のエラー契約を確認して
昇格フェーズの失敗と後続の実行可否を分けます。
