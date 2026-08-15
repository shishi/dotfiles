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

- `python -B -m unittest discover -s codex-tools/tests -p 'test_*.py' -v`: PASS（74 tests）
- `bash -n codex-tools/bootstrap-home.sh`: PASS
- `git diff --check`: PASS
- テストはすべて`tempfile.TemporaryDirectory()`配下を使用し、実ユーザーホームは変更していない。

## 自己レビュー

- snapshot順は`codex_home -> agents_skills -> repo_home -> commit_stage`。
- rollback順は`owned links -> installed repo -> repo snapshot -> agents snapshot -> codex snapshot`。
- owned linkは作成時の`lstat` identityを記録し、rollback時にidentity、link種別、期待targetを再検証する。削除は非再帰`unlink`だけを使う。
- secretを含む`backup/codex`と`backup/agents-skills`は削除せず、repo rollback失敗時も残りのlive復元を継続する。
- restoreはrepo snapshotを入力検証にだけ使い、通常restoreで上書きしない。
- 残存する既知の問題はない。

## 独立レビュー

- 新規レビューエージェントによる初回レビューでP1を2件検出した。
  - owned link path差し替え後の削除競合。
  - 3ディレクトリ不足backupへの無効なrestore案内。
- 両方をREDテストから修正し、再レビューで`APPROVED`。P0/P1/P2/P3はすべて0件。

## 追加独立レビュー対応

- commit `4a1158e`への追加独立レビューで、check/use間にpathを差し替えるTOCTOU P1を2件再現した。
  - owned link確認後、汎用`remove_path`入口で実directoryへ差し替えるとforeign dataを再帰削除した。
  - `repo_installed`後、repo削除入口で外部directoryへ差し替えるとforeign dataを再帰削除した。
- 両PoCを`TemporaryDirectory`内の自動テストとして先に追加し、foreign file欠落のREDを確認した。
- link rollbackは作成時identityの再検証と専用non-recursive unlinkへ変更した。check後に実directoryへ差し替えられてもunlinkが安全に失敗し、foreign dataを残す。
- repo rollbackは現`repo_home`を削除せず、backup内の一意な`repo-codex-rollback-quarantine`へrenameしてからsnapshotを復元する。
- 同じ非破壊方針をrestore rollbackにも適用し、swap済みlive pathを`failed-restore` quarantineへrenameしてから旧live pathを復元する。対応テストもREDからGREENを確認した。
- 追加修正後の全74テスト、`bash -n`、`git diff --check`はPASSした。
- 新規独立再レビューは`APPROVED`。P0/P1/P2/P3はすべて0件。Windows実機でもdirectory symlinkとjunctionのidentity取得、非再帰unlink、target保持を確認した。

## 最終レビューP1対応

- `tasklist`の非ゼロ終了、`pgrep`の終了値2以上、各プロセス検査コマンドの`OSError`をすべてfail-closedにした。検査不能時はstderrへ理由を出し、Codexが動作中として移行・復元を停止する。
- bootstrap rollbackはlive linkを直接unlinkしない。backup内の一意なquarantineへrenameしてから、移動先のlink種別・target・作成時identityを再検証する。検証に失敗したentryは削除せず保持してrollback不完全として報告する。
- `setup-home-links.sh`も同じ順序で、親ディレクトリ内の一意なquarantineへ`mv`後にlink sourceを検証する。通常ファイルへの差し替えはquarantineに残る。
- TDDとして、Windows/Unixの検査失敗4ケースと、bootstrap・shell helperの通常ファイル差し替え2ケースを先にREDで確認してから最小実装を追加した。

## 最終検証

- `python -B -m unittest discover -s codex-tools/tests -p 'test_*.py' -v`: PASS（79 tests）
- `bash -n codex-tools/setup-home-links.sh`: PASS
- `bash codex-tools/tests/setup-home-links.test.sh`: PASS
- `python -B -m unittest discover -s tests -p '*_test.py' -v`: PASS（19 tests）
- `git diff --check`: PASS
- 全テストはtemporary directoryのみを使用し、実ユーザーホームのbootstrap/restoreは実行していない。

## P1修正後の独立再レビュー

- 新規レビューエージェントがPOSIX renameによる`st_ctime_ns`更新をP1として検出した。ctimeをidentityから除外し、ctimeだけが変わるquarantine rename再現テストをREDから追加した。
- 再レビューはP0/P1なし。inode/dev・mode・target・reparse tagによる差し替え検知は維持されることを確認した。
