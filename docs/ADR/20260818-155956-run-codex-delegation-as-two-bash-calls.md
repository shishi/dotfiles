# codex への委譲を 2 回の Bash 呼び出しと 1 回の Write で実行する

| | |
|---|---|
| **Status** | accepted |
| **Date** | 2026-08-18 |
| **Decision-makers** | shishi |
| **Consulted** | codex(correctness レビュー 3 巡)、Claude subagent(spec-scope レビュー) |
| **Informed** | `claude/skills/codex-delegate/SKILL.md` を読むエージェント |

## Context and Problem Statement

Claude Code のトークン消費を抑えるため、探索・定型作業・実装を codex CLI へ委譲する。削減量を決めるのは委譲そのものではなく、**委譲結果が Claude の context に入る経路**である。`codex exec` の stdout は進捗ログとトークン計を含む全文を返すため、素朴に呼ぶと削減が成立しない。

同時に、プロンプトにはリポジトリから引用したコードが入る。この本文をシェルに通すと、本文由来のコード実行に至る経路が開く。

この ADR は実行形の各要素がなぜその形なのかを記録する。**実行するコマンドの正本は `claude/skills/codex-delegate/SKILL.md` の `### 3.` のスニペット**であり、本 ADR はコマンドを持たない。両方に置くと乖離し、乖離した側を読んだ者が動かない手順に従う。

## Decision Drivers

* Claude の context 増分を、codex の出力量に依存しない上限で切れること
* プロンプト本文がシェルの解釈を受けないこと
* 障害対応中に読まれる情報(終了コード・失敗ログ)が有限で、原因が判別できること
* `rm -rf` を含む後始末が、この手順が作ったディレクトリの外に届かないこと
* skill 本文は委譲のたび context に載るため、手順以外を skill に置かないこと

## Considered Options

1. **2 回の Bash 呼び出しの間に Write を挟み、最終メッセージを `-o` のファイルへ落とす**
2. `codex exec` を 1 回の Bash 呼び出しで済ませ、プロンプトを heredoc で渡す
3. openai-codex プラグインの `codex-companion.mjs` を呼ぶ

## Decision Outcome

**Chosen option**: 「2 回の Bash 呼び出しの間に Write を挟む」。プロンプトをシェルに通さない要件と、`-o` で最終メッセージだけを取り出す要件を同時に満たす形が他に無い。

### Consequences

**Positive:**

* 同一の実行に対し、stdout は 128,602 バイト、`-o` のファイルは 2,775 バイトだった。受け取る量が codex の出力量から切り離される
* プロンプトにバッククォートと `$(...)` を含めて渡しても、置換されずに codex へ到達する
* 作業ディレクトリを毎回作るので、前回の残骸を次の実行が読む取り違えが起きない

**Negative:**

* 呼び出しが 2 回に分かれるため、1 回目が返したパスを 2 回目へ貼る手作業が挟まる。貼り間違いが `rm -rf` の対象を誤らせる経路になり、パスの形の照合が要る
* 後始末を同じ呼び出しに置く制約から、`out.json` を後で読み直すことができない

**Neutral:**

* 失敗時のログは末尾 4,000 バイトだけが残る。全文はどの経路でも残らない

### Confirmation

`codex-delegate` skill の変更時は shell block を抽出し、`zsh -n` と `sh -n` で直接検証する。`--config`、出力先、後始末の順序は diff で確認し、skill 本文を写経する静的テストは置かない。

実挙動のうち確認済みのもの — `-s` の実効性(`read-only` は書き込みを拒否し、`workspace-write` + `writable_roots=[]` は workspace 内を許してホームを拒否する)、`network_access` の実効性と `read-only` では効かないこと、記憶ストアの論理内容が委譲を跨いで変わらないこと、プロンプトがシェルを経由しないこと、schema の上限が実際に切ること、使用済み判定の原子性、パスの形の照合、認証失敗で作業ディレクトリが残らないこと、Bash の timeout が委譲を SIGTERM で終了させて codex の子プロセスまで届くこと、background で起動した委譲が完走して JSON が task の出力に載ること。

**未確認で、実挙動として残っているもの:**

1. `/codex:rescue` と `/codex:status` が発動しないこと(プラグイン撤去の反映にセッション再起動が要る)

**`codex --version` が変わったら、`--config` のキー名の検証(空の `CODEX_HOME` を向けた `--strict-config`)と上記の実挙動を再実行する。** キーが改名された場合の失敗は、エラーではなく沈黙として現れる。

## Pros and Cons of the Options

### 2 回の Bash 呼び出しの間に Write を挟む

`mktemp -d` でパスを返す → Write で `prompt.md` を書く → 走査・実行・取り出し・後始末。

* Good, because プロンプトがシェルを経由しないので、本文由来のコード実行の経路が存在しない
* Good, because `-o` と stdout のリダイレクトで、context に入る量を schema の上限で切れる
* Bad, because 手で貼るパスが 1 つ増える
* Neutral, because 3 つの実行文脈(sandbox 内・sandbox 外・Write)が同じ絶対パスを指す必要があるが、これは実測で成立している

### heredoc でプロンプトを渡す

* Bad, because 引用符なしのデリミタは zsh が本文中の `` ` `` と `$(...)` をコマンド置換として実行する
* Bad, because 引用符を付けても、デリミタと同一の行が本文にあればそこで heredoc が終わり、残りがコマンドになる。デリミタを長くしても閉じない — この skill の手順や設計 doc を codex に渡す委譲では、その本文自体にデリミタの行が載る
* Bad, because どちらも構文としては正しいので `zsh -n` も `sh -n` も検出しない

### `codex-companion.mjs` を呼ぶ

* Bad, because 呼び出しパスがバージョン番号を含み(`~/.claude/plugins/cache/openai-codex/codex/<version>/scripts/`)、PATH に登録される同バージョンの `bin` は実体が存在しない。バージョン非依存で呼ぶ手段がないため、プラグイン更新のたびにパスが壊れる
* Bad, because 出力を verbatim で返すので、削減の目的に反する

## 各要素の理由

以下は `SKILL.md` の `### 3.` のスニペットの各要素が、なぜその形・その位置なのか。

### 出力経路

* **codex の stdout と stderr はログファイルへ逃がす。** `-o` は最終メッセージを別に保存するだけで、リダイレクトしなければ進捗出力全文が context に入る
* **失敗時にログを出す量はバイトで区切る。** 行数で区切ると、1 行が JSON や stack trace になる codex のログでは上限にならない。失敗経路は認証切れや利用枠切れで日常的に通るため、ここが唯一の無制限経路にならないようにする
* **実行・結果の取り出し・後始末は同じ呼び出しに置く。** `trap ... EXIT` はそのシェルの終了で発火するため、後始末を別の呼び出しに分けると次の呼び出しが読む前に `out.json` が消える。プロンプトの書き出しはこの制約の対象外で、先に分けてよい

### 後始末と取り違え

* **パスの形を照合してから `rm -rf` の射程に入れる。** `trap` が消すのは変数の指す先なので、貼り間違いがそのまま任意のディレクトリの再帰削除になる。手順自身が貼り間違いを想定している以上、これは到達する経路である。`prompt.md` という名前のファイルは委譲の作業ディレクトリに限らず存在しうるため、その存在だけでは射程を絞れない
* **照合は最後の要素(`${WORK##*/}`)に対して行う。** パス全体を `*/codex-delegate-*` で見る形だと末尾の `*` が `/` も含むため、`/tmp/codex-delegate-ABCDEF/../victim` のような形が通り抜ける
* **「使用済み」の目印は `mkdir` で取る。** `mkdir` は既存のディレクトリに対して失敗するので、存在を見てから作る形と違って確認と作成のあいだに隙が無い。同じパスを 2 つの呼び出しへ貼っても、成功した側だけが codex を起動する。`out.json` と `run.log` は目印に使えない — `out.json` が存在するのは正常終了した委譲だけで、その経路ではディレクトリごと消えており、`run.log` はリダイレクトで作られるので判定より後になる
* **`mkdir` の失敗を握り潰さない。** 96 は「既に起動している」と「目印を作れない」の両方を含み、`mkdir` のエラー文で区別できる。これは 98 が「検出あり」と「gitleaks が動かない」を兼ねるのと同じ形で、どちらも委譲しない条件であることが共通している
* **目印を取るのは gitleaks より後、`trap` を張るのは目印より後、`cp` は `trap` より後。** gitleaks の検出は「直して再委譲する」経路なので、そこではまだディレクトリを残す。`cp` が目印より前だと、同じパスを貼った 2 つ目の呼び出しが実行中の委譲の `schema.json` を書き換えうる。`cp` が `trap` より後だと、失敗したディレクトリが後始末の対象に入る
* **`trap ... EXIT` は、張ったあとにシェルが通常終了すればどの経路でも発火する。** `cp` の失敗も認証失敗も含む。発火しないのはシグナルで終わる 2 経路 — Bash の timeout(SIGTERM)と task の停止。この 2 経路では作業ディレクトリが残るが、作成先はシステムの一時領域であり、その掃除に委ねる
* **作業ディレクトリは `${TMPDIR:-/tmp}` 配下に明示的に作る。** 引数なしの `mktemp -d` は Claude Code の Bash sandbox 内で `Operation not permitted` になる(`TMPDIR` 環境変数を見ず、許可されていない場所を使う)。`/tmp` 直下を指定する形も同じ理由で通らない。フォールバックは `TMPDIR` 未設定の環境でファイルシステム直下に作らせないためのもの
* **作業ディレクトリはリポジトリ外に置く。** リポジトリ内だと untracked としてレビュー対象に混入する

### sandbox と config

* **`-s` は必ず指定する。** `~/.codex/config.toml` の `sandbox_mode` は `workspace-write` で、`-s` を書かない `codex exec` は explore でも書き込みできる状態で走る。この既定値は codex 自身が config を書き換えることもあるため、呼び出し側で毎回固定し、指定のない呼び出し形を持たない
* **`-s` が上書きするのは `sandbox_mode` だけである。** 書き込みルート・ネットワーク到達性・承認方針・記憶機能は config の側に残るため、CLI で毎回渡す。CLI で渡せば、config が書き換わっても次の実行には効かない
* **`writable_roots=[]` でも一時領域は書き込み可能なままである。** `workspace-write` は workspace の外を拒否するが、`$TMPDIR` と `/tmp` は codex 側の既定で許可される。塞がるのはホームディレクトリなど「workspace でも一時領域でもない場所」であり、書き込みが workspace 内に限られるとは読まない。委譲の作業ディレクトリも一時領域にあるため、委譲先からは他の委譲の作業ディレクトリにも手が届く
* **Codex native Memories を二重に無効化する。** global config では、Claude Code / Codex 共有の `agent-memory` を唯一の正本にするため無効化済みである。委譲呼び出しは `features.memories=false`、`memories.generate_memories=false`、`memories.use_memories=false` を毎回渡す。この三重指定は、config の変更や既定値のドリフトが委譲に影響するのを防ぐ防御層である
* **キーの綴りが正しいことと効いていることは別である。** 綴りは、空の `CODEX_HOME` を向けた `--strict-config` で検証する(通常の config には Windows 用の `computer_use` セクションがあり、strict を付けると起動前に落ちる)。strict を外した実行では存在しないキーが素通りするので、受理されたことは何の証拠にもならない。`codex --version` が変わったら綴りと実挙動を再検証する — キーが改名された場合の失敗は、エラーではなく沈黙として現れる
* **`--dangerously-bypass-approvals-and-sandbox` は使わない。** その形は codex-review skill が「他の用途で使わない」と限定しており、本設計はその限定を変更しない。`-s` が効かない環境では委譲しない — `read-only` も `workspace-write` も担保にならず、explore が読むだけである保証も失われる。codex の Linux sandbox は unprivileged user namespace を要する bubblewrap に依存するため、多くのコンテナでは機能しない

### 検査

* **スニペットは `zsh -n` と `sh -n` の両方で検査する。** Claude Code の Bash tool が実行するのは zsh(5.9.2)であり bash ではない。`bash -n` は実行系と異なる言語を検査するため、通っても保証にならない。zsh と bash の差はクォートしない変数展開の単語分割やマッチしない glob の扱いに現れ、構文検査では捕まらない
* **`codex exec` は Bash 呼び出しの中で素のコマンドとして書く。** `sandbox.excludedCommands` は行のテキストではなく実行されるコマンドを照合するため、シェル関数・エイリアス・`sh -c` に包むと `codex` が照合から隠れ、その呼び出しは Claude Code の Bash sandbox 内で走る。sandbox は TLS を傍受するので、codex 自身の API 接続が `invalid peer certificate: UnknownIssuer` で切れる。権限エラーではなく証明書エラーとして現れるため、原因がメッセージに出ない
* **プロセスの残存をコマンドで確かめない。** Bash sandbox 内では `pgrep` も `ps` も `operation not permitted` で失敗しながら終了コード 0 を返すため、外部のプロセス一覧に問い合わせる形の確認はすべて「該当なし」と答える。走っている委譲の有無は、未完了の background task があるかどうかで見る
* **`schema.json` は skill 配下の実ファイルを `cp` する。** 出力契約の単一ソースを skill 側に置き、二重管理を避ける

## More Information

* 実行手順の正本: `claude/skills/codex-delegate/SKILL.md`
* 出力契約: `claude/skills/codex-delegate/schema.json`
* 発火の判断基準: `claude/CLAUDE.md` の「Codex への委譲」節
* `~/.codex` を dotfiles の `codex/` に向ける前提: [20260816-180256-link-codex-home-from-setup-sh](20260816-180256-link-codex-home-from-setup-sh.md)
