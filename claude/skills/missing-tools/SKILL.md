---
name: missing-tools
description: command not found や実行ツール・言語サーバーの不足を、プロジェクトの devShell / direnv から解決し、必要な CLI を一時実行するときに使います。
---

# 実行ツールの不足を解決する

PATH にないことと、プロジェクトに用意されていないことを分けます。
既存の Nix → Docker → その他という環境優先順位に従い、用意された環境を先に使います。

## プロジェクトの環境

1. repo のセットアップ手順、flake / shell 定義、`.envrc` と CI を確認します。
   `nix develop -c` や許可済みの `direnv exec .` で、そのプロジェクトのコマンドを実行します。
2. 非対話シェル・WSL・LSP の PATH 継承が関係する場合は、
   [devShell のプロセス環境](references/devshell.md) を読みます。
   direnv がない・自動読込がないという理由だけで、別の版を取得しません。
3. プロジェクト環境では提供されていない独立 CLI が必要なら、
   comma、対象を指定した `nix run`、`nix shell --command` の順に一時実行を検討します。
   repo が供給する版との互換性を確認します。

コマンド自身の非ゼロ終了は、コマンドの不在ではありません。
実行ファイル、版、終了コードとエラーを照合します。
言語処理系の global installer や `curl | sh` を不足解決の既定にしません。

## Nix を使えない Windows

プロジェクトの既存環境で解決しない場合は、CLI が提供する一時 runner があれば使います。
既存の許可範囲にある通常のアプリ導入が必要なら Scoop を優先し、利用できなければ winget を検討します。
これは永続的な変更です。machine scope・UAC・再起動の必要性も操作前に確認します。
詳細な導入・更新・結果照合は `windows-package-maintenance` を使います。
manifest 自体の修正は `scoop-manifest` の担当です。

新規の shell で PATH が変わる場合は、導入した実ファイルと新旧プロセスを分けて確認します。
既存の package manager・導入実体・レジストリを調べずに再インストールしません。
非 Windows で Nix もプロジェクトの環境も使えない場合は、利用可能な一時実行経路を調べます。
必要な環境・権限がないと確認できた場合だけ、その不足と再開条件を示します。
