---
name: codex-delegate
description: |
  作業を codex CLI へ委譲して Claude Code のトークン消費を抑えるアダプタ。
  探索(read-only)・定型作業・plan 確定後の実装を codex exec で実行し、
  結果は schema で上限を切った JSON 1 通だけ受け取る。CLAUDE.md の判断基準で
  自律発火する、または /codex-delegate で明示発動。レビューは委譲しない
  (review-gate / codex-review の責務)。
---

# Codex Delegate

codex CLI に作業をさせ、Claude が受け取るのは JSON 1 通だけにする。codex の進捗出力は
ログファイルへ逃がし、失敗したときだけ末尾を読む。

委譲で入った変更は Claude 自身が書いた変更と同じものとして扱う。エージェントがファイルを
編集するという点で両者に差はなく、意図した変更かどうかの判断はどちらの場合もオーケストレータ
である Claude が差分を見て行う。したがって**委譲専用の検査機構は持たない** — 妥当性は差分の
確認と review-gate skill で見る。

## 前提条件

1. **`~/.codex` が dotfiles の `codex/` を指していること**(`readlink ~/.codex`)。この link で
   委譲先が `codex/AGENTS.md` の規律(TDD・Git 安全性)を持つ。AGENTS.md は TDD の手順を
   本文に書いており skill の存在に依存しない。**満たさないマシンでは chore と implement を
   委譲しない**(規律を持たない委譲先にコードを書かせることになる)。explore は読むだけなので
   この前提は不要
2. `codex` CLI が PATH にある(`command -v codex`)
3. `claude/settings.json` の `sandbox.excludedCommands` に `codex:*` があること。無いと codex の
   app-server 初期化が `Operation not permitted` で落ちる
4. `gitleaks` が動くこと。動かない環境では委譲しない
5. OpenAI 側の利用枠が残っていること。枯渇すると起動直後に失敗する(メッセージは認証方式に
   よって異なる)。**Claude 側の消費を減らす代わりにこの枠を消費する。** 委譲が正味の節約に
   なっているかは、context 増分ではなく両方の消費で判断する
6. **`workspace-write` の委譲は worktree が clean な状態から始める。** clean でなければ委譲
   しない。codex による上書きは差分に現れない — 既存の未コミット変更を書き直されると、その
   内容は worktree からも差分からも消え、元々そこに何があったかを復元する材料が残らない。
   事後の検査では捕まえられないので、上書きされる対象が存在しない状態から始める

## 委譲種別

| 種別 | `-s` | 内容 |
|---|---|---|
| explore | `read-only` | 所在探索、原因調査、コードベースの読解 |
| chore | `workspace-write` | リネーム、同パターンの横展開、テスト追加 |
| implement | `workspace-write` | plan 確定後の feature / bugfix |

委譲しないもの:

- 設計判断、およびユーザーとの対話が要る作業
- 個人記憶リポジトリへの書き込み。記憶は Claude Code 専用で、権限境界の管理主体を移さない
- レビューゲートそのもの。review-gate skill と codex-review skill の責務
- gitleaks がプロンプトから secrets を検出した作業。検出をゼロにできるまで委譲しない
- ネットワークを要する作業(依存の取得・更新、lockfile の更新)。`network_access=false` を
  毎回固定しているため完了しない。依存が未インストールのリポジトリでは、AGENTS.md が求める
  テストや build の実行自体がこれに当たる

## 手順

**プロンプトはシェルを経由させない。** そのため呼び出しを 2 回に分け、間に Write ツールを挟む。

### 1. 作業ディレクトリを作る

```sh
WORK=$(mktemp -d "${TMPDIR:-/tmp}/codex-delegate-XXXXXX") && chmod 700 "$WORK" && echo "$WORK"
```

### 2. Write ツールで `<返されたパス>/prompt.md` を書く

Bash で書かない。heredoc もシェル文字列も使わない。プロンプトにはリポジトリから引用した
コードが入るため、シェルを経由させると本文由来のコード実行に至る経路が 2 本開く。デリミタから
引用符を外せば zsh が本文中の `` ` `` と `$(...)` をコマンド置換として実行し、引用符を付けても、
デリミタと同一の行が本文にあればそこで heredoc が終わって残りがコマンドになる。後者は綴りを
長くしても閉じない — この skill の手順や設計 doc を codex に渡す委譲では、その本文自体に
デリミタの行が載る。どちらも構文としては正しいので `zsh -n` も `sh -n` も検出しない。
Write ツールで書けば経路ごと存在しない。

プロンプトに必ず入れる 4 つ:

1. **タスク** — explore なら答えるべき問い、chore / implement なら変更の内容と受け入れ条件
2. **範囲** — 見るべきファイル・ディレクトリを具体名で挙げる
3. **規律の無効化** — 下記の 2 行を逐語で入れる
4. **出力** — 最終メッセージは指定された JSON schema に適合する JSON だけにすること

規律の無効化はこの 2 行をそのまま入れる:

```text
Do not run an independent review with a new agent. The delegating side reviews afterwards.
Do not commit, stash, or create branches. Leave all changes in the working tree.
```

`~/.codex/AGENTS.md` は codex に独立レビューを求めるが、レビューは委譲した側が委譲後に行う。
内側で走らせると二重になり、委譲 1 本の所要時間と OpenAI 枠の消費が増える。commit を禁じるのは、
レビューゲートが commit の前に走るため、委譲先が commit すると Claude が差分を見る前に変更が
確定するからである。無効化が効かなかった場合は差分を見る手順で気づく — commit されていれば
`git log`、stash されていれば「変更が無いのに `changed_files` が非空」という食い違いに現れる。

### 3. 走査・実行・結果の取り出し・後始末

```sh
WORK=/tmp/xxxxxxxx   # 1 回目が返したパス
[ -s "$WORK/prompt.md" ] || exit 96   # パスの貼り間違い、または Write がまだ
[ -e "$WORK/run.log" ] && exit 96     # 使用済み = 既に codex を起動している
cp "$HOME/.claude/skills/codex-delegate/schema.json" "$WORK/schema.json" || exit 1
gitleaks dir "$WORK/prompt.md" --no-banner || exit 98   # 検出あり・実行不能とも委譲しない
trap 'rm -rf "$WORK"' EXIT            # ここから先だけが後始末の対象
MODE=read-only          # 委譲種別に応じて read-only か workspace-write
codex exec -s "$MODE" \
  --config approval_policy=never \
  --config features.memories=false \
  --config memories.generate_memories=false \
  --config memories.use_memories=false \
  --config sandbox_workspace_write.network_access=false \
  --config 'sandbox_workspace_write.writable_roots=[]' \
  --output-schema "$WORK/schema.json" \
  -o "$WORK/out.json" \
  - < "$WORK/prompt.md" > "$WORK/run.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -s "$WORK/out.json" ]; then
  cat "$WORK/out.json"
  exit 0
fi
tail -c 4000 "$WORK/run.log"
[ "$rc" -ne 0 ] || rc=97   # 終了コードは 0 だが JSON が返っていない
exit "$rc"
```

この形を変えない理由:

- **実行・結果の取り出し・後始末は同じ呼び出しに置く。** `trap ... EXIT` はそのシェルの終了で
  発火するため、後始末を別の呼び出しに分けると、次の呼び出しが読む前に `out.json` が消える。
  プロンプトの書き出しはこの制約の対象外で、先に分けてよい
- **codex の stdout と stderr はログファイルへ逃がす。** `-o` は最終メッセージを別に保存する
  だけで、リダイレクトしなければ codex の進捗出力全文が Claude の context に入り、削減の目的が
  失われる。同一の実行で比べると、stdout は進捗ログとトークン計を含む全文を返し、`-o` の
  ファイルは最終メッセージだけを持つ
- **失敗時にログを出す量はバイトで区切る。** 行数で区切ると、1 行が JSON や stack trace になる
  codex のログでは上限にならない。失敗経路は認証切れや利用枠切れで日常的に通るため、ここが
  唯一の無制限経路にならないようにする
- **`trap` は codex を起動する直前に張る。** 手前の中断(取り違え・skill 未配備・gitleaks の
  検出)はどれも codex を起動していないので、作業ディレクトリを残す。とくに secrets の検出は
  「直して再委譲する」ことが前提の経路であり、ここでプロンプトを消すと、直すたびに数 KB の
  プロンプトを書き直すことになる。残しておけば、同じディレクトリへ修正版を Write して 3 を
  再実行するだけで済む — `run.log` はまだ無いので使用済み判定にも掛からない
- **`trap ... EXIT` が発火するのは、codex が終わってシェルが終了するときだけである。** timeout
  ではプロセスが生き続けるため発火せず、停止では trap を走らせずに終了するため発火しない。
  停止経路では作業ディレクトリが残るが、作成先はシステムの一時領域であり、その掃除に委ねる
- **「使用済み」の目印は `run.log` で見る。** リダイレクトによって codex の起動と同時に作られる
  ため、正常終了・timeout・停止のどの経路でも「このディレクトリからは既に委譲を起動した」ことを
  表す。`out.json` は目印にならない — 存在するのは正常終了した委譲だけで、その経路では作業
  ディレクトリごと消えている
- **`-s` は必ず指定する。** `~/.codex/config.toml` の `sandbox_mode` は `workspace-write` で、
  `-s` を書かない `codex exec` は explore でも書き込みできる状態で走る。この既定値は codex 自身が
  config を書き換えることもあるため、呼び出し側で毎回固定し、指定のない呼び出し形を持たない
- **6 つの `--config` を毎回渡す。** `-s` が上書きするのは `sandbox_mode` だけで、`workspace-write`
  のときの書き込みルートとネットワーク到達性は config の `[sandbox_workspace_write]` 側に残る。
  承認方針も sandbox の外へ出る操作を認めるかを決めるキーなので同格に扱う。CLI で渡せば、
  config が書き換わっても次の実行には効かない
- **codex の記憶機能は委譲のあいだ切る。** `~/.codex/config.toml` は native memories を有効に
  しているため、既定では委譲ごとに codex が記憶を書き、過去の実行から抽出した内容を次の委譲へ
  持ち込む。これは差分に現れない入力であり、リポジトリを跨いで運ばれる。対話的な codex 利用では
  有効のままにするため、config 側は変えない
- **キーの綴りが正しいことと効いていることは別である。** 綴りは、空の `CODEX_HOME` を向けた
  `--strict-config` で検証する(通常の config には Windows 用の `computer_use` セクションがあり、
  strict を付けると起動前に落ちる)。strict を外した実行では存在しないキーが素通りするので、
  受理されたことは何の証拠にもならない。**`codex --version` が変わったら綴りと実挙動を再検証
  する** — キーが改名された場合の失敗は、エラーではなく沈黙として現れる
- **`--dangerously-bypass-approvals-and-sandbox` は使わない。** その形は codex-review skill が
  「他の用途で使わない」と限定しており、本 skill はその限定を変更しない。**`-s` が効かない環境
  では委譲しない** — `read-only` も `workspace-write` も担保にならず、explore が読むだけである
  保証も失われる。codex の Linux sandbox は unprivileged user namespace を要する bubblewrap に
  依存するため、多くのコンテナでは機能しない
- 作業ディレクトリは実行ごとに `mktemp -d` で作り、リポジトリ外に置く。固定名は前回の残骸を
  次の実行が読む取り違えを招き、リポジトリ内だと untracked としてレビュー対象に混入する
- **`${TMPDIR:-/tmp}` 配下に明示的に作り、以降は絶対パスで扱う。** 引数なしの `mktemp -d` は
  sandbox 内で `Operation not permitted` になる(`TMPDIR` 環境変数を見ず、許可されていない
  場所を使うため)。`/tmp` 直下を指定する形も同じ理由で通らない。フォールバックは `TMPDIR` が
  未設定の環境でファイルシステム直下に作らせないためのもので、sandbox 内では発動しない。
  `TMPDIR` の値は sandbox の有効・無効で変わるが、1 回目が返した絶対パスは 2 回目(sandbox 外)
  からも Write ツールからも同じ実体を指す
- **`schema.json` は skill 配下の実ファイルを `cp` する。** 出力契約の単一ソースを skill 側に
  置き、二重管理を避ける
- **gitleaks の走査は codex の起動より前に置き、非ゼロで中断する。** 非ゼロは「検出あり」と
  「gitleaks が動かない」の両方を含み、どちらも委譲しない条件になる
- **スニペットは `zsh -n` と `sh -n` の両方で検査する。** Bash tool が実行するのは zsh(5.9.2)
  であり bash ではない。`bash -n` は実行系と異なる言語を検査するため、通っても保証にならない

## 終了コード

| コード | 意味 | 対処 |
|---|---|---|
| 0 | 成功。stdout が `out.json` の全文 | `status` と `summary` を読む |
| 96 | 作業ディレクトリの取り違え(`prompt.md` が無い、または使用済み) | 1 回目が返したパスを貼り直す。使用済みなら 1 からやり直す |
| 97 | codex は正常終了したが JSON を返さなかった | この呼び出しの stdout に出ているログ末尾で切り分け、再委譲する |
| 98 | gitleaks で停止(検出あり、または gitleaks が動かない) | 検出をゼロにして 3 を再実行する(作業ディレクトリは残っている) |

その他の非ゼロは codex 自身の失敗(認証・利用枠・schema 不一致)で、ログ末尾(最大 4,000
バイト)が stdout に出る。

## 結果の受け取り

1. `out.json` の `status` と `summary` を読む。`done` 以外なら `blockers` を見て、再委譲するか
   Claude 側で引き取るかを決める
2. **`status` と `blockers` の整合は Claude が検査する。** schema では強制していない(構造化出力が
   JSON Schema の条件分岐 `if` / `then` を受理するかを確認していない)。`done` なのに `blockers` が
   非空、あるいは `done` 以外で空なら、結果を判断に使わない — `workspace-write` なら差分を見て
   Claude 側で引き取り、`read-only` なら再委譲する
3. `workspace-write` で実行した場合、`git status --short --untracked-files=all` と `git diff` で
   何が変わったかを見る。Claude 自身が書いたコードを見るときと同じ判断をする。**差分が空なのに
   `changed_files` が非空なら、commit か stash を疑って `git log --stat -3` と `git stash list` を
   見る** — 空の差分は「何も書かなかった」とも読めるため、この照合が無いと誤った安心を返す
4. ignored ファイルへの変更は `--untracked-files=all` に現れない。生成物・キャッシュ・`.env` の
   類が失われて困るリポジトリでは `--ignored` を付けた確認を併用する
5. CLAUDE.md のレビューゲート条件(5 ファイル以上・新規モジュール・公開 API・infra/config 変更、
   および commit 前)で判定して review-gate skill を通す。判定は変更の中身に対して行い、委譲の
   種別では行わない — 広範囲のリネームや横展開は、種別が chore でもゲート条件に該当する。委譲先が
   commit していた場合もゲートは通し、指摘があれば追加 commit ではなく `git reset --soft` で戻して
   から修正する

## 長時間の委譲

**timeout は委譲を終了させない。** Bash の timeout に達した呼び出しはプロセスを殺されず
background task へ移され、codex はそのまま走り続けて、完了時に通知が届く。出力は task の出力
ファイルへ蓄積されるため、JSON もログも失われない。timeout が決めるのは「foreground で待つ時間」
であって、委譲が終わる期限ではない。

- timeout に達したら **完了通知を待ってから差分を見る。** 待たずに見ると、読んでいる最中に codex が
  worktree を書き換える
- したがって `workspace-write` を foreground で実行しても、多重 writer を機構としては防げない。
  timeout 後は Claude が次の作業へ進めるようになるため、**書き込みが走っている間に次の委譲を
  始めないことは Claude が守る規律になる。** 開始前に、未完了の委譲 background task が無いことを
  確認する
- **プロセスの残存をコマンドで確かめない。** Claude Code の Bash sandbox 内では `pgrep` も `ps` も
  `operation not permitted` で失敗しながら終了コード 0 を返すため、外部のプロセス一覧に問い合わせる
  形の確認はすべて「該当なし」と答える。走っている委譲の有無は、未完了の background task が
  あるかどうかで見る
- 止める必要があるときは、その background task を停止する。停止は codex まで届く
- **timeout の指定は、結果をインラインで受け取るか通知で受け取るかの選択である。** 既定は
  `BASH_DEFAULT_TIMEOUT_MS` の 5 分、指定できる上限は `BASH_MAX_TIMEOUT_MS` の 20 分(いずれも
  `claude/settings.json` で定める)。結果を待つ必要がない委譲は、短い timeout で background へ
  流してよい。委譲を分ける基準は timeout ではなく差分の大きさで、1 回でレビューできる範囲に収める
- `read-only` の explore は background で実行してよい。書き込まないため、同時に複数走っても
  worktree は壊れない。JSON は background task の stdout に載る — `out.json` はシェルの終了とともに
  消えるため、ファイルとしては残らない

## 外部へ送られる範囲

組み立てた `prompt.md` を gitleaks で走査し、検出ゼロを確認してから codex を起動する。プロンプトを
走査対象にするのは、それが Claude の書いた内容を外部へ渡す唯一の経路だからである。secrets-scan
skill は uncommitted の変更(worktree と HEAD の差分 + untracked)を対象とするため、プロンプトへ
書き起こした内容・tracked ファイルからの引用・リポジトリ外の情報は検査されない。

codex が作業中に読んだファイルの内容とコマンド出力も送られる。プロンプトの走査はこれを覆わない。

**codex に与える可視範囲は Claude Code 自身のそれと同じで、委譲によって読まれ得る範囲は
広がらない。** 変わるのは送信先で、同じ内容が OpenAI へも渡る。これが成り立つのは、委譲のあいだ
codex の記憶機能を切っているからである — 有効なままだと、過去の委譲から抽出された内容が別の
リポジトリの委譲へ持ち込まれ、可視範囲が Claude より広くなる。ignored ファイル(`.env` の類)も
リポジトリ外のファイルも、両者とも読める。したがってこれは委譲の可否ではなく、そのリポジトリで
エージェントを使うかどうかの判断に属する。

リポジトリ全体への事前走査は委譲の条件にしない。エージェントのセッションログやプラグインキャッシュ
をリポジトリ配下に持つ構成では、この走査が数百件規模の検出を返して条件として機能せず、委譲を常に
止めることになる。

## Troubleshooting

### `Operation not permitted` で codex が起動しない

`claude/settings.json` の `sandbox.excludedCommands` に `codex:*` が無い。追加する(既存項目は
`git:*` / `gh:*` の形式)。`codex` と書くと exact マッチになり、引数付きの呼び出しには無言で
効かない。

### 認証・利用枠の失敗

ログ末尾に現れる。メッセージは認証方式によって異なる。interactive command は実行できないため、
ユーザーに `! codex login` を依頼する。枠切れは委譲そのものが使えないことを意味するため、Claude
側で引き取る。

### 96 で止まる

1 回目が返したパスを貼れているか、そのディレクトリで既に委譲を起動していないか(`run.log` の
有無)を見る。停止で残ったディレクトリは使い回せない。1 からやり直す。
