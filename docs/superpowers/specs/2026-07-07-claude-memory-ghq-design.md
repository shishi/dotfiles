# claude-memory の ghq 形式配置 — 設計

日付: 2026-07-07
ステータス: 承認待ち

## 目的

setup.sh が claude-memory(個人永続記憶、private repo)を clone する際、
ghq.root が設定されている環境では ghq のディレクトリ規約
(`<ghq_root>/github.com/shishi/claude-memory`)に配置し、
リポジトリ管理を ghq に一元化できるようにする。

## 背景

- 現状は `~/dev/claude-memory` 固定(`CLAUDE_MEMORY_DIR` で上書き可)。
- 全 OS の gitconfig(.gitconfig.mac / .linux / .win)に `ghq.root = ~/dev/src` があり、
  環境変数 `GHQ_ROOT=~/dev/src` もセットされている。
- ghq root 配下に規約どおり置けば、`ghq list` 等でほかのリポジトリと同様に扱える。
  ghq バイナリには依存しない(パス規約だけ借りる)。

## パス解決ロジック

優先順位(上が勝ち):

1. `CLAUDE_MEMORY_DIR` が明示セットされていればそのまま使う(現行維持。devcontainer 等の逃げ道)。
2. ghq root が見つかれば `<ghq_root>/github.com/shishi/claude-memory`。
   ghq 本体と同じ優先順で解決する:
   - `GHQ_ROOT` 環境変数。値の先頭 `~/` は `$HOME/` に手動展開する
     (実環境でチルダのまま格納されていることを確認済み)。
   - なければ `git config --type=path --get-all ghq.root | head -n1`。
     `--type=path` により git 自身がチルダ展開する。複数値時に先頭を
     採用するのは ghq の primary root の仕様に合わせた挙動。
3. どちらもなければ従来どおり `~/dev/claude-memory`。

## 既存 clone の移行

- 解決パス ≠ 旧デフォルト(`~/dev/claude-memory`)かつ、旧パスに実体ディレクトリがあり、
  解決パスが未存在の場合: `mkdir -p` で親ディレクトリを作り `mv` で移行する。
- 旧・新の両方が存在する場合: 移行せず警告メッセージを出し、解決パス(新)を使う。
  データ破壊につながる上書き・削除は行わない。
- 移行後の symlink 張り直しは既存の `ln -sfn` 処理がそのまま行うため追加処理は不要。

## clone と symlink

現行の clone フォールバック(ssh → gh → 手動案内メッセージ)と
`claude/memory` symlink 処理は変更しない。対象パスが解決結果に変わるだけ。

## 実装配置(案 A)

- **`claude/resolve-memory-dir.sh`(新規)**: パス解決+移行を担う独立ヘルパー。
  - stdout に解決済み絶対パスを 1 行 echo する。
  - 移行(mv)もこのスクリプト内で行い、警告は stderr に出す
    (stdout はパスのみに保つ)。
  - 入力はすべて環境変数(`CLAUDE_MEMORY_DIR` / `GHQ_ROOT` / `HOME` /
    git のグローバル設定)経由なので、テストから差し替え可能。
- **`setup.sh`(変更)**: 固定の
  `CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/dev/claude-memory}"` を
  `CLAUDE_MEMORY_DIR="$(bash "${DOTDIR}/claude/resolve-memory-dir.sh")"` に置き換える。
  以降の clone・symlink 処理は無変更。
- **`.gitignore`(変更)**: `/claude/*` の無視に対するホワイトリスト行
  `!/claude/resolve-memory-dir.sh` を追加する。

## テスト

`tests/claude-memory-ghq.sh`(新規)。既存テストと同じプレーン bash スモーク形式
(`pass`/`fail` カウント、一時ディレクトリ使用)。`GIT_CONFIG_GLOBAL` に偽 gitconfig、
`HOME` に一時ディレクトリを向けて実挙動を検証する:

1. `CLAUDE_MEMORY_DIR` セット時 → その値がそのまま返る(最優先)。
2. `GHQ_ROOT=~/xxx`(チルダ)→ `$HOME/xxx/github.com/shishi/claude-memory` に展開される。
3. `GHQ_ROOT` なし・gitconfig に `ghq.root = ~/yyy` → gitconfig 側で解決される。
4. gitconfig に ghq.root が複数 → 先頭の値が使われる。
5. どちらもなし → `$HOME/dev/claude-memory` にフォールバック。
6. 旧パスに実体あり・新パス未存在 → mv で移行され、返り値は新パス。
7. 旧・新両方存在 → mv されず両方残り、返り値は新パス(stderr に警告)。

## 対象外(YAGNI)

- ghq バイナリ(`ghq get`)の利用。
- github.com 以外のホストや repo 名の一般化(このリポジトリ専用でよい)。
- 旧パスから新パスへの symlink 残置などの互換レイヤ。
