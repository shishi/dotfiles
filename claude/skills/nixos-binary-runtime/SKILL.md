---
name: nixos-binary-runtime
description: NixOS で外部配布の Electron/Chromium 等が ELF interpreter や共有ライブラリ不足で起動しない場合に診断します。キャッシュからの取得可否は nix-binary-cache を使います。
---

# NixOS の外部バイナリ起動

既存の Nix パッケージとプロジェクト環境で必要機能を満たせるかを先に確認します。
ここでは一般の Linux 向けバイナリと NixOS の runtime の差を診断します。
ホスト固有の設定と過去の成功例は関連記憶から取得します。

1. 実際の実行ファイルを特定し、アーキテクチャ、ELF interpreter、必要な共有ライブラリ、
   RPATH / RUNPATH を調べます。ラッパーの存在と実 ELF を分けます。
   `file`、`readelf`、`patchelf --print-interpreter` / `--print-rpath` などを使います。
2. loader 不在と、loader が動いた後のライブラリ不足を分けます。
   `nix-ld` が有効でも、必要なライブラリが一式あるとは判断しません。
   `NIX_LD` と `NIX_LD_LIBRARY_PATH` の実効値・対象 system を確認します。
3. 不足ライブラリを既存の同系 nixpkgs パッケージの依存と照合します。
   Chrome の依存を Electron へ一括流用せず、GTK の世代や ABI の違いを確認します。
   Nix でパッチ済みの実行ファイルは nix-ld の環境変数を使わない場合があります。
4. 一時的な依存追加は対象プロセスに限定します。
   `LD_LIBRARY_PATH` をログイン環境全体へ export すると、正常な Nix プログラムにも
   別のライブラリを注入するため、検証用ラッパーなどで範囲を限定します。
5. FHS 環境や別の wrapper を使う場合は、必要な依存と `/tmp` 等の mount の扱いを確認します。
   過去の特定環境での失敗を、その方式全体の実行不能とは判断しません。
6. 元の入口から実際に起動し、必要な画面・描画・入力まで確認します。
   依頼が継続利用を含む場合は、既存の Nix 構成へ反映し、新しい環境でも起動を確認します。
   一回限りの環境変数設定を宣言済みの配備と混同しません。

ホストの loader や `/bin` への手動 symlink 作成を標準の対処にしません。
実行環境の追加・変更は元の依頼と既存の構成管理の範囲に従います。
設定と制限は [nix-ld の仕様](https://github.com/nix-community/nix-ld) で確認します。
