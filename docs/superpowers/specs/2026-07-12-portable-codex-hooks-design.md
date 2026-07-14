# Portable Codex Hooks Design

日付: 2026-07-12
状態: adversarial review 反映済み(r2 待ち)
ゴールの先: 本設計の実装後、Windows の `~/.codex` を dotfiles/codex への junction に変換する(手動コピー配備の廃止)

## Goal

Make every tracked Codex hook start successfully on Windows, macOS, and Linux while preserving its current policy behavior, so that a single tracked `codex/hooks.json` works on all machines and `~/.codex` can be a junction/symlink to `dotfiles/codex` everywhere.

## Root causes

- Windows resolves the bare `bash` in `command` to WSL's launcher (`System32\bash.exe`) instead of Git Bash; hooks then run in the wrong environment or fail (`Bash/Service/CreateInstance/E_ACCESSDENIED`).
- The push guard misses several executable and refspec forms(`/usr/bin/git`・`git.exe`・`$(...)` 内の git など)and can false-positive on text that merely mentions git.
- The Codex compact hooks read Claude's state directory(`$HOME/.claude/compact-state`)なので、両ツールを併用すると状態が混線する。

## 事実(実測・2026-07-12)

- codex-cli **0.142.5** の hooks.json は per-handler の **`commandWindows`** フィールドをサポートし、Windows では `command` より優先される(隔離 CODEX_HOME + marker ファイルで検証済み)。`commandWindows` の無い handler は従来どおり `command` を使う。
- これが検証済みの最低バージョン。**それ未満の codex では `commandWindows` が無視され壊れた `command` に落ちる**可能性があるため、0.142.5 を最低要件とする。

## Design

### 1. `commandWindows` + PowerShell ランチャー

Keep `command` as the portable POSIX path for macOS and Linux. Add `commandWindows` to **every** Codex handler, invoking a tracked PowerShell launcher(`codex/hooks/run-hook.ps1`)。ランチャーにも hooks.json にも username・マシン固有絶対パスを含めない。

**Git Bash 発見は決定的な優先順**(素朴な `Get-Command bash` は WSL launcher を先に掴んで元バグを再生産するため):

1. `git.exe` を PATH から解決し、その Git for Windows インストールから対応する `bin\bash.exe` を導出
2. `$env:SCOOP`(および既定の `~\scoop`)の `apps\git\current\bin\bash.exe`
3. 標準の Git for Windows 配置(`%ProgramFiles%\Git\bin\bash.exe` 等)
4. 最後に PATH 上の `bash.exe` 候補 — ただし `System32` 配下(WSL launcher)を明示的に拒否し、候補が Git Bash であることを検証してから採用

### 2. 実行契約(argv ベース、シェル文字列構築禁止)

launcher の呼び出し形式(hooks.json の commandWindows):

```text
pwsh -NoProfile -File <dotfiles>/codex/hooks/run-hook.ps1 --failure-mode deny|warn [--env NAME=VALUE]... -- <script-path> <arg...>
```

**PowerShell 要件: pwsh 7.3+**(`$PSNativeCommandArgumentPassing = 'Standard'` を launcher 冒頭で設定)。Windows PowerShell 5.1 のネイティブ引数渡しは内部で文字列結合するため argv 契約を守れない(`Start-Process -ArgumentList` も同様)。pwsh 不在は「Git Bash 不在」と同じく failure-mode マトリクスに従う(…が invoker が pwsh 自体なので実際は launcher 起動失敗ケースに含まれる — E2E 対象)。

launcher が起動する子プロセス:

```text
<git-bash>\bash.exe --noprofile --norc <script-path> <arg...>
```

- 引数はプロセス argv として渡す。シェルコマンド文字列を組み立てない(スペース・クォート・メタ文字の破壊/注入を構造的に排除)。`--` を launcher 引数と script 引数の区切りとする
- script path は明示的に変換・正規化して渡す
- stdin をそのまま転送し、stdout/stderr を分離したまま透過。**exit code の正確な伝播は「子プロセスの起動に成功した場合」に適用**(起動失敗時は下記の失敗ポリシーが変換する)
- **login shell(`-l`)は使わない**(起動ファイル由来の出力・遅延・環境変異を policy hook に持ち込まないため)。hook スクリプトが login 環境を必要とする依存は現状ない
- **env の展開契約**: `--env NAME=VALUE` の VALUE 内 `$HOME` は launcher がユーザーホームへ明示的に展開してから setenv する(それ以外の変数参照は展開しない・文書化)。argv 渡しではシェル評価が無いため、暗黙の展開に依存しない

### 3. 失敗ポリシーは handler 種別ごと(全 fail-open は安全装置の自殺)

handler 種別は launcher の `--failure-mode` 引数で明示的に選択する(推測しない)。挙動マトリクス:

| 事象 | `--failure-mode deny`(policy: git-push-guard) | `--failure-mode warn`(lifecycle: compact 系) |
|---|---|---|
| 子プロセス正常起動 | exit code をそのまま伝播 | 同左 |
| Git Bash 不在 | **有効な PreToolUse deny JSON を stdout に出力**して deny(理由: 依存不在) | stderr に 1 行警告、exit 0 |
| launcher 内部エラー/引数不正 | 同上(deny JSON、理由区別) | 同上(警告、exit 0) |

- deny は「エラー exit」ではなく **Codex が解釈できる deny JSON** として表現する(exit code だけでは deny にならない可能性があるため)
- launcher は「Git Bash 不在」と「launcher バグ/引数不正/スクリプト失敗」をメッセージで区別する
- **launcher 自身が起動できない**(run-hook.ps1 欠損・PowerShell 実行ポリシー等)ケースは launcher 内の fail-closed では守れないため、E2E 検証項目に含める(その場合 codex 側の hook 失敗扱いとなることを実測で確認し、push-guard については Claude 側 settings.json の deny ルールが第二防衛線であることを記録する)

### 4. push-guard 強化(両コピー同一)

**脅威モデル**: 単一ユーザーのエージェント(Claude/Codex)が Bash tool 経由で誤って危険な push を実行するのを防ぐ。悪意ある難読化への完全対抗は目的外だが、**「git を含みうる曖昧なコマンドは reject(fail-closed)」**を原則とし、見かけの網羅性で実際の穴を隠さない。

- 実行位置の `git`・`git.exe`・パス付き(`/usr/bin/git`・`C:\...\git.exe`)を認識する
- `$(...)`・`` ` ` ``(ネストしたコマンド置換)の内部も検査する
- force(`--force`/`-f`/`--force-with-lease`)・delete(`--delete`/`-d`/`:refspec`)・保護先 `master`(refspec 変形 `HEAD:master`・`+ref` 含む)を拒否
- 単なる言及(`echo git push --force` 等、実行位置に無いもの)は許可
- **named bypass corpus** をテストとして保持: 実行形態(bare/exe/パス付き)・ラッパー・置換ネスト・refspec 削除・leading `+`・保護先変形・オプション位置・CRLF tokenizer 出力・無害な引用/コメントテキスト
- 対応しない構文(エイリアス・多段シェル文字列等)は明記し、判定不能で git 実行の可能性があるものは reject 側に倒す

### 5. compact-state の分離(スクリプトは byte-identical を維持)

hook スクリプト自体は既に `COMPACT_STATE_DIR` 環境変数を尊重する(`${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}`)。**スクリプトは変更せず**、codex/hooks.json 側で渡す: POSIX `command` ではシェル評価があるので `COMPACT_STATE_DIR=$HOME/.codex/compact-state bash ...` の前置で、`commandWindows` では launcher の `--env COMPACT_STATE_DIR=$HOME/.codex/compact-state`($HOME は launcher が明示展開)で。これにより claude/hooks との byte-identical copy-sync 規約を破らない。

### 6. `~/.codex` 丸ごと junction 化(実装後の移行)

**設計判断(ユーザー決定 2026-07-12)**: `~/.claude` = dotfiles/claude と同じく、`~/.codex` 全体を dotfiles/codex への junction にする。auth.json・sessions 等の live 状態が public repo の**作業ツリー内**(git 追跡外)に置かれるリスク(`git clean -fdx` での消失・バックアップ混入・強制 add 事故)は、claude 側と同一の受容済みリスクとして引き受け、`.gitignore` の whitelist を監査して「意図したファイルだけが追跡される」ことをテストで保証する。

**whitelist は再帰 glob をやめ個別列挙にする**: 現行の `!/codex/skills/**`・`!/codex/hooks/**` は、junction 化後に codex や skill installer が同ディレクトリへ生成した新ファイルを「通常の `git add .`」で追跡候補にしてしまう(force-add 不要で混入する = 受容済みリスクより広い)。承認済みファイルを個別に unignore する形へ改める(hooks: 各 .sh・.test.sh・run-hook.ps1・hooks-json.test.ps1 / skills: 既知 skill ディレクトリごと)。監査テストは 3 層で、移行時だけでなく tests/ に常設する: (1) `git ls-files -- codex` が承認済み追跡集合と完全一致 (2) 代表的な機微パス(auth.json・sessions/・sqlite・plugins cache)が `git check-ignore` で ignored (3) `git ls-files --others --exclude-standard -- codex` が空(= 追跡候補になる untracked ゼロ。`git status --porcelain` は tracked な config.toml の live 変更で常時失敗するため使わない)。移行時は plugin list に加えて **skills ディレクトリの inventory 比較**(移行前後で一致)も行う。

**全プラットフォームで同じ最終形にする**: `~/.codex` → `<dotfiles>/codex` の link(Windows: junction / POSIX: symlink)+ 個別列挙 whitelist + 常設監査テスト。プラットフォーム別の到達方法:

- **Windows(このマシン)**: 下記の junction 移行手順
- **WSL / Linux(実ディレクトリ持ち)**: 同じ手順の `ln -sfn` 版(preflight → backup → tracked 衝突解決 → live 状態 move → symlink → 検証)。WSL の `~/.codex` 操作は wsl.exe 経由で行う
- **macOS(既に symlink 運用)**: dotfiles pull + 監査テスト実行のみ(移行不要。config.toml に他マシン状態が混ざる既知問題は tracked-のまま運用の受容範囲)
- **新規マシン**: setup.sh の既存分岐(`~/.codex` 不在なら symlink 作成)がそのまま最終形を作る。実ディレクトリを検出した場合のメッセージに本 spec の移行手順への参照を足す

移行手順(Windows):

1. **preflight**: codex のプロセス(CLI・デスクトップアプリ・app-server)が動いていないこと。dotfiles/codex 側と `~/.codex` 側の名前衝突を列挙し、tracked ファイル(AGENTS.md・config.toml・hooks/・hooks.json・skills/)以外に衝突が無いこと
2. **backup**: `~/.codex` を `~/.codex.bak-<date>` へコピー(rollback 用。検証完了後にユーザー承認で削除)
3. tracked ファイルの衝突解決: config.toml は live 版の内容を dotfiles/codex/config.toml(tracked)へ移す(tracked のまま運用 — ユーザー決定。機械状態の commit はユーザーが取捨)。hooks/・hooks.json・AGENTS.md・skills は本設計実装後は tracked 版が正
4. live 状態(auth.json・sessions・sqlite・plugins cache・その他全部)を dotfiles/codex/ 配下へ move
5. `~/.codex` を除去し `cmd /c mklink /J` で junction 作成
6. **検証**: `.gitignore` whitelist 監査 — `git status --porcelain` だけでは不十分(過去に force-add されたファイルは clean のまま追跡され続ける)。**`git ls-files codex` が承認済み追跡パス集合と一致**すること、および **`git check-ignore` が代表的な機微パス(codex/auth.json・codex/sessions/・sqlite 各種・plugins cache)を ignore と判定**することを両方テストする。加えて codex 起動・hook trust 再承認・全 hook 発火・`codex plugin list` が移行前と一致・rollback 手順の文書化

### 7. hooks-json.test.ps1(設計が正、既存ドラフトを置き換え)

既存ドラフトの「scoop パス直書き・`-lc` 必須」assertion は本設計(ランチャー・machine 固有パス禁止・login shell 廃止)と矛盾するため置き換える。新 assertion:

- 全 handler に非空の `commandWindows` があり、tracked launcher(`run-hook.ps1`)を参照する
- 対応する tracked hook スクリプトを参照する
- username・scoop 絶対パス・ドライブ付きユーザーパス・標準インストール絶対パスを含まない
- portable な POSIX `command` が維持されている
- `bash.exe` を直接呼ばない

## Verification

Tests must fail before implementation and cover:

- every Codex handler has a portable Windows override(新 hooks-json.test.ps1)
- launcher discovery: 各発見段階、**PATH 先頭に偽の WSL launcher(System32 相当)を置いても Git Bash を選ぶ**、Git Bash ゼロ時の handler 種別ごとの fail 挙動
- launcher 契約: スペース・アポストロフィ・Unicode・空引数を含むパス/引数、stdin 転送、stdout/stderr 分離、exit code 伝播
- push-guard: named bypass corpus(上記 4 の全項目)を両コピーでパス
- compact hooks: `COMPACT_STATE_DIR` 経由で Codex は `$HOME/.codex/compact-state`、Claude は `$HOME/.claude/compact-state` を使い分ける(スクリプト diff は空のまま)
- 既存 hook テスト全パス
- **実機 E2E**: Windows の `codex exec` で SessionStart・UserPromptSubmit・PreToolUse・Stop の各イベントに一意 marker を書かせ、選択された bash 実行体・stdin 受領・exit 挙動を記録して確認する
- junction 移行後: gitignore whitelist 監査・plugin list 一致・hook 発火

## Review gates

Run an adversarial review after this design, then a defect review before committing the implementation. Repeat each review until clean.
