# Portable Agent Hook Cleanup

## Status

Accepted

## Goal

Claude Code と Codex の hook 構成から、保守上の意味がない重複と
マシン固有の Git Bash パスを除きます。共有できる実装は `agents/` を正本にします。

Herdr integration は Herdr 自身が生成・更新します。Claude Code 用と Codex 用を
独自実装へ置き換えず、再生成後も両者を識別できる状態を保ちます。

## Decisions

### Shared hooks

`git-push-guard.sh` と `inject-memory.sh` は、引き続き `agents/hooks/` の実装を
Claude Code と Codex から呼び出します。エージェントごとのコピーは作りません。

Codex の Windows hook は、共有 PowerShell launcher を経由して Git Bash を起動します。
launcher は `git --exec-path` から Git for Windows のインストール先を解決します。
これにより、ユーザー名や Scoop の配置を `hooks.json` に書きません。

POSIX 環境では、既存の `command` をそのまま使います。Windows だけ
`commandWindows` で launcher を呼びます。

### Herdr ownership

Herdr が生成した `herdr-agent-state.*` の内容は共通化しません。POSIX 用 `.sh` は
portable な初期状態として追跡し、Windows 用 `.ps1` は runtime 生成物として ignore します。
Herdr の再インストールや更新による上書きを許容します。

生成物は次の情報で識別できます。

- 配置先: `~/.claude/` または `~/.codex/`
- marker: `HERDR_INTEGRATION_ID=claude` または `HERDR_INTEGRATION_ID=codex`
- report 引数: `herdr:claude` または `herdr:codex`

両 integration は `SessionStart` で `session` action を実行します。入力形式の違いに対応する
guard は Herdr 側に残します。dotfiles は両スクリプトの byte-level な同一性を要求しません。

tracked 設定では portable な `~` 形式を使います。Windows の `commandWindows` は共有
launcher を経由し、`setup.sh` の収束処理も同じ形式を復元します。Herdr installer が
実行環境向けの script と設定を再生成した場合は、上記の識別情報で所有者を判別します。

### Test consolidation

Codex の `hooks.json` 契約は、Bash 版と PowerShell 版の両方で検査します。Bash 版は
意味単位の構造と portable path を、PowerShell 版はWindows launcherと実装到達性を検査します。
実行環境と責務が異なるため、どちらも保持します。

契約テストは hook の配列位置や `SessionStart` group の総数を固定しません。
共有 memory hook と push guard を内容で特定します。tracked 設定にあるWindows handlerは
Herdrを含めて共有launcher経由であることを要求します。

Codex 固有の injector テストは、Codex SessionStart入力からglobal・core・project memoryが
一度ずつ届くintegration契約を検査するため保持します。共有 injector suiteのunit境界とは
責務が異なります。

空の `.claude/settings.json` も削除します。空 object は project scope へ設定を追加しません。

## Alternatives

### Implement one custom Herdr hook

Claude Code と Codex の処理を `agents/hooks/` に実装すれば、生成 script を 1 本にできます。
しかし、Herdr の入力契約や更新へ自動追随できません。Herdr の管理責務とも競合するため
採用しません。

### Keep the absolute Git Bash path

現在の Windows では動作しますが、ユーザー名とインストール方法に依存します。
他の Windows 環境へそのまま配布できないため採用しません。

### Inline Git Bash discovery in every handler

追加ファイルは不要ですが、同じ解決処理を各 `commandWindows` に複製します。
検証と保守の対象が増えるため採用しません。

## Verification

- launcher の Red-Green テスト
- `tests/codex-hooks-json.sh`
- `codex/hooks/hooks-json.test.ps1`
- `codex/hooks/inject-memory.test.sh`
- `tests/shared-agent-hooks.sh`
- `tests/setup-home-links.sh`
- `agents/hooks/inject-memory.test.sh`
- `agents/hooks/git-push-guard.test.sh`
- JSON と PowerShell の構文確認
- repository diff の確認
- 新規エージェントによる独立レビュー
