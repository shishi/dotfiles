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
   Nix でパッチ済みの実行ファイルは nix-ld の環境変数を使わない場合があります。
3. FHS 環境や別の wrapper で動かす場合も、必要な依存がその環境の中にあるかを確かめます。

実行環境の追加・変更は元の依頼と既存の構成管理の範囲に従います。
設定と制限は [nix-ld の仕様](https://github.com/nix-community/nix-ld) で確認します。
