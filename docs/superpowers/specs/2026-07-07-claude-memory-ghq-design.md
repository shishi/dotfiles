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

1. `CLAUDE_MEMORY_DIR` が**非空で**セットされていればそれを使う(devcontainer 等の逃げ道)。
   未設定と空文字は同じく「未指定」として扱う(現行の `${VAR:-default}` の挙動を維持)。
   値は返す前に絶対化する: 先頭 `~/` は `$HOME/` に展開、相対パスは
   `$(pwd -P)` 基準で絶対化する。相対パスのまま `ln -sfn` に渡ると symlink
   target が `$DOTDIR/claude` からの相対として解釈され、clone 先と参照先が
   ズレるため。

パスの正規化(全経路共通): ヘルパーが stdout に出すパスは POSIX 形式
(`/` 始まり)に正規化する。Git Bash/MSYS では `CLAUDE_MEMORY_DIR` や
`git config --type=path` が `C:/Users/...` のような drive-letter 形式を
返し得るが、そのままでは setup.sh 側の「`/` 始まり」検証で弾かれて
Windows だけ claude-memory セクションがスキップされてしまう。
`cygpath` が使える環境では `cygpath -u -a` で `/c/...` 形式へ変換してから
出力する(cygpath がない環境で drive-letter 形式が来ることは想定しない)。
2. ghq root が見つかれば `<ghq_root>/github.com/shishi/claude-memory`。
   ghq 本体と同じ優先順で解決する:
   - `GHQ_ROOT` 環境変数。値の先頭 `~/` は `$HOME/` に手動展開する
     (実環境でチルダのまま格納されていることを確認済み)。
   - なければ `git config --type=path --get-all ghq.root | head -n1`。
     `--type=path` により git 自身がチルダ展開する。複数値時に先頭を
     採用するのは ghq の primary root の仕様に合わせた挙動。
3. どちらもなければ従来どおり `~/dev/claude-memory`。

## 既存 clone の移行

移行はヘルパー内で行う。実行時はまず `mkdir -p "$(dirname "$resolved")"` で
解決先の親ディレクトリ(fresh 環境では `<ghq_root>/github.com/shishi` が
未作成)を作ってから `mv` する。移行(`mv`)は以下の条件を**すべて**満たす
場合のみ実行する:

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
- 旧・新の両方が既に存在する → 移行せず警告し、以下の順で返すパスを決める。
  上書き・削除は一切行わない(重複の解消はユーザーが手動で行う):
  1. `${DOTDIR}/claude/memory` symlink が旧・新どちらかを指していれば
     その指す先を返す(現に使われている側を維持し、書き込み先を変えない)。
  2. symlink で現用側を判定できなければ**旧パスを返す**。origin 一致は
     「同じ repo らしい」ことしか保証せず、新が古い clone だった場合に
     書き込み先が勝手に切り替わって旧側の未 push 記憶が orphan になるため、
     自動で新へ寄せない(警告で手動解消を促す)。

移行が成功した場合の symlink 張り直しは既存の `ln -sfn` 処理がそのまま行う
(条件 4 により symlink であることが保証済み)。

## clone と symlink

現行の clone フォールバック(ssh → gh → 手動案内メッセージ)と
`claude/memory` symlink 処理は変更しない。対象パスが解決結果に変わるだけ。

## 実装配置(案 A)

- **`claude/resolve-memory-dir.sh`(新規)**: パス解決+移行を担う独立ヘルパー。
  - exit contract: 成功時は exit 0 で stdout に解決済み**絶対パスを 1 行だけ**
    echo する。パスを決定できない内部失敗時は非 0 で終了する
    (移行の中止は失敗ではない — 安全側のパスを返して exit 0)。
  - 移行(mv)もこのスクリプト内で行い、警告は stderr に出す
    (stdout はパスのみに保つ)。
  - 入力はすべて環境変数(`CLAUDE_MEMORY_DIR` / `GHQ_ROOT` / `HOME` /
    `DOTDIR` / git のグローバル設定)経由なので、テストから差し替え可能。
- **`setup.sh`(変更 1)**: OS 別 `.gitconfig` symlink のブロックを
  claude-memory 処理より**前**に移動する。現状は後にあるため、fresh 環境の
  初回実行では `git config ghq.root` が引けず旧パスに clone →次回実行で移行、
  という二段階挙動になってしまう。先に張れば初回から ghq 形式に置ける。
- **`setup.sh`(変更 2)**: 固定の
  `CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/dev/claude-memory}"` を
  `CLAUDE_MEMORY_DIR="$(DOTDIR="$DOTDIR" bash "${DOTDIR}/claude/resolve-memory-dir.sh")"`
  に置き換える(`DOTDIR` は setup.sh 内の shell 変数で export されていないため、
  呼び出し時に明示的に渡す)。ヘルパー側は `DOTDIR` が空なら移行を行わない
  (fail closed — 条件 4 が判定できない状態で mv しない)。
  setup.sh は substitution の終了コードと出力を検証し、ヘルパーが非 0 または
  stdout が「`/` 始まりの非空 1 行」でない場合は警告を出して claude-memory
  セクション全体(clone・symlink)をスキップする(setup.sh には `set -e` が
  ないため、検証しないと壊れた値のまま後続処理へ進んでしまう)。
- **`setup.sh`(変更 3)**: clone 実行前に
  `mkdir -p "$(dirname "${CLAUDE_MEMORY_DIR}")"` を追加する。ghq root 配下の
  中間ディレクトリ(例: `~/dev/src/github.com/shishi`)は fresh 環境に存在せず、
  `git clone` は親を作らないため。以降の clone・symlink 処理は無変更。
- **`.gitignore`(変更)**: `/claude/*` の無視に対するホワイトリスト行
  `!/claude/resolve-memory-dir.sh` を追加する。

## テスト

`tests/claude-memory-ghq.sh`(新規)。既存テストと同じプレーン bash スモーク形式
(`pass`/`fail` カウント、一時ディレクトリ使用)。`GIT_CONFIG_GLOBAL` に偽 gitconfig、
`HOME` に一時ディレクトリを向けて実挙動を検証する:

1. `CLAUDE_MEMORY_DIR` セット時 → その値(絶対化済み)が返る(最優先)。
   相対パス・`~/` 始まりの値は絶対パスに変換されて返る。
2. `CLAUDE_MEMORY_DIR=""`(空文字)→ 未指定扱いで ghq 解決に進む。
3. `GHQ_ROOT=~/xxx`(チルダ)→ `$HOME/xxx/github.com/shishi/claude-memory` に展開される。
4. `GHQ_ROOT` なし・gitconfig に `ghq.root = ~/yyy` → gitconfig 側で解決される。
5. gitconfig に ghq.root が複数 → 先頭の値が使われる。
6. どちらもなし → `$HOME/dev/claude-memory` にフォールバック。
7. 旧パスに正規 clone(.git + origin 一致)あり・新パス未存在 → mv で移行され、返り値は新パス。
8. 旧パスが claude-memory の clone でない(.git なし or origin 不一致)→ 移行されず旧パスが返る(警告)。
9. `${DOTDIR}/claude/memory` が実体ディレクトリ → 移行されず旧パスが返る(警告)。
10. 旧・新両方存在・symlink が旧を指す → 返り値は旧パス(現用側を維持、警告)。
11. 旧・新両方存在・symlink が新を指す → 返り値は新パス(警告)。
12. 旧・新両方存在・symlink 判定不能 → 返り値は旧パス(自動で新へ寄せない、警告)。
13. `DOTDIR` 未設定でヘルパーを直接呼ぶ → 移行は行われない(fail closed)。
14. 旧パスに正規 clone あり・新パスの親ディレクトリごと未存在 → ヘルパーが
    親を `mkdir -p` してから mv し、実行後は `new/.git` が存在し旧パスは消えている。
15. stdout は常にパス 1 行のみ(警告が混入しない)。
16. `CLAUDE_MEMORY_DIR=C:/tmp/memory` かつ `cygpath` が利用可能(PATH 上の
    stub で模擬)→ `/c/tmp/memory` 形式に正規化されて返る。

加えて setup.sh の順序検証: `.gitconfig` symlink 処理が claude-memory 処理より
前にあることを確認する(grep ベースの行番号比較で足りる)。

## 対象外(YAGNI)

- ghq バイナリ(`ghq get`)の利用。
- github.com 以外のホストや repo 名の一般化(このリポジトリ専用でよい)。
- 旧パスから新パスへの symlink 残置などの互換レイヤ。
