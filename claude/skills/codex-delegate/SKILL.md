---
name: codex-delegate
description: |
  作業を codex CLI へ委譲して Claude Code のトークン消費を抑えるアダプタ。
  探索(read-only)・定型作業・実装を codex exec で実行し、
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
6. `workspace-write` の委譲では、**未コミット変更と委譲先が触る範囲が重なるかを見て決める。**
   codex による上書きは差分に現れない — 既存の未コミット変更を書き直されると、その内容は
   worktree からも差分からも消え、元々そこに何があったかを復元する材料が残らない。事後の検査
   では捕まえられないので、重なりうるなら委譲する前に commit するか、委譲の範囲を変える。
   Claude 自身の編集は置換前の文字列の一致を要求するため他の編集を踏み潰さないが、codex に
   その保証はない — ここは「委譲した変更を自分の変更と同じに扱う」原則が実際に破れる箇所である

## 委譲種別

| 種別 | `-s` | 内容 |
|---|---|---|
| explore | `read-only` | 所在探索、原因調査、コードベースの読解 |
| chore | `workspace-write` | リネーム、同パターンの横展開、テスト追加 |
| implement | `workspace-write` | feature / bugfix |

委譲しないもの:

- 設計判断、およびユーザーとの対話が要る作業
- 個人記憶リポジトリへの書き込み。記憶は Claude Code 専用で、権限境界の管理主体を移さない
- レビューゲートそのもの。review-gate skill と codex-review skill の責務
- gitleaks がプロンプトから secrets を検出した作業。検出をゼロにできるまで委譲しない

**ネットワークはタスクごとに決める。ただし `workspace-write` でしか開けられない。** 既定は遮断
(`NET=false`)で、依存の取得・更新・lockfile の更新のようにネットワークが要るタスクだけ
`NET=true` にする。遮断したまま渡すと、その作業は `Could not resolve host` で完了しない。依存が
未インストールのリポジトリでは、AGENTS.md が求めるテストや build の実行自体がこれに当たる。
開けるとその委譲の送信先が OpenAI だけではなくなるので、必要なタスクに限る。

**`read-only` では `NET=true` が黙って効かない。** `sandbox_workspace_write.network_access` は
`workspace-write` のときだけ読まれるキーで、`read-only` の委譲は `NET` の値に関わらず
`Could not resolve host` になる。エラーにならず素通りするので、設定したつもりで遮断されたまま走る。
ネットワークが要る調査は explore では行えない — `workspace-write` の委譲にする(書き込まないタスク
でも `-s workspace-write` を選ぶ必要がある)。

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
case "${WORK##*/}" in (codex-delegate-??????) ;; (*) exit 96 ;; esac  # 1 回目が作った形でなければ触らない
[ -s "$WORK/prompt.md" ] || exit 96   # パスの貼り間違い、または Write がまだ
gitleaks dir "$WORK/prompt.md" --no-banner || exit 98   # 検出あり・実行不能とも委譲しない
mkdir "$WORK/run.claim" || exit 96    # 既に委譲を起動している、または目印を作れない
trap 'rm -rf "$WORK"' EXIT            # ここから先だけが後始末の対象
cp "$HOME/.claude/skills/codex-delegate/schema.json" "$WORK/schema.json" || exit 1
MODE=read-only          # 委譲種別に応じて read-only か workspace-write
NET=false               # ネットワークが要るタスクだけ true(workspace-write でのみ効く)
codex exec -s "$MODE" \
  --config approval_policy=never \
  --config features.memories=false \
  --config memories.generate_memories=false \
  --config memories.use_memories=false \
  --config "sandbox_workspace_write.network_access=$NET" \
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

スニペットの各要素がなぜその形・その位置なのかは
[ADR 20260818-155956](../../../docs/ADR/20260818-155956-run-codex-delegation-as-two-bash-calls.md)
にある。**変える前にそれを読む。** 順序・リダイレクト・目印の取り方・`--config` はいずれも、
実測した失敗を避けるために選ばれている。読まずに単純化すると、その失敗が戻る。

実行時に効く事実を 1 つだけここに置く。

- **`writable_roots=[]` でも `$TMPDIR` と `/tmp` は書き込み可能なままである。** 塞がるのは
  ホームディレクトリなど「workspace でも一時領域でもない場所」で、書き込みが workspace 内に
  限られるとは読まない。委譲の作業ディレクトリも一時領域にあるため、委譲先からは他の委譲の
  作業ディレクトリにも手が届く

## 終了コード

| コード | 意味 | 対処 |
|---|---|---|
| 0 | 成功。stdout が `out.json` の全文 | `status` と `summary` を読む |
| 96 | 作業ディレクトリの取り違え(名前の形が違う、`prompt.md` が無い、既に委譲を起動済み、目印を作れない) | 1 回目が返したパスを貼り直す。起動済みなら 1 からやり直す。`mkdir` のエラー文が出ていればそれが原因 |
| 97 | codex は正常終了したが JSON を返さなかった | この呼び出しの stdout に出ているログ末尾で切り分け、再委譲する |
| 98 | gitleaks で停止(検出あり、または gitleaks が動かない) | 検出をゼロにして 3 を再実行する(作業ディレクトリは残っている) |

その他の非ゼロは codex 自身の失敗(認証・利用枠・schema 不一致)で、ログ末尾(最大 4,000
バイト)が stdout に出る。

## 結果の受け取り

上限は schema が決める。自由記述 5 項目の文字数の合計が 22,600 文字で、これを超える出力を求めても
各項目がこの値で切られる。**受け取るデータ量はこれを上回る** — 上限が掛かるのはデコード後の文字数で、
実際に届くのは JSON にした形なので、UTF-8 のバイト数とエスケープが上に乗る(内訳は ADR)。厳密に
見たいときは `out.json` を `wc -c` で測る。これは context 増分の上限であって、委譲が消費する
トークン全体の上限ではない。

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
background task へ移され、codex はそのまま走り続けて、完了時に通知が届く。timeout が決めるのは
「foreground で待つ時間」であって、委譲が終わる期限ではない。

**受け取れるのは foreground と同じ範囲だけである。** background task の出力に載るのは、成功なら
JSON 全文、失敗ならログ末尾の 4,000 バイトで、`run.log` の全文はどちらの経路でも残らない
(正常終了で作業ディレクトリごと消える)。timeout にしたことで得られる情報が増えるわけではない。

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

### `invalid peer certificate: UnknownIssuer` で api.openai.com に繋がらない

`codex exec` をシェル関数・エイリアス・`sh -c` の中に入れて呼んでいる。`sandbox.excludedCommands` は
行のテキストではなく実行されるコマンドを見るため、包むと `codex` が照合から隠れ、その呼び出しは
Claude Code の Bash sandbox 内で走る。sandbox は TLS を傍受するので、codex 自身の API 接続が証明書の
発行者不明で切れる。**権限エラーではなく証明書エラーとして出る**ので、原因がメッセージに現れない。

`codex exec` は Bash 呼び出しの中で素のコマンドとして書く。包む形にしない。走っている呼び出しが
sandbox の内側かどうかは `echo "$TMPDIR"` で分かる — sandbox 内では `/tmp/claude-*`、外では
システムの一時領域を指す。

### `Operation not permitted` で codex が起動しない

`claude/settings.json` の `sandbox.excludedCommands` に `codex:*` が無い。追加する(既存項目は
`git:*` / `gh:*` の形式)。`codex` と書くと exact マッチになり、引数付きの呼び出しには無言で
効かない。

### 認証・利用枠の失敗

ログ末尾に現れる。メッセージは認証方式によって異なる。interactive command は実行できないため、
ユーザーに `! codex login` を依頼する。枠切れは委譲そのものが使えないことを意味するため、Claude
側で引き取る。

### 96 で止まる

1 回目が返したパスを貼れているか、そのディレクトリで既に委譲を起動していないか(`run.claim` の
有無)を見る。停止で残ったディレクトリは使い回せない。1 からやり直す。
