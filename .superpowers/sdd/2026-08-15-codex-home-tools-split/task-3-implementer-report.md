# Task 3 Implementer Report

## 結果

- `codex_home`、`agents_skills`、`repo_home` を外部backupへ順にrenameし、検証済みcommit stageを`repo_home`へrenameする原子的切替を実装した。
- 失敗時はowned linkだけを削除し、`repo_home`、`agents_skills`、`codex_home`の順でsnapshotを復元する。各失敗は独立してstderrへ報告し、残りの復元を継続する。
- rollback後も`repo-codex-before-bootstrap`を原子的なstaging copyでbackupへ再保持し、3ディレクトリが揃う場合だけ有効な`--restore`コマンドを案内する。
- `--restore`は`codex`、`agents-skills`、`repo-codex-before-bootstrap`を安全な実ディレクトリとして検証し、live 2パスだけをstaging経由で復元する。repo snapshotは変更しない。
- Task 2の全量stage、未知runtime、managed overlay、secretのGit境界、copy failure injectionを維持した。

## TDD証跡

1. repo swap失敗テストを先に追加し、現行が`status=0`を返すREDを確認した。
2. repo snapshot欠落restoreテストを先に追加し、現行がrestoreを実行するREDを確認した。
3. link作成後例外テストを先に追加し、2本目のlinkが残るREDを確認した。
4. rollback前にowned pathを差し替えるテストを先に追加し、非所有directoryが削除されるREDを確認した。
5. rollback後repo snapshot保持と不完全backup案内テストを先に更新し、snapshot欠落と無効な`--restore`案内のREDを確認した。
6. 各REDに対して最小実装を追加し、対象テストと全suiteをGREENにした。

## 検証

- `python -B -m unittest discover -s codex-tools/tests -p 'test_*.py' -v`: PASS（71 tests）
- `bash -n codex-tools/bootstrap-home.sh`: PASS
- `git diff --check`: PASS
- テストはすべて`tempfile.TemporaryDirectory()`配下を使用し、実ユーザーホームは変更していない。

## 自己レビュー

- snapshot順は`codex_home -> agents_skills -> repo_home -> commit_stage`。
- rollback順は`owned links -> installed repo -> repo snapshot -> agents snapshot -> codex snapshot`。
- owned linkは登録時と削除直前の両方で、link種別と期待targetを確認する。差し替えられたpathは削除しない。
- secretを含む`backup/codex`と`backup/agents-skills`は削除せず、repo rollback失敗時も残りのlive復元を継続する。
- restoreはrepo snapshotを入力検証にだけ使い、通常restoreで上書きしない。
- 残存する既知の問題はない。

## 独立レビュー

- 新規レビューエージェントによる初回レビューでP1を2件検出した。
  - owned link path差し替え後の削除競合。
  - 3ディレクトリ不足backupへの無効なrestore案内。
- 両方をREDテストから修正し、再レビューで`APPROVED`。P0/P1/P2/P3はすべて0件。
