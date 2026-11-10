# dotfiles

シェル、エディター、ターミナル、AI エージェント (Claude Code・Codex) の設定を管理するリポジトリです。公開リポジトリなので、個人のマシン名、私的なパスや接続先、認証情報を書き込みません。

## 作業の進め方

- このリポジトリは master 1 本で開発します。タスク用の worktree やブランチは作らず、master の checkout で直接変更して commit します。
- 同じ checkout で別のセッションも作業するため、自分以外の未コミット変更が残っていることがあります。commit するのは自分の変更だけにし、ほかの変更は戻さずに残します。

## 構成

- `setup.sh`: 各設定をホームディレクトリへ symlink で配備します。配備先は repo の実ファイルを指すため、変更は配備先のファイルにそのまま反映されます。ツールへの適用には、再読み込みや再起動、hook の信頼し直しが必要な場合があります。
- `claude/`・`codex/`: Claude Code と Codex のホーム (`~/.claude`・`~/.codex`) の Git 管理部分です。共通の指示は `codex/AGENTS.md` が正本で、`claude/CLAUDE.md` から読み込みます。
- `agent-shared/`: 両エージェントが共有する hook (`hooks/`) と補助スクリプト (`bin/`)、操作の判定ルールの正本 (`policy/action-policy.json`) です。
- `docs/`: 利用者向けの文書です。エージェントまわりの仕組みは `docs/agents.md` にまとめています。
- そのほかのディレクトリは各ツールの設定です (fish、nushell、nvim、helix、wezterm、ghostty、herdr など)。

## 変更するときの注意

- スクリプトは原則 sh / bash で書きます。それで難しい理由がある場合だけ python など普及した言語を使います。
- 改行コードは、既存のファイルでは今の改行を保ちます (CRLF のファイルも混在しています)。新しいファイルは同じ種類の既存ファイルに合わせ、特に理由がなければ LF にします。
- `codex/config.toml` は Codex 自身も書き換えます。Git の clean フィルター (`setup.sh` が設定) が端末ごとの値を除くので、commit 前に差分に余計な行が混ざっていないか確認します。
- 操作の判定ルールは `agent-shared/policy/action-policy.json` を直し、`python3 agent-shared/bin/apply-action-policy` で `claude/settings.json` と `codex/config.toml` へ書き出します。`--check` で設定とのずれを確かめます。
- `codex/hooks.json` の hook を追加・変更すると、利用者が Codex の `/hooks` で信頼し直すまで動きません。
- `claude/skills/` と `codex/skills/` の両方にある skill は、エージェント名を除いて同じ内容に保ちます (`tests/skills-sync.sh` で確認)。review-gate の観点 agent も `claude/agents/*.md` と `codex/agents/*.toml` で同じ本文に保ちます。

## テスト

テストは手動で実行します。変更した仕組みに関係するものを走らせます。

- `agent-shared/hooks/*.test.sh`: hook のテスト (`bash <ファイル>`)
- `tests/`: 設定・skill の同期、補助スクリプト、出力ゲートなどのテスト。`.sh` は `bash <ファイル>`、`.py` は `python3 <ファイル>`、nvim 用の `.lua` は各ファイルの先頭に書いたコマンドで実行します。`tests/output-gate-rules-live*.py` は検査役のモデルを実際に呼ぶため、時間と利用枠を使います。
