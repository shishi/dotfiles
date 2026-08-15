# 宣言的 Codex ホーム 実装計画

> **実行方針:** Kent Beck の TDD に従い、各タスクを Red → Green → Refactor の順で進める。構造変更と振る舞い変更は混ぜない。

**目的:** `dotfiles/codex` を永続的な Codex 設定の唯一の正とし、`~/.codex` 全体と `~/.agents/skills` を symlink で接続する。選択した plugin は `codex/config.toml` から冪等に復元・削除できるようにする。

**構成:** 追跡対象は `.gitignore` の allowlist で限定する。plugin 同期と既存ホーム移行は Python 標準ライブラリだけで実装し、`setup.sh` から薄い shell wrapper を呼ぶ。移行は完全バックアップ、検証、transaction journal、symlink 切替を分離し、Codex 終了後にだけ実行する。

**技術:** Bash、Python 3.11 以上（`tomllib`）、PowerShell テスト補助、Codex CLI、Git

## 実装時の安全条件

- 現在の `codex/hooks.json` と `codex/hooks/hooks-json.test.ps1` のユーザー変更は変更しない。
- 実 Codex が動作中のため、このセッションでは `~/.codex` の移行・置換を実行しない。
- `auth.json`、token、session、SQLite、logs、cache、plugin download を追跡しない。
- 失敗テストを確認してから最小実装を書き、Green 後だけ重複を整理する。
- 5ファイル以上の変更、新規module、infra設定変更の区切りと完了前に、新規エージェントでレビューする。

### タスク1: 追跡境界と plugin desired state をテストで固定する

**対象ファイル:**

- 新規: `tests/codex_managed_state_test.py`
- 新規: `codex/tests/fixtures/config_classification.json`
- 新規: `codex/tests/fixtures/live_config_sanitized.toml`
- 新規: `codex/tests/fixtures/expected_managed_config.toml`
- 変更: `.gitignore`
- 変更: `codex/config.toml`

1. `codex/` が既定で無視され、`AGENTS.md`、`config.toml`、`agents/**`、`rules/**`、`hooks/**`、`hooks.json`、個人 `skills/**`、installer、migration、tests だけが allowlist される失敗テストを書く。
2. `skills/.system/**` と既知runtime・credential形状が追跡対象にならない失敗テストを書く。
3. live/repo各キーを `adopt-live`、`merge`、`repo-wins`、`reject-generated` の4分類にしたJSON fixtureと、値を無害化したlive入力・期待出力fixtureを作る。root model/reasoning/sandbox/approval、project trust、Windows sandbox、shell policy、desktop、hook trust、computer-use allowanceは永続設定として採用またはmergeする。`developer_instructions`、`personality`、`approvals_reviewer`、native memories無効化はrepoを優先する。plugin生成MCP、version付きruntimeを指す現行`notify`、native pipe、実行file/cache path、app version、marketplace timestamp/revision、app-supplied local pathは拒否する。
4. fixtureの全キーが重複なく分類され、未分類キーで失敗し、期待するmanaged configと一致するRed testを書く。
5. `tomllib` で `config.toml` を読み、plugin ID の一意性、enabled の真偽値、Superpowers の有効providerが1つ、`superpowers@openai-api-curated = false`、`codex-security@openai-api-curated = true` を検証する失敗テストを書く。
6. 実行: `python tests/codex_managed_state_test.py`。意図した失敗を確認する。
7. `.gitignore` に最小の allowlist と `skills/.system` の再除外を追加する。
8. fixtureの期待結果どおりにdurable設定を `config.toml` へ反映し、現行のportable外部 marketplace Git source とplugin選択を移す。上流 `superpowers@superpowers-marketplace` だけを有効にし、curated版は無効sentinelにする。
9. 実行: `python tests/codex_managed_state_test.py`。Greenを確認する。
10. テスト内の重複fixture helperだけを整理し、再実行する。

### タスク2: agent・rule・個人skillを `codex/` へ集約する

**対象ファイル:**

- 新規: `codex/agents/agent-architect.toml`
- 新規: `codex/agents/agent-improver.toml`
- 新規: `codex/agents/agent-reviewer.toml`
- 新規: `codex/agents/claude-skills-architect.toml`
- 新規: `codex/rules/default.rules`
- 新規: `codex/skills/compact-prep/SKILL.md`
- 新規: `codex/skills/memory-consolidate/SKILL.md`
- 変更: `tests/codex_managed_state_test.py`

1. 必須agent、rule、10個の個人skillと各 `SKILL.md` を列挙する失敗テストを書く。
2. 実行: `python tests/codex_managed_state_test.py`。不足分だけで失敗することを確認する。
3. 現在の `~/.codex/agents`、`~/.codex/rules`、`~/.agents/skills/{compact-prep,memory-consolidate}` から内容を取り込み、既存repo版のagent instruction・hooks・重複skillは上書きしない。
4. 実行: `python tests/codex_managed_state_test.py`。Greenを確認する。

### タスク3: plugin同期の判定ロジックをTDDで実装する

**対象ファイル:**

- 新規: `codex/install_plugins.py`
- 新規: `codex/tests/test_install_plugins.py`

1. fake command runnerを使い、CLI未導入、既に収束済み、enabled外部pluginに必要なmissing marketplaceだけの追加、enabled plugin追加、disabled plugin削除、未管理plugin保持の失敗テストを書く。追加後に `codex plugin list --json` を呼ぶ操作順も固定する。
2. app-supplied分類をテストする。`openai-bundled`、`openai-primary-runtime`、`openai-api-curated` のlocal sourceは追跡・追加しない。前2者はinstall/removeせず、curatedはenabledをinstallせず不在ならwarning成功、disabledはremove可能とする。
3. malformed TOML、重複、marketplace値のexact `source_type`/`source` table、plugin値のexact Boolean `enabled` table、enabled source-backed pluginのsource不足、marketplace list失敗、plugin list失敗、`marketplaces[].marketplaceSource` のsource不一致、add/install/remove失敗をテストする。scalar、extra key、誤った値型はCLI実行前に拒否する。
4. 実行: `python -m unittest discover -s codex/tests -p 'test_*.py'`。意図した失敗を確認する。
5. `tomllib` で設定を厳密に読み、desired state、`codex plugin marketplace list --json`、`codex plugin list --json` の差分から操作列を作る最小実装を書く。
6. command runnerを注入できる小さな関数に分け、テストをGreenにする。
7. Green後、marketplace分類・検証・差分計算の重複だけを整理する。

### タスク4: CLI副作用から `config.toml` を保護する

**対象ファイル:**

- 変更: `codex/install_plugins.py`
- 新規: `codex/install-plugins.sh`
- 変更: `codex/tests/test_install_plugins.py`

1. 成功時と各失敗時に `config.toml` がバイト単位で不変になる失敗テストを書く。
2. 同一ディレクトリへ元バイト列を退避し、全終了経路で一時ファイルへの書込み・flush後に `os.replace` する最小実装を書く。
3. 復元自体の失敗を非zeroにするテストを追加する。復元失敗時は元バイト列の退避fileを削除せず、その絶対pathと安全な手動復旧commandをstderrへ表示する最小実装を書く。
4. `python3`、次に `python` を調べ、Python 3.11以上の最初の候補を選ぶ薄いwrapperを追加する。先の候補が古い場合のfallbackと、対応候補なしの明示的失敗をテストする。Codex CLI不在だけはmessage付き成功、それ以外の依存・同期失敗は非zeroにする。
5. 2台分の一時ホームfixtureを連続実行し、disabled sentinelが両方で残ることを検証する。
6. 実行: `python -m unittest discover -s codex/tests -p 'test_*.py'`。

### タスク5: fresh setup の2本のsymlinkと失敗伝播を実装する

**対象ファイル:**

- 新規: `codex/setup-home-links.sh`
- 新規: `codex/tests/setup-home-links.test.sh`
- 変更: `setup.sh`
- 変更: `tests/setup-windows-symlinks.sh`

1. 一時HOMEでatomicな `mkdir` lockを取得し、`~/.codex -> dotfiles/codex` と `~/.agents/skills -> dotfiles/codex/skills` の2本を要求する失敗テストを書く。既存lockは無変更で拒否し、全終了経路で自分のlockを解放する。
2. 既存実directoryを置換しない、既存正規linkは冪等、`same_link` のsource/target解決失敗は拒否、片方のlink失敗時は同じ試行で作ったlinkだけを戻す、作成後に実linkとtargetを検証するテストを書く。
3. cleanupは作成の逆順で行い、各linkのownershipとraw `readlink` targetが作成時と一致する場合だけ削除する。ownership変更・削除失敗後も残りをbest-effortで処理し、元の失敗、各cleanup失敗、`rollback incomplete` をすべて診断するテストと最小実装を書く。
4. Git Bash/MSYSでは `MSYS=winsymlinks:nativestrict` を使い、Developer Modeまたは権限不足を明示的な失敗にする最小実装を書く。
5. `setup.sh` の既存Codex link部分をhelper呼出しへ置換する。無関係なsetup処理はリファクタしない。
6. `codex/install-plugins.sh` の失敗を握り潰さず、top-level setupを非zeroにするテストと実装を追加する。
7. 実行: `bash codex/tests/setup-home-links.test.sh` と `bash tests/setup-windows-symlinks.sh`。

### タスク6: 既存ホームの安全なmigrationをTDDで実装する

**対象ファイル:**

- 新規: `codex/migrate_home.py`
- 新規: `codex/tests/test_migrate_home.py`
- 新規: `codex/migrate-home.sh`

1. 一時directoryで、Codex process検出、未分類トップレベル項目、destination collisionを事前拒否する失敗テストを書く。
2. 完全backupがrepo root外のtimestamp付きdirectoryに作られ、regular fileはsize/SHA-256、symlinkとWindows junctionは追跡せずtype/targetで検証される失敗テストを書く。junction作成はdestination/targetの `cmd.exe` meta characterをlaunch前に拒否する。
3. repo側の `AGENTS.md`、`config.toml`、agents、rules、hooks、個人skillsを権威として上書きしないテストを書く。runtime allowlistだけをrepo内の無視対象pathへコピーし、nested `skills/.system` は親 `skills` が実directoryの場合だけ扱い、symlink/junction親を追跡しない。
4. 新規作成したrepo runtime pathだけをtransaction journalへ記録し、backupとruntime copyを検証した後、live変更直前にCodex processを再checkする最小実装を書く。
5. live2本を削除せず、backup内のcommit snapshotへ順にatomic renameしてからlinkを作成・検証する。2本目snapshot rename、2本目link、copy、検証の各失敗でsnapshotからliveを戻し、journal pathを逆順best-effort cleanupするテストを書く。各rollback失敗は残りの処理を止めず診断する。
6. `migrate-home.sh --restore BACKUP_DIR` をTDDで追加する。real directoryであるbackup rootと `codex`/`agents-skills` を要求し、2本をstage copyして検証後、Codex processを再checkする。現liveをtimestamp付きpre-restoreへ保持して2pathをrename swapし、部分失敗ではbest-effort rollbackし、backup自体は保持する。
7. 両link検証後にfilesystem migrationを明示的にcommit扱いにし、その後plugin同期を別stepとして呼ぶ。commit前failureはbackupがあればexact restore command、commit後のplugin失敗・launcher例外はlinkを戻さずretry-onlyを表示するテストを書く。
8. `migrate-home.sh` も `python3` / `python` からPython 3.11以上を選び、古い先行候補からfallbackするwrapper testを追加する。
9. 実行: `python -m unittest discover -s codex/tests -p 'test_*.py'` と `bash codex/tests/migrate-home-wrapper.test.sh`。
10. Green後、copy・verify・snapshot・swap・rollbackの責務を小関数へ整理し、再実行する。

### タスク7: 全体回帰と安全性を検証する

**対象ファイル:**

- 必要時のみ変更: 上記テスト・script

1. 実行: `python tests/codex_managed_state_test.py`。
2. 実行: `python -m unittest discover -s codex/tests -p 'test_*.py'`。
3. 実行: `bash codex/tests/setup-home-links.test.sh`。
4. 実行: `bash codex/tests/install-plugins-wrapper.test.sh`、`bash codex/tests/migrate-home-wrapper.test.sh`、`bash tests/setup-windows-symlinks.sh`、`bash tests/compact-safety.sh`、既存hook tests。
5. 実行: `git diff --check` と `git status --short --untracked-files=all`。
6. `git check-ignore -v` でcredential、session、SQLite、plugin cache、`.system` が無視され、管理対象だけが追跡可能なことを確認する。
7. plugin strict-shape、必要marketplaceだけの追加順、setup lock/ownership cleanup、migration process-race/snapshot rollback/nested runtime、restore stage/swap rollback、wrapper version fallback、commit前restore対commit後retry-onlyのfailure pathがテストで覆われることを確認する。テスト件数の固定値には依存しない。
8. 実Codexが起動中なので実ホームにはmigrationを実行せず、Codex終了後に実行するcommandとbackup/retry手順だけを報告する。

### タスク8: 新規エージェントのレビューゲートを通す

**対象:** spec、ADR、実装計画、全実装差分、全テスト結果

1. 新規エージェントへ仕様適合性、秘密情報、rollback、Windows symlink、plugin収束、ユーザー変更保護に加え、restoreの2path swap、process再check、commit境界の診断を重点にレビュー依頼する。
2. P1/P2があれば、該当テストを先に追加または修正して失敗を確認し、最小修正後に全回帰を実行する。
3. 同じレビュー担当へ再レビューを依頼し、CLEANになるまで反復する。
4. `verification-before-completion` に従って最終コマンドを新しく実行し、その結果だけを完了根拠として報告する。
