# Codexホームとツールの分離設計

## 目的

dotfiles/codex/ を ~/.codex が参照する実ホームに限定する。移行・セットアップ・プラグイン同期・テストは dotfiles/codex-tools/ へ分離する。Codexが将来追加するruntimeファイルを、初回移行時の許可リストで拒否しない。

## 決定

    dotfiles/
    ├─ codex/          # ~/.codex のリンク先。Codexが読むホーム
    │  ├─ config.toml  # Git管理する選択済み設定
    │  ├─ skills/      # Git管理する個人スキル。~/.agents/skills のリンク先
    │  └─ runtime/     # auth、cache、sessions、plugins等。Git管理外
    └─ codex-tools/    # Codexホームには入れない運用ツールとテスト

~/.codex は dotfiles/codex を参照し、~/.agents/skills は dotfiles/codex/skills を参照する。codex-tools のスクリプト、テスト、fixturesはCodexホームへ現れない。

## Git境界

ルートの .gitignore は codex/ 配下を既定で無視し、次だけを明示的に許可する。

- AGENTS.md、config.toml、agents/、rules/、hooks/、hooks.json
- skills/。ただし skills/.system/ は無視する

auth.json、セッション、SQLite、cache、browser、plugins、将来Codexが追加する未分類ファイルは作業ツリー内に保存するがGit管理しない。codex-tools/ は通常の追跡対象とする。

## 初回bootstrap

codex-tools/bootstrap-home.sh はPython実装を呼ぶ。一回限りのbootstrapであり、Codexを完全終了した外部端末からだけ実行する。

1. Codexプロセス、リンク状態、入力パス、バックアップ先を検証する。実行中または既存リンクは中止する。
2. ~/.codex と ~/.agents/skills をリポジトリ外の時刻付きバックアップへ完全コピーし、ファイル内容・symlink・junctionを検証する。
3. 検証済み .codex バックアップを、リポジトリ内の一時ステージングへ全量コピーする。未知のトップレベルentryも除外しない。
4. 現在の dotfiles/codex にある選択済み管理ファイルをステージングへ上書きする。リポジトリの config.toml、agents、rules、hooks、skillsが優先する。
5. ステージング全体と管理ファイルの上書き結果を検証する。~/.agents/skills の旧内容は外部バックアップで保持する。
6. Codex停止を再確認する。ライブの .codex と .agents/skills、および移行前のリポジトリ codex をバックアップ内のスナップショットへrenameする。
7. 検証済みステージングを dotfiles/codex へrenameし、2本のリンクを作成・解決確認する。
8. リンク作成・rename・検証の失敗時は、作成済みリンクを外し、ライブ2ディレクトリと移行前リポジトリをスナップショットから戻す。外部バックアップは残す。
9. ファイルシステム切替後、プラグイン同期を別の再試行可能ステップとして実行する。失敗しても検証済みリンクを戻さない。

--restore BACKUP_DIR は、bootstrap前のライブ .codex と .agents/skills を復元する。リポジトリの移行前スナップショットも保持するため、bootstrap途中の失敗は復旧できる。

## ツールの責務

- codex-tools/setup-home-links.sh: fresh環境で2本のリンクだけを作成する。実ディレクトリを置換しない。
- codex-tools/bootstrap-home.py: 全量スナップショット、検証、切替、rollback、restoreを担当する。
- codex-tools/install-plugins.py: dotfiles/codex/config.toml を唯一のdesired stateとして読む。
- codex-tools/tests/: bootstrap、リンク、プラグイン同期のテストだけを置く。

## 受入条件

- browser のような未知runtimeを含む既存ホームを、許可リスト追加なしでbootstrapできる。
- ~/.codex から codex-tools は見えない。
- 選択済みの設定・rules・hooks・skillsはリポジトリ版が優先する。
- runtimeと秘密情報はGitに追加されない。
- bootstrap前・切替途中・切替後の障害から、元のライブ2ディレクトリを回復できる。
- WindowsのReadOnlyファイル、symlink、junction、Python 3.11以上を扱える。
- 新規エージェントレビューと全テストが成功する。
