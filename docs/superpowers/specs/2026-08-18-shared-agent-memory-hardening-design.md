# 共有エージェント記憶の再確立と堅牢化

日付: 2026-08-18
状態: 承認済み・実装完了

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

memory write lock は共有 helper `~/.agents/bin/memory-write-lock.sh` の
`acquire <canonical-repo>` と `release <opaque-handle>` で操作します。`acquire` は
`mkdir <repo>/.git/memory-write.lock` の排他性を維持し、予測困難な 64 hex token を
token 固有の owner marker と private state に記録します。stdout には token を含まない
opaque handle path だけを返します。

handle path の stdout 書き込み成功を確認し、committed state と終了までの signal ignore を
確立した時点を ownership transfer の commit point とします。
commit point より前の HUP、INT、TERM または stdout 失敗では handle と自分の lock を
片付け、対応する非 0 status で終了します。commit point 後は ownership が caller へ
移転済みとして、短い終了処理中の signal で status 0 を変更しません。caller は
stdout だけでなく終了 status 0 を確認し、
nonzero の出力を handle として使用しません。

handle は当該 repo の `.git/memory-write-state/handle.*` にある実ディレクトリで、
directory mode は 0700、固定形式の repo file と token file は 0600 とします。`release`
は handle を source または eval せず、path、file type、permission、canonical repo、64 hex
token を厳格に検証します。別 process で保持した handle が指す token と owner marker が
一致する場合だけ lock を解放し、成功後にだけ handle を削除します。
handle は最初から最終 path を atomic `mkdir` して作り、repo と token をその中に記録します。
別名の pending directory から handle への rename は行いません。owner marker は atomic
`mkdir` した token 固有の 0700 directory と、その中の 0600 value file で構成します。
value は同じ lock directory で作成した temporary file を private owner marker 内の固定名へ
移し、marker の型、mode、固定内容を再検証してから所有権を確立します。

解放開始時は予測困難名の 0700 private retirement directory を atomic `mkdir` し、型、mode、
物理 parent を検証します。その private directory 内の固定かつ不存在の path へ handle を
rename し、rename 後の実ディレクトリ、固定形式、repo、token を再検証します。rename 前に
同名の foreign handle へ差し替えられていた場合も自動復元せず、private retirement 内で
内容非変更のまま保持し、以後の取得を停止します。rename 後に元の handle path へ作成された
内容には触れません。
取得失敗時の partial cleanup も同じ retirement 手順を使用し、検証済みでも canonical な
handle path を直接削除しません。lock cleanup に失敗した場合は retirement state を fence と
して保持します。

解放時の canonical lock も `.git` 直下に atomic `mkdir` した予測困難な 0700 private
retirement directory 内の固定・不存在 path へ同一 filesystem 内で rename します。
外部に既存し得る path を directory destination operand として使用しません。rename の前後に
lock が実ディレクトリであり symlink でないことを確認し、foreign、dangling symlink、owner
不一致の内容には一切触れません。
retirement path または既存 state が一つでも残っている間は、新しい取得を
lock `mkdir` の前後で拒否します。並行 acquire の未確立 handle state も同じ fence に含めます。

取得、lock 解放、state 削除の失敗は fail-closed とし、token や token を含む path を
stdout/stderr に出しません。取得中の HUP、INT、TERM は partial state と自分の lock を
安全に片付けて元の signal status で終了します。解放失敗時は retirement と handle を
保持し、次回取得を停止します。stale lock、state、retirement は 10 分経過だけを
根拠に自動削除せず、ユーザー確認を必要とします。

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
