# gh skill と生成台帳で外部 skill を同期する

| | |
|---|---|
| **状態** | accepted |
| **日付** | 2026-09-06 |
| **決定者** | リポジトリ管理者 |
| **動作前提** | `gh skill install`、`gh skill update --dir`が利用できること |
| **周知先** | dotfiles 利用者 |

## 背景

自作または改変した skill は dotfiles で管理します。一方、第三者が配布する未改変の
skill を同じ方法で追跡すると、配布元の更新から乖離します。利用者が導入リストを
手で編集せず、`setup.sh` の実行だけで導入状態を復元・更新できる仕組みが必要です。

Codex plugin の選択はアカウントを正本とします。この決定は、
[Codex home の ADR](20260816-180256-link-codex-home-from-setup-sh.md) を変更しません。
本 ADR は plugin ではなく、外部リポジトリから導入する単体 skill だけを扱います。

## 判断基準

* Claude Code と Codex の両方へ同じ操作で導入できること
* 新しいマシンで登録済み skill を復元できること
* 利用者が台帳を手で編集しないこと
* 自作 skill と外部 skill の Git 管理境界が明確であること
* 自作 skill や管理外ファイルを削除しないこと
* `setup.sh` の既存方針に合わせ、sh と既存コマンドだけで実装すること

## 検討した選択肢

1. `gh skill` と薄い管理スクリプトを使う
2. `npx skills` と薄い管理スクリプトを使う
3. `setup.sh` から `gh skill update --all` だけを呼ぶ

## 決定

`gh skill` を取得・更新エンジンにし、`agent-shared/bin/managed-skills.sh` が
望ましい導入状態を管理します。管理スクリプトは次の操作を提供します。

```text
managed-skills.sh add OWNER/REPO SKILL [both|claude|codex]
managed-skills.sh sync
managed-skills.sh list
managed-skills.sh remove NAME
managed-skills.sh fork NAME [both|claude|codex]
```

`add` の導入先を省略した場合は `both` です。`fork` で省略した場合は、台帳に登録された
現在の導入先を引き継ぎます。

管理スクリプトは `agent-shared/managed-skills.tsv` を生成します。このファイルだけを
Git で追跡し、外部 skill の本体は追跡しません。利用者は台帳を直接編集せず、管理
スクリプトの操作によって更新します。

外部 skill は、Claude Code では `~/.claude/skills/<name>`、Codex では
`~/.agent-shared/skills/<name>` へ直接導入します。各コピーへ
`.dotfiles-managed-skill` を置き、管理スクリプトの所有物であることを示します。

管理対象のパスは `.git/info/exclude` の専用区間へ自動登録します。`fork` は管理印と
`gh skill` が追加した GitHub 更新情報を外し、除外設定からも削除します。その結果、
現在の内容を保持したまま自作 skill として Git 管理へ移せます。

## 同期フロー

`setup.sh` はエージェントのホームディレクトリを配置した後に
`managed-skills.sh sync` を呼びます。

1. 台帳全体の形式、skill名、重複、導入先を検証します。
2. 台帳にあり導入先にない skill を一時ディレクトリへ取得し、完全なことを確認してから
   導入先へ移します。
3. 管理印がある既存 skill を `gh skill update --dir` で更新します。
4. 台帳から消えた skill は、管理印があるコピーだけを削除します。
5. 実在する管理コピーから Git のローカル除外設定を再生成します。
6. 導入、更新、削除、失敗の件数を出力します。

`gh skill` は対話を無効にして実行し、利用者の入力待ちにはしません。処理は skill と
導入先ごとに継続します。取得または更新に失敗しても、既存コピーと
台帳を残して次回の同期で再試行します。台帳全体が不正な場合は、導入・更新・削除を
始めません。同名の管理外ディレクトリがある場合は上書きせず、その導入先を失敗として
報告します。

`gh skill` がない環境では既存 skill を変更しません。`setup.sh` は失敗を報告して残りの
セットアップを続けます。

## 更新方針

固定指定のない skill は配布元の最新版へ追従します。Git tag または Git commit の
識別子を指定した skill は、`gh skill` の固定動作に従います。

自動更新は、配布元の悪意ある変更やアカウント侵害の影響を受けます。追加時に配布元と
内容を確認し、継続的に信頼できない配布元は Git tag または Git commit の識別子へ
固定します。

## 結果

### 利点

* Git clone と `setup.sh` だけで、登録済み skill を両エージェントへ復元できます。
* 利用者は台帳を手で保守しません。
* 自作 skill は従来の Git 管理を維持できます。
* `gh skill` の試験提供中の操作を 1 本のスクリプトへ隔離できます。

### 欠点

* 同じ外部 skill を Claude Code 用と Codex 用に 1 コピーずつ保持します。
* 配布元の更新を自動取得するため、固定しない skill は配布元を継続的に信頼します。
* `gh skill` のインターフェース変更時は管理スクリプトの追従が必要です。

## 他案を採らない理由

### npx skills と薄い管理スクリプト

skill の検索範囲は広いものの、Node.js への依存が増えます。新しいマシンで導入状態を
復元する管理層はどちらの場合も必要なため、既に利用している `gh` を選びます。

### gh skill update だけを呼ぶ

既存コピーは更新できますが、新しいマシンには更新対象がありません。何を復元するかを
表す台帳がないため、要件を満たしません。

## 確認方法

`tests/managed-skills.sh` は、省略時の両エージェント導入、無対話実行、失敗した取得の再試行、
管理対象だけの削除、管理外 skill との衝突、`fork` による内容保持と更新情報の除去を検証します。
`tests/setup-home-links.sh` は、`setup.sh` が同期を呼ぶことを検証します。

実物の `gh skill` でも、一時的なホームディレクトリを使って初回同期と再同期を確認します。
