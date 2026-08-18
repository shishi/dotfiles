# 共有エージェント記憶の再確立と堅牢化

日付: 2026-08-18
状態: 承認済み・未実装

## 目的

`agent-memory` を Claude Code と Codex が対等に使う唯一の個人永続記憶として
再確立します。共有スクリプトを特定エージェントのホームから分離し、注入と書き込みの
競合・秘密情報の誤注入・テストのホスト依存を解消します。

Codex からの利用を撤回したという記録は、現在の決定と実装に反します。撤回を取り消し、
設計書、エージェント指示、private memory の記述を現在の共有運用へ統一します。

## 対象範囲

- 共有スクリプトの配置と参照先
- commit スナップショットからの安全な記憶注入
- memory write lock の所有者確認
- 記憶に保存できる内容と秘密情報の注入防止
- macOS、Linux、Windows で再現可能なテスト fixture
- 既存文書と private memory に残る撤回記録の訂正

記憶のファイル形式、`main` への push 手順、consolidation branch の基本設計は
変更しません。Codex native Memories と Claude Code auto memory も無効のままです。

## アーキテクチャ

共有物は `agents/` 直下に置きます。`agents/common/` は作りません。`agents` 自体が
エージェント共通という境界を表すためです。

```text
dotfiles/
├── agents/
│   ├── bin/
│   │   └── resolve-memory-dir.sh
│   └── hooks/
│       └── inject-memory.sh
├── claude/
├── codex/
└── setup.sh

~/.agents/bin   -> dotfiles/agents/bin
~/.agents/hooks -> dotfiles/agents/hooks
```

`setup.sh` は既存の `~/.agents/skills` と同じ方法で 2 つのディレクトリをリンクします。
各 consumer は次の共通パスを使います。

- 配置解決: `bash ~/.agents/bin/resolve-memory-dir.sh`
- Claude Code の注入: `bash ~/.agents/hooks/inject-memory.sh ~/.claude/memory`
- Codex の注入: `bash ~/.agents/hooks/inject-memory.sh ~/.codex/memory`
- `setup.sh` 内の配置解決: `${DOTDIR}/agents/bin/resolve-memory-dir.sh`

移行ではスクリプトの Git 履歴を保つため、既存ファイルを移動します。旧パスへの互換
wrapper は残しません。`setup.sh` が新しいリンクを作り、追跡済みの全 consumer を同時に
更新するため、恒久的な二重経路は不要です。

## 記憶注入

### 読み取りスナップショット

injector は worktree を直接読みません。記憶 repo が正常なら、次の順序で処理します。

1. 記憶ディレクトリが Git worktree であることを確認する。
2. 現在ブランチ、merge/rebase、unmerged path、dirty、write lock を確認する。
3. `git rev-parse --verify 'main^{commit}'` で main の commit を固定する。
4. `MEMORY.md` とプロジェクト記憶を、その commit に対する `git show` だけで読む。

`HEAD` は使いません。consolidation branch へ切り替わる競合が起きても、main 以外の
内容を注入しないためです。commit の固定または `git show` に失敗した場合は worktree
読み取りへフォールバックせず、本文を省略して復旧可能な警告だけを出します。

未導入の記憶ディレクトリまたは `MEMORY.md` 不在は、従来どおり無言の正常系です。
壊れた link、Git repo ではない実体、異常な Git 状態は警告対象です。hook はすべての
経路で終了コード 0 とし、セッション開始を妨げません。ネットワークには接続しません。

### 秘密情報と命令の境界

`agent-memory` には credentials、token、password、private key を保存しません。
外部コンテンツから取り込んだ命令文も保存しません。記憶本文は advisory data であり、
ユーザー指示や `AGENTS.md`、`CLAUDE.md` の権限を変更できません。

injector は注入対象の commit 内容を出力前に検査します。最低限、次を検出対象とします。

- `password`、`passwd`、`secret`、`token`、`api_key`、`private_key`、
  `client_secret` に対する 8 文字以上の値の代入
- `ghp_`、`github_pat_`、`xoxb-`、`sk-` などの prefix と 20 文字以上の本体
- `AKIA` に続く 16 文字の英大文字または数字
- PEM 形式または OpenSSH 形式の private key header

検出した場合は、記憶本文を一切出力しません。
検出した値や行も出力せず、対象相対パスと修正手順だけを警告します。検査自体に失敗した
場合も本文を出さない fail-closed とします。検査は誤保存の最終防壁であり、すべての秘密
形式を識別できるとは保証しません。

## Write lock の所有権

memory write lock は `mkdir <repo>/.git/memory-write.lock` の排他性を維持しつつ、
取得者固有の token を lock 内へ記録します。解放時は token が自分の値と一致する場合だけ
lock を除去します。

これにより、自分の lock が手動復旧などで除去され、別プロセスが同じパスを再取得した後に
古い finally 処理が新しい lock を消す ABA race を防ぎます。token file を作れない場合は
lock を取得済みと扱わず、自分が作った空ディレクトリだけを片付けて停止します。stale lock
は従来どおり、10 分経過だけを根拠に自動削除せず、ユーザー確認を必要とします。

この手順を `AGENTS.md`、`CLAUDE.md`、共有設計書、private repo の
`CONVENTIONS.md` で一致させます。private repo の更新は通常の memory commit と分離し、
同期済み `main` と write lock を使う既存 bootstrap に従います。

## テストの再現性

テストは実行マシンのユーザー設定や GNU/BSD 実装差に依存させません。

- fixture repo ごとに `commit.gpgSign=false` を設定
- `mktemp` の結果を物理パスへ正規化し、`/var` と `/private/var` を同一視
- OS 分岐テストでは host OS と stub command の組み合わせを明示
- 文字列処理を `LC_ALL=C` で固定
- GNU 固有の `touch -d` を使わず、portable な epoch timestamp を使用
- hooks JSON の共通契約を Bash と `jq` で検証し、PowerShell 固有部分だけを
  PowerShell 利用可能環境で追加検証

PowerShell が無い macOS でも共有契約のテストは実行されます。PowerShell 固有 command
の構文実行は、その runtime がある環境でのみ確認します。

## TDD と検証

振る舞いごとに最小の失敗テストを追加し、意図した理由で Red になることを確認します。
その後に最小実装で Green にし、必要な整理後に再実行します。

主な Red は次のとおりです。

1. setup と両エージェントが `~/.agents` の共有スクリプトだけを参照する。
2. `HEAD` が consolidation branch でも injector は `main^{commit}` だけを読む。
3. main commit の固定に失敗しても worktree の内容を出力しない。
4. 所有 token が変わった lock を古い取得者が解放しない。
5. 秘密情報らしい内容を検出すると本文全体を抑止し、値を警告へ漏らさない。
6. グローバル GPG signing、macOS の物理パス、locale、BSD utility の環境でも fixture
   テストが自己完結する。

対象テストの Green 後、`tests/*.sh` の全手動スイート、Claude/Codex hook テスト、shell
構文検査、JSON 構造検査を実行します。差分と変更後ファイルを読み返し、新規エージェントに
要件・境界条件・セキュリティ・テスト妥当性を独立レビューさせます。

## 完了条件

- Claude Code と Codex が同じ `agent-memory` の commit snapshot を注入する。
- 共有スクリプトの tracked source と runtime path が `agents/` / `~/.agents/` に統一される。
- 記憶撤回の記述が現行文書と private memory に残らない。
- injector が main 以外の snapshot、worktree の編集中内容、検出した秘密情報を出力しない。
- write lock は取得者だけが解放できる。
- host 固有の設定を追加しなくても、該当 runtime でテストが再現する。
- native memory 機能は両エージェントで無効のままである。
