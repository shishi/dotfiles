# シェル・文字コード・WSL の境界

## パスと引数

- Git Bash のランチャーと stdout を返す `bash.exe` を区別します。設定する実行ファイルは
  対象環境から解決し、特定ユーザーの Scoop パスをコピーしません。
- MSYS は `/s` などの Windows CLI の引数をパスへ変換する場合があります。
  破損した引数を確認してから、その呼出しに限って変換を調整するか PowerShell 側で組み立てます。
  `MSYS_NO_PATHCONV` は子へ継承されるため、内側の Git/Scoop まで含めて確認します。
- Bash → 昇格 launcher → PowerShell のように解釈が重なる場合は、PowerShell のファイルへ
  処理を置き `-File` で渡します。引数に出すパスを減らし、PowerShell 側の `Join-Path` を使えます。
- 長文、JSON、正規表現はファイル編集ツールで書いてから渡します。heredoc が壊れた場合、
  引用を何層も重ねる前に渡したファイルの bytes と実行シェルを確認します。
- `uname` の結果には Windows ビルド番号等が付く場合があります。判定が必要なら実値と
  必要なプラットフォーム条件を照合します。

## 文字コードと改行

Windows PowerShell 5.1 は BOM のないスクリプトを従来の ANSI codepage として読むため、
非 ASCII を含む `.ps1` は UTF-8 BOM 等の対応する形式にします。PowerShell 7 の既定値は
異なります。実運用が 5.1 なら `powershell.exe -File` でも確認します。
[PowerShell の文字コード](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)

- jq/native Python の出力を Bash で受ける場合は CR の有無を bytes で確かめます。
  行末 CR が原因の場合だけ境界で除去し、ファイル内容の CR を無差別に消しません。
- 改行の採取は `tr -cd '\r' | wc -c` と `tr -cd '\n' | wc -c`、または hex dump で対比できます。
  正規表現自体が壊れていないか、LF だけの既知の入力でも確認します。
- Python の text mode は Windows の改行へ変換する場合があります。既存形式を維持する
  `newline` 指定や binary mode を使い、全行差分になっていないか確認します。
- tzdata のない Git Bash では `TZ=<zone>` だけで必要な時刻を得られない場合があります。
  Windows の実タイムゾーンと出力の offset を照合し、日付/曜日の境界も確認します。

## WSL とリンク

Windows 上のツールへ Linux の `/home/...` を渡しても WSL 内へ届く保証はありません。
まず実行主体と distro を確認し、WSL 側の操作は対象 distro の `wsl.exe` 経由、または
対応する `\\wsl.localhost\<distro>\...` を使います。Linux 内のツールには不要な経路を足しません。
書込後は WSL 内で同じファイルを読み、Windows 側の別パスへ生成していないことを確認します。
[WSL のファイルシステム](https://learn.microsoft.com/en-us/windows/wsl/filesystems)

MSYS の `ln -s` は構成によりコピーへフォールバックします。symlink が必要な配備では
native strict mode と必要な OS 権限を確認し、実リンク先まで検証します。稼働中プロセスの
cwd が Windows 上でディレクトリの削除を阻む場合は、worktree 登録の解除と実ディレクトリの
残存を分け、別の有効な cwd から承認済み範囲の片付けを確認します。
