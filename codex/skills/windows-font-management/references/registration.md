# 登録とロードの照合

## scope と永続化

Windows の通常のフォント導入には user 向けと全ユーザー向けの入口があります。
既存 installer と依頼の scope を保ち、管理者権限を不要に広げません。
[Windows のフォント管理](https://support.microsoft.com/en-us/windows/experience/personalization/manage-fonts-in-windows)

`AddFontResource`/`AddFontResourceEx` の呼出しだけでロードしたものは一時的です。
永続化には対応する配置と登録が必要で、API 成功だけでは再起動後の存在を証明しません。
[GDI の導入と削除](https://learn.microsoft.com/en-us/windows/win32/gdi/font-installation-and-deletion)

user-scope が再ログオン後に使えないという実測がある場合は、OS/導入方式/対象を記録し、
同条件でファイル、ACL、登録、実ロードを確認します。FontCache のファイルや registry の
一致しない観測だけから Windows 全体のロードアルゴリズムを断定しません。
プロジェクトが global 専用を選んでいる場合は、その個別契約を維持します。

## 検査する層

| 層 | 確認するもの |
|---|---|
| ファイル | 実パス、bytes/hash、フォント内部の名前/形式、ACL |
| 登録 | 対象ユーザーまたは machine の Fonts 値と実パス、同名の user/global 登録 |
| resource | Add/Remove の API と flag、成功数、通知、session |
| 列挙 | 新規 process の GDI/DirectWrite。private/non-enumerable の指定も確認 |
| 描画 | 対応 API の実アプリで、対象文字と fallback を区別 |
| 永続化 | 必要な再ログオン/再起動後の同じ検査 |

`AddFontResourceEx` の `FR_PRIVATE` は process 内、`FR_NOT_ENUM` は非列挙の指定です。
これらを通常のシステム列挙と比較しません。Ex 系には対応する RemoveEx を使います。
[AddFontResourceExW](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-addfontresourceexw)

通知が必要な経路では `WM_FONTCHANGE` を使い、待ち時間を制限してハングした window を
待ち続けないようにします。既存 installer と異なる登録名を推測で追加せず、フォントの
name table と既存登録との対応を確認します。

列挙 object の cache が疑われたら、新しい object だけでなく別 process でも読みます。
`PrivateFontCollection` 等の disposable resource は finally 等で解放します。
例外を握りつぶして件数の減少をフォントの不在と報告しません。

カラーフォントはテーブル形式と描画 API/OS の対応を照合します。設定画面の tofu は
対象文字や fallback の不足でも起こるため、別の対応アプリでも対象 glyph を描きます。
[DirectWrite のカラーフォント](https://learn.microsoft.com/en-us/windows/win32/directwrite/color-fonts)
