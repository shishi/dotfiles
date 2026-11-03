---
name: nix-environment
description: プロジェクトのルートに flake.nix があるとき、コマンド・テスト・ビルド・実行環境の起動に使います。読解・編集だけの作業では使いません。
---

# flake.nix のあるプロジェクトの実行環境

プロジェクトのルートに `flake.nix` があるときは、その devShell でコマンドを実行します。

1. `nix develop -c <command>` で実行します。許可済みの `.envrc` があれば `direnv exec . <command>` でもかまいません。
2. devShell が使えない具体的な理由 (Nix が無い、評価に失敗する、必要なツールが含まれない) がある場合だけ、repo が用意する Docker の手順を使います。それも無い場合は、repo のセットアップ手順に従います。
3. 読解・編集だけで終わる作業では devShell を起動しません。
4. devShell に無い CLI を一時的に使う場合は `missing-tools` に従います。
