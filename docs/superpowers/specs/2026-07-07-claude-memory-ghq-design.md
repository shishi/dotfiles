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

1. `CLAUDE_MEMORY_DIR` が**非空で**セットされていればそのまま使う(devcontainer 等の逃げ道)。
   未設定と空文字は同じく「未指定」として扱う(現行の `${VAR:-default}` の挙動を維持)。
2. ghq root が見つかれば `<ghq_root>/github.com/shishi/claude-memory`。
   ghq 本体と同じ優先順で解決する:
   - `GHQ_ROOT` 環境変数。値の先頭 `~/` は `$HOME/` に手動展開する
     (実環境でチルダのまま格納されていることを確認済み)。
   - なければ `git config --type=path --get-all ghq.root | head -n1`。
     `--type=path` により git 自身がチルダ展開する。複数値時に先頭を
     採用するのは ghq の primary root の仕様に合わせた挙動。
3. どちらもなければ従来どおり `~/dev/claude-memory`。

## 既存 clone の移行

移行(`mv`)は以下の条件を**すべて**満たす場合のみ実行する:

1. 解決パス ≠ 旧デフォルト(`~/dev/claude-memory`)。
2. 旧パスが実体ディレクトリで、解決パスが未存在。
3. 旧パスが本当に claude-memory の clone であること:
   `[ -d old/.git ]` かつ `git -C old remote get-url origin` が
   `shishi/claude-memory`(ssh/https いずれの形式でも)にマッチする。
4. `${DOTDIR}/claude/memory` が未存在または symlink であること。
   実体ディレクトリの場合(Git Bash の `ln -s` コピー問題等)は移行しても
   symlink が張り直されず記憶の書き込み先が二重化するため、移行を中止して
   警告し、旧パスを返す(手動修復を促す)。

失敗時の扱い:

- 条件 3 を満たさない(repo でない・origin 不一致)→ 移行せず警告し、
  **旧パスを返す**(動いている状態を壊さない)。
- `mv` 自体が失敗した、または移行後に `new/.git` が確認できない →
  警告し、旧パスがまだ存在すれば旧パスを返す。中途半端な新パスは採用しない。
- 旧・新の両方が既に存在する → 移行せず警告する。新パスに `new/.git` が
  あれば新を返し、なければ(過去の部分 mv の残骸等)旧を返す。
  上書き・削除は一切行わない(どちらが最新かはユーザーが手動で確認する)。

移行が成功した場合の symlink 張り直しは既存の `ln -sfn` 処理がそのまま行う
(条件 4 により symlink であることが保証済み)。

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
- **`setup.sh`(変更 1)**: OS 別 `.gitconfig` symlink のブロックを
  claude-memory 処理より**前**に移動する。現状は後にあるため、fresh 環境の
  初回実行では `git config ghq.root` が引けず旧パスに clone →次回実行で移行、
  という二段階挙動になってしまう。先に張れば初回から ghq 形式に置ける。
- **`setup.sh`(変更 2)**: 固定の
  `CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/dev/claude-memory}"` を
  `CLAUDE_MEMORY_DIR="$(bash "${DOTDIR}/claude/resolve-memory-dir.sh")"` に置き換える。
  ヘルパーには `DOTDIR` を環境変数で渡す(条件 4 の判定に必要)。
  以降の clone・symlink 処理は無変更。
- **`.gitignore`(変更)**: `/claude/*` の無視に対するホワイトリスト行
  `!/claude/resolve-memory-dir.sh` を追加する。

## テスト

`tests/claude-memory-ghq.sh`(新規)。既存テストと同じプレーン bash スモーク形式
(`pass`/`fail` カウント、一時ディレクトリ使用)。`GIT_CONFIG_GLOBAL` に偽 gitconfig、
`HOME` に一時ディレクトリを向けて実挙動を検証する:

1. `CLAUDE_MEMORY_DIR` セット時 → その値がそのまま返る(最優先)。
2. `CLAUDE_MEMORY_DIR=""`(空文字)→ 未指定扱いで ghq 解決に進む。
3. `GHQ_ROOT=~/xxx`(チルダ)→ `$HOME/xxx/github.com/shishi/claude-memory` に展開される。
4. `GHQ_ROOT` なし・gitconfig に `ghq.root = ~/yyy` → gitconfig 側で解決される。
5. gitconfig に ghq.root が複数 → 先頭の値が使われる。
6. どちらもなし → `$HOME/dev/claude-memory` にフォールバック。
7. 旧パスに正規 clone(.git + origin 一致)あり・新パス未存在 → mv で移行され、返り値は新パス。
8. 旧パスが claude-memory の clone でない(.git なし or origin 不一致)→ 移行されず旧パスが返る(警告)。
9. `${DOTDIR}/claude/memory` が実体ディレクトリ → 移行されず旧パスが返る(警告)。
10. 旧・新両方存在(新に .git あり)→ mv されず両方残り、返り値は新パス(stderr に警告)。
    新に .git がなければ返り値は旧パス。
11. stdout は常にパス 1 行のみ(警告が混入しない)。

加えて setup.sh の順序検証: `.gitconfig` symlink 処理が claude-memory 処理より
前にあることを確認する(grep ベースの行番号比較で足りる)。

## 対象外(YAGNI)

- ghq バイナリ(`ghq get`)の利用。
- github.com 以外のホストや repo 名の一般化(このリポジトリ専用でよい)。
- 旧パスから新パスへの symlink 残置などの互換レイヤ。
