# Codexホームとツール分離 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Codexの実ホームを dotfiles/codex に限定し、未知runtimeを含む既存ホームを安全にbootstrapして2本のリンクへ切り替える。

**Architecture:** dotfiles/codex は ~/.codex のリンク先だけを置き、dotfiles/codex-tools はbootstrap、リンク作成、プラグイン同期、テストを置く。bootstrapはライブホームを全量ステージングコピーし、既存の選択済み管理ファイルを上書きして検証後に原子的に切り替える。

**Tech Stack:** Python 3.11以上、Bash、Windows directory symlink、Python unittest、Git Bash。

**Spec:** docs/superpowers/specs/2026-08-15-codex-home-tools-split-design.md

## Global Constraints

- Codex実行中はbootstrap、restore、ライブパスの変更を拒否する。
- runtimeと秘密情報は codex/ に保存してもGitへ追加しない。
- codex/ の管理ファイルはリポジトリ版が優先する。
- 未知runtimeを初回bootstrapで許可リスト拒否しない。
- WindowsのReadOnly、symlink、junctionを追跡し、Python 3.11以上を維持する。
- すべての挙動変更はKent Beck式RED、GREEN、最小リファクタの順で実施する。
- 各タスク終了時に新規レビューエージェントのレビューを受ける。

---

### Task 1: Codex実ホームと運用ツールの配置を分離する

**Files:**

- Create: codex-tools/
- Move: codex/install-plugins.sh -> codex-tools/install-plugins.sh
- Move: codex/install_plugins.py -> codex-tools/install_plugins.py
- Move: codex/migrate-home.sh -> codex-tools/bootstrap-home.sh
- Move: codex/migrate_home.py -> codex-tools/bootstrap_home.py
- Move: codex/setup-home-links.sh -> codex-tools/setup-home-links.sh
- Move: codex/tests/ -> codex-tools/tests/
- Modify: setup.sh
- Modify: .gitignore
- Modify: tests/codex_managed_state_test.py

**Interfaces:**

- Consumes: DOTDIR, dotfiles/codex, dotfiles/codex-tools.
- Produces: setup.sh が codex-tools/setup-home-links.sh と codex-tools/install-plugins.sh を実行する配置。

- [ ] **Step 1: 実ホームにツールが存在しない失敗テストを書く**

  tests/codex_managed_state_test.py に次の検証を追加する。

      self.assertFalse((repo / "codex" / "migrate_home.py").exists())
      self.assertTrue((repo / "codex-tools" / "bootstrap_home.py").is_file())

- [ ] **Step 2: テストが失敗することを確認する**

  Run: python -B -m unittest discover -s tests -p "codex_managed_state_test.py" -v

  Expected: codex-tools が未作成のため FAIL。

- [ ] **Step 3: ツールとテストを移動し、呼び出し元を更新する**

  codex/ には AGENTS.md、config.toml、agents、rules、hooks、hooks.json、skills だけを残す。setup.sh は codex-tools のリンク作成とプラグイン同期を呼ぶ。各Bash wrapperのSCRIPT_DIR基準のPythonパス、fixtureからの相対パス、install_plugins.py の config_path を dotfiles/codex/config.toml へ更新する。

- [ ] **Step 4: 配置テストをGREENにする**

  Run: python -B -m unittest discover -s tests -p "codex_managed_state_test.py" -v

  Expected: PASS。

- [ ] **Step 5: 移動後の既存ラッパーテストを実行する**

  Run: bash codex-tools/tests/migrate-home-wrapper.test.sh; bash codex-tools/tests/install-plugins-wrapper.test.sh; bash codex-tools/tests/setup-home-links.test.sh

  Expected: exit 0。

- [ ] **Step 6: 新規レビューエージェントにTask 1をレビューさせる**

  Review scope: codex/ に実行ツールが残らないこと、setup.sh とwrapperのパス整合、.gitignoreの追跡境界。

### Task 2: 全量snapshot bootstrapをRED-GREENで実装する

**Files:**

- Modify: codex-tools/bootstrap_home.py
- Modify: codex-tools/bootstrap-home.sh
- Modify: codex-tools/tests/test_migrate_home.py

**Interfaces:**

- Consumes: bootstrap(codex_home: Path, agents_skills: Path, repo_home: Path, backup_root: Path, process_running: Callable[[], bool]) -> int
- Produces: ~/.codex -> repo_home と ~/.agents/skills -> repo_home/skills の検証済みリンク。

- [ ] **Step 1: 未知runtimeを全量コピーする失敗テストを書く**

  test_bootstrap_copies_unknown_runtime_and_overlays_repository_managed_paths を追加する。ライブcodex_homeへ browser/state.json と unknown-state を作り、repo_homeへ managed config.toml と skills/managed/SKILL.md を作る。bootstrap後に次を検証する。

      self.assertEqual("runtime", (repo_home / "browser" / "state.json").read_text())
      self.assertTrue((repo_home / "unknown-state").is_file())
      self.assertEqual("managed", (repo_home / "config.toml").read_text())
      self.assertTrue(codex_home.is_symlink())

- [ ] **Step 2: テストが現行の許可リスト拒否で失敗することを確認する**

  Run: python -B -m unittest discover -s codex-tools/tests -p "test_migrate_home.py" -v

  Expected: status 1 または未知entry拒否による FAIL。

- [ ] **Step 3: bootstrapの全量ステージング処理を最小実装する**

  既存の _copy_entry、_copy_tree、verify_copy、_remove_path、junction安全処理を再利用する。repo_homeの兄弟に一意なstageを作り、検証済みバックアップのcodex全体をstageへコピーする。MANAGED_NAMESだけをrepo_homeからstageへ上書きし、各上書きをverify_copyで検証する。RUNTIME_PATTERNS と unknown拒否分岐はbootstrap経路から削除する。

- [ ] **Step 4: 全量snapshotテストをGREENにする**

  Run: python -B -m unittest discover -s codex-tools/tests -p "test_migrate_home.py" -v

  Expected: PASS。

- [ ] **Step 5: 既存の未分類拒否テストをbootstrap仕様へ置換する**

  test_unclassified_top_level_entry_is_rejected_before_backup を削除し、未知entryでも外部バックアップを作成してstageへ保存するテストへ置き換える。

- [ ] **Step 6: 新規レビューエージェントにTask 2をレビューさせる**

  Review scope: 管理ファイル上書き順、未知entryの全量保存、secretのGit境界、既存copy・junction helperの再利用。

### Task 3: 3つのrenameを含む原子的切替とrestoreを実装する

**Files:**

- Modify: codex-tools/bootstrap_home.py
- Modify: codex-tools/tests/test_migrate_home.py

**Interfaces:**

- Consumes: verified stage、外部backup、repo_home。
- Produces: ライブ2ディレクトリと移行前repo_homeのrollback可能なスナップショット。

- [ ] **Step 1: リポジトリ切替途中失敗のREDテストを書く**

  test_bootstrap_repo_swap_failure_restores_live_paths_and_repo_home を追加する。2本目のライブrenameまたはrepo_home renameでOSErrorをinjectし、次を検証する。

      self.assertTrue(codex_home.is_dir())
      self.assertTrue(agents_skills.is_dir())
      self.assertEqual("managed", (repo_home / "config.toml").read_text())
      self.assertFalse(codex_home.is_symlink())

- [ ] **Step 2: テストがrollback不足で失敗することを確認する**

  Run: python -B -m unittest discover -s codex-tools/tests -p "test_migrate_home.py" -v

  Expected: FAIL。

- [ ] **Step 3: commitとrollbackを実装する**

  停止再確認後、codex_home、agents_skills、repo_homeをbackup内の別名snapshotへrenameする。stageをrepo_homeへrenameし、2本のdirectory symlinkを作成する。失敗時は作成済みリンクだけを消し、repo_home、agents_skills、codex_homeの順でsnapshotを復元する。復元失敗は全件stderrへ出し、外部backupを削除しない。

- [ ] **Step 4: restoreの入力と復元範囲を更新する**

  --restore は backup内のcodex、agents-skills、repo-codex-before-bootstrapを検証し、stagingを通してライブ2ディレクトリを復元する。repo snapshotは通常restoreで上書きせず、bootstrap失敗rollback専用として保持する。

- [ ] **Step 5: 切替・restoreテストをGREENにする**

  Run: python -B -m unittest discover -s codex-tools/tests -p "test_migrate_home.py" -v

  Expected: PASS。ReadOnly、symlink、junction、process-race、partial-swapの既存ケースもPASS。

- [ ] **Step 6: 新規レビューエージェントにTask 3をレビューさせる**

  Review scope: 3パスのrename順、失敗時の所有権確認、secretを含むbackup保持、restoreの非破壊性。

### Task 4: プラグイン同期とセットアップを新しいホーム根へ接続する

**Files:**

- Modify: codex-tools/install_plugins.py
- Modify: codex-tools/install-plugins.sh
- Modify: codex-tools/setup-home-links.sh
- Modify: codex-tools/tests/test_install_plugins.py
- Modify: codex-tools/tests/setup-integration.test.sh

**Interfaces:**

- Consumes: dotfiles root。
- Produces: plugin同期が dotfiles/codex/config.toml を読む。fresh setupが2本のリンクを作る。

- [ ] **Step 1: config pathのREDテストを書く**

  installer mainのテストで、toolsディレクトリにconfig.tomlを置かず、dotfiles/codex/config.tomlだけを置く。reconcileが後者を読むことをassertする。

- [ ] **Step 2: テストが旧SCRIPT_DIR基準で失敗することを確認する**

  Run: python -B -m unittest discover -s codex-tools/tests -p "test_install_plugins.py" -v

  Expected: FAIL。

- [ ] **Step 3: dotfiles rootを一度だけ解決する**

  install_plugins.py、setup-home-links.sh、wrappersは自分の親ディレクトリをdotfiles rootとし、config sourceを root/codex/config.toml、home sourceを root/codex として使用する。

- [ ] **Step 4: installerとsetupのGREENを確認する**

  Run: python -B -m unittest discover -s codex-tools/tests -p "test_install_plugins.py" -v; bash codex-tools/tests/setup-integration.test.sh

  Expected: exit 0。

- [ ] **Step 5: 新規レビューエージェントにTask 4をレビューさせる**

  Review scope: fresh setup、CLI不在時の挙動、plugin desired stateの場所、BashとPythonのroot解決整合。

### Task 5: Git境界、文書、実行手順を確定する

**Files:**

- Modify: .gitignore
- Modify: tests/codex_managed_state_test.py
- Modify: docs/ADR/20260813-224935-use-linked-declarative-codex-home.md
- Modify: docs/superpowers/specs/2026-08-15-codex-home-tools-split-design.md
- Modify: docs/superpowers/plans/2026-08-15-codex-home-tools-split.md

**Interfaces:**

- Consumes: codex/ のallowlistと codex-tools/ の追跡対象。
- Produces: unknown runtimeはignore、運用ツールは追跡、手順は bootstrap-home.sh に統一。

- [ ] **Step 1: Git境界のREDテストを書く**

  codex_managed_state_test.py で次を検証する。

      self.assertTrue(is_ignored("codex/browser/state.json"))
      self.assertFalse(is_ignored("codex/config.toml"))
      self.assertFalse(is_ignored("codex-tools/bootstrap_home.py"))

- [ ] **Step 2: テストが旧ツールallowlistで失敗することを確認する**

  Run: python -B -m unittest discover -s tests -p "codex_managed_state_test.py" -v

  Expected: FAIL。

- [ ] **Step 3: .gitignoreと文書を更新する**

  codex/ の旧ツールallowlistを削除する。codex-tools/ の追跡を妨げる規則を置かない。ADRのDecision Outcomeを tools splitと全量bootstrapへ更新し、旧allowlist migrationをsupersededと記録する。

- [ ] **Step 4: Git境界テストをGREENにする**

  Run: python -B -m unittest discover -s tests -p "codex_managed_state_test.py" -v

  Expected: PASS。

- [ ] **Step 5: 完全検証を実行する**

  Run: python -B -m unittest discover -s codex-tools/tests

  Run: python -B -m unittest discover -s tests -p "*_test.py"

  Run: bash codex-tools/tests/migrate-home-wrapper.test.sh; bash codex-tools/tests/install-plugins-wrapper.test.sh; bash codex-tools/tests/setup-home-links.test.sh; bash codex-tools/tests/setup-integration.test.sh

  Run: bash -n codex-tools/bootstrap-home.sh; git diff --check

  Expected: すべてexit 0。

- [ ] **Step 6: 新規エージェントに最終レビューを依頼する**

  Review scope: 仕様との一致、秘密情報の追跡境界、全量bootstrapのrollback、Python 3.11とWindows junction互換。

- [ ] **Step 7: Codex終了後の実bootstrapを実行する**

  Run: bash /c/Users/shishi/dev/src/github.com/shishi/dotfiles/codex-tools/bootstrap-home.sh

  Expected: 外部backupの場所、2本の解決済みリンク、plugin同期結果を出力する。失敗時はbackupを残し、復旧コマンドだけを出力する。
