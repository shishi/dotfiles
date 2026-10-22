---
name: codex-delegate
description: |
  最上位の Claude Code から Codex CLI へ探索・定型変更・実装を委譲するときに使う。
  担当範囲と受入条件を渡し、JSON で結果を受け取る。受託側からの再委譲には使わない。
  独立レビューは codex-review / review-gate を使う。
---

# Codex Delegate

担当範囲と受入条件を Codex CLI に渡し、進捗ログとは別に上限付きの JSON を受け取る。
成果物の検証・独立レビュー・統合は呼出元の Claude が担当する。委譲先は AGENTS.md の
「作業の割当と利用枠」に従って選び、Claude 内の子と Codex CLI のどちらかを固定で優先しない。
codex の進捗出力はログファイルへ逃がし、失敗したときだけ末尾を読む。

委譲で入った変更は Claude 自身が書いた変更と同じものとして扱う。エージェントがファイルを
編集するという点で両者に差はなく、意図した変更かどうかの判断はどちらの場合もオーケストレータ
である Claude が差分を見て行う。したがって**委譲専用の検査機構は持たない** — 妥当性は差分の
確認と review-gate skill で見る。

**ただし codex 側の hook は委譲の中でも効く。** `~/.codex/hooks.json` の PreToolUse hook は委譲先の
Bash 呼び出しに対しても実行前に走り、拒否されたコマンドは実行されないまま
`Command blocked by PreToolUse hook: <理由>` が委譲先へ返る。`hooks.state` のエントリは `enabled` が
省略されていても走ることがあるため、省略を「無効」の印として読まない(既定値を定める codex 側の
記述が無く、省略からは状態を判定できない)。これは委譲専用の検査ではなく、codex を使う限り効く経路
である。

**hook が見るのは Bash に渡されたコマンド文字列であって、委譲先が書き込む内容ではない。** heredoc の
本文はその文字列に含まれるので検査されるが、`bash script.sh` のようにデータ経由で読み込まれる内容は
検査されない。ガードを通ったことは、その変更が妥当であることを意味しない。

## 前提条件

委譲判断はユーザーの依頼を受けた最上位の司令塔が行う。他のエージェントから担当作業を
受託した Claude は、この skill を起動しない。担当作業を実行して返し、別 CLI が必要なら
取得済みの根拠と必要な変更を司令塔へ返す。同じツール内の子を使う場合も、この立場を引き継ぐ。

1. **`~/.codex` が dotfiles の `codex/` を指していること**(`readlink ~/.codex`)。この link で
   委譲先が `codex/AGENTS.md` の規律(オーバーエンジニアリング禁止・最小検証・Git 安全性)と
   `codex/skills/` を持つ。**満たさないマシンでは chore と implement を委譲しない**(規律を持たない委譲先にコードを書かせることになる)。explore は読むだけなので
   この前提は不要
2. `codex` CLI が PATH にある(`command -v codex`)
3. `claude/settings.json` の `sandbox.excludedCommands` に `codex:*` があること。無いと codex の
   app-server 初期化が `Operation not permitted` で落ちる
4. `gitleaks` が動くこと。動かない環境では委譲しない
5. OpenAI 側の利用枠が残っていること。枯渇すると起動直後に失敗する(メッセージは認証方式に
   よって異なる)。委譲の負担は Claude と Codex の両方の消費で判断し、
   Claude 側の context 増分だけを節約の根拠にしない
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
- 個人記憶リポジトリへの書き込み。記憶は Claude Code / Codex 共有だが、
  呼び出し側が書き込みプロトコルと承認境界を保持する
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

### モデルと推論量を選ぶ

AGENTS.md の仕事内容による選択基準を使う。定型作業は `gpt-6-luna` / `high`、通常の
実装・調査は `gpt-6.1-sol` / `medium`(複雑なら `high`)、広い影響を伴う難しい作業は
`gpt-6-astra` / `high` を初期値にする。委譲種別だけで固定せず、検証対象のモデルが
指定されている場合はそのモデルを維持する。選んだ値を手順 3 の `DELEGATE_MODEL` と
`DELEGATE_EFFORT` に入れる。`agents.default_subagent_model` は子の既定値なので、
新しく起動する `codex exec` 本体のモデル指定の代わりにはならない。

選んだモデルが利用不能なら、司令塔が AGENTS.md の許容候補を試す。サービス全体の
認証・権限・利用枠の問題ではモデルを巡回しない。Codex の許容候補を使えなければ
Claude 内の子も候補にし、委譲の負担に見合わないか候補が使えなければ、司令塔自身が
担当作業と検証を引き取る。失敗した試行の変更がある場合は、先に差分と進捗を
確認し、完了部分を失ったり同じ操作を重ねたりしない。

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
2. **範囲** — 担当ファイル・維持する保証・基準 commit・受入コマンド・期限を具体化する。
   起動前の HEAD、stash、未コミット変更を確認し、他者変更を戻さないことを伝える
3. **受託側の役割** — 下記の 3 行を逐語で入れる
4. **出力** — 最終メッセージは指定された JSON schema に適合する JSON だけにすること

受託側の役割はこの 3 行をそのまま入れる:

```text
You are a delegated worker called by Claude Code. Do not delegate to another CLI, including Claude Code. Pass this restriction to any in-process subagents and return findings to the delegating coordinator if a different CLI is needed.
Do not run an independent review with a new agent. The delegating side reviews afterwards.
Do not commit, stash, or create branches. Leave all changes in the working tree.
```

検証コマンドと実結果は `findings` へ含めさせる。必要な作業や検証が残れば `partial` / `blocked`
とし、ツールの終了だけで `done` としない。schema の容量に証拠が収まらない場合は担当範囲を
分割し、根拠を捨てない。

`~/.codex/AGENTS.md` は codex に独立レビューを求めるが、レビューは委譲した側が委譲後に行う。
内側で走らせると二重になり、委譲 1 本の所要時間と OpenAI 枠の消費が増える。commit を禁じるのは、
レビューゲートが commit の前に走るため、委譲先が commit すると Claude が差分を見る前に変更が
確定するからである。無効化が効かなかった場合は差分を見る手順で気づく — commit されていれば
`git log`、stash されていれば「変更が無いのに `changed_files` が非空」という食い違いに現れる。

### 3. 走査・実行・結果の取り出し

以下は explore の例。chore / implement はコマンド先頭の `-s read-only` を
`-s workspace-write` へ直接置き換える。`codex exec` 行の許可 prefix に一致させるため、
この値は変数にしない。準備・記録など同じブロック内の別コマンドの許可は、それぞれ判定される。

```sh
WORK=/tmp/xxxxxxxx   # 1 回目が返したパス
case "${WORK##*/}" in (codex-delegate-??????) ;; (*) exit 96 ;; esac  # 1 回目が作った形でなければ触らない
[ -s "$WORK/prompt.md" ] || exit 96   # パスの貼り間違い、または Write がまだ
gitleaks dir "$WORK/prompt.md" --no-banner || exit 98   # 検出あり・実行不能とも委譲しない
mkdir "$WORK/run.claim" || exit 96    # 既に委譲を起動している、または目印を作れない
cp "$HOME/.claude/skills/codex-delegate/schema.json" "$WORK/schema.json" || exit 1
NET=false               # ネットワークが要るタスクだけ true(workspace-write でのみ効く)
DELEGATE_MODEL=gpt-6.1-sol # 仕事内容に応じて選んだモデル
DELEGATE_EFFORT=medium    # 仕事内容に応じて選んだ推論量
ROLE=explore             # explore / chore / implement
STARTED_AT=$(date +%s)
codex exec -s read-only --model "$DELEGATE_MODEL" \
  --config "model_reasoning_effort=$DELEGATE_EFFORT" \
  --config approval_policy=never \
  --config features.memories=false \
  --config memories.generate_memories=false \
  --config memories.use_memories=false \
  --config "sandbox_workspace_write.network_access=$NET" \
  --config 'sandbox_workspace_write.writable_roots=[]' \
  --output-schema "$WORK/schema.json" \
  --json \
  -o "$WORK/out.json" \
  - < "$WORK/prompt.md" > "$WORK/events.jsonl" 2> "$WORK/run.log"
rc=$?
FINISHED_AT=$(date +%s)
TASK_STATUS=$(jq -r '.status // "unknown"' "$WORK/out.json" 2>/dev/null) || TASK_STATUS=unknown
RUN_RECORD=$(bash "$HOME/.agent-shared/bin/agent-run-record.sh" codex "$DELEGATE_MODEL" "$DELEGATE_EFFORT" "$ROLE" "$STARTED_AT" "$rc" "$WORK/events.jsonl" "$TASK_STATUS" "$FINISHED_AT") || { echo "記録保存失敗。結果は $WORK に保全" >&2; exit 95; }
printf 'Run record: %s\n' "$RUN_RECORD" >&2
printf 'Run artifacts: %s\n' "$WORK" >&2
if [ "$rc" -eq 0 ] && [ -s "$WORK/out.json" ] && jq -e 'type == "object" and (.status == "done" or .status == "partial" or .status == "blocked")' "$WORK/out.json" >/dev/null; then
  cat "$WORK/out.json"
  exit 0
fi
tail -c 4000 "$WORK/run.log"
tail -c 4000 "$WORK/events.jsonl"
[ "$rc" -ne 0 ] || rc=97   # 終了コードは 0 だが JSON が返っていない
exit "$rc"
```

スニペットの順序・リダイレクト・目印の取り方・`--config` はいずれも、実測した失敗を
避けるために選ばれている。根拠を確認せずに単純化すると、その失敗が戻る。

実行時に効く事実を 1 つだけここに置く。

- **`writable_roots=[]` でも `$TMPDIR` と `/tmp` は書き込み可能なままである。** 塞がるのは
  ホームディレクトリなど「workspace でも一時領域でもない場所」で、書き込みが workspace 内に
  限られるとは読まない。委譲の作業ディレクトリも一時領域にあるため、委譲先からは他の委譲の
  作業ディレクトリにも手が届く

## 終了コード

| コード | 意味 | 対処 |
|---|---|---|
| 0 | JSON を受領。作業完了は未判定 | `status`、検証結果と実物を照合 |
| 95 | 実績記録の保存に失敗。作業結果とログは保全 | 出力済みの場所から記録だけを回復し、委譲を再実行しない |
| 96 | パス・入力・起動目印の確認で停止 | 既存の実行 handle、`run.claim` とエラーを確認。起動済みなら新規実行しない |
| 97 | codex は正常終了したが利用可能な JSON がない | 保全したログ・イベント・残った変更を調べ、司令塔が引取りや再試行を判断 |
| 98 | gitleaks で停止(検出あり、または gitleaks が動かない) | 検出をゼロにして 3 を再実行する(作業ディレクトリは残っている) |
| 143 | SIGTERM で終了した | timeout 等の原因と旧実行の停止、途中の変更・結果を確認してから引取りを判断 |

その他の非ゼロは codex 自身の失敗(認証・利用枠・schema 不一致)で、stderr とイベントの
末尾を各最大 4,000 バイト返す。`--json` はイベント側だけを変え、`-o` の結果 JSON は維持する。
記録は司令塔が private state へ書ける経路で実行し、委譲先の書込許可は広げない。
実績記録のパスはレビューまで保持し、検証結果と採用指摘を追記する。

## 結果の受け取り

上限は schema が決める。自由記述 5 項目の文字数の合計が 22,600 文字で、これを超える出力を求めても
各項目がこの値で切られる。**受け取るデータ量はこれを上回る** — 上限が掛かるのはデコード後の文字数で、
実際に届くのは JSON にした形なので、UTF-8 のバイト数とエスケープが上に乗る(内訳は ADR)。厳密に
見たいときは `out.json` を `wc -c` で測る。これは context 増分の上限であって、委譲が消費する
トークン全体の上限ではない。

1. `out.json` の `status` と `summary` を読む。終了コード 0 は JSON 受領であり、作業完了の証明ではない。
   イベントの失敗や hook・権限の拒否があれば、代替操作の証拠または未完了理由を確認する。
   取得できる実モデルの metadata と指定値を照合し、取得できなければ実モデル未確認とする。
   `done` 以外なら `blockers` と残った作業を見て、司令塔が引取りや再試行を判断する
2. **`status` と `blockers` の整合は Claude が検査する。** schema では強制していない(構造化出力が
   JSON Schema の条件分岐 `if` / `then` を受理するかを確認していない)。`done` なのに `blockers` が
   非空、あるいは `done` 以外で空なら、不整合を未解決として保持し、実物と検証結果から
   司令塔が残件を確かめる。JSON を取り直すためだけに同じ作業を再実行しない
3. `workspace-write` で実行した場合、開始時の HEAD・stash と現在値、
   `git status --short --untracked-files=all`、`git diff HEAD` を照合する。
   `changed_files` との不一致、対象外変更、他者変更の消失を確認する。**差分が空なのに
   `changed_files` が非空なら、commit か stash を疑って `git log --stat -3` と `git stash list` を
   見る** — 空の差分は「何も書かなかった」とも読めるため、この照合が無いと誤った安心を返す
4. ignored ファイルへの変更は `--untracked-files=all` に現れない。生成物・キャッシュ・`.env` の
   類が失われて困るリポジトリでは `--ignored` を付けた確認を併用する
5. AGENTS.md と review-gate skill に従い、委譲した成果物も原則としてゲートを通す。
   省略は AGENTS.md の条件をすべて満たす場合だけとし、委譲の種別では判断しない。
   委譲先が commit / stash / branch 変更をしていたら、その状態と成果を保全し、開始 commit
   からの変更全体を確認する。自動で reset や履歴の書換えをせず、既存の承認範囲で修正・統合する。
   履歴変更が必要なら AGENTS.md の明示承認条件に従う。explore でも対象が不変か確認する
6. 結果・ログ・検証と実績記録を保全し、レビューに必要な証拠を回収してから、自分が作った
   `WORK` だけを削除する。失敗や記録保存失敗の切り分けが残る間は削除しない

## 長時間の委譲

長い委譲は起動元の timeout と background 実行の仕様を確認し、必要なら最初から background
で始める。実行 handle と `WORK` を保持し、同じ実行を追跡する。観測の timeout だけでは
CLI の終了・最終 JSON の欠落・子プロセスの停止を断定しない。

- `workspace-write` の writer が動いている間は、同じ範囲へ次の writer を起動しない。
  停止が必要ならその task の停止手段を使い、停止結果と途中の変更を確認する。
- プロセス一覧を取得できない環境では、空の出力を停止の証拠にせず、実行 handle の状態を確認する。
  旧 writer の停止が確認できない間は、同じ範囲への引取り書込みも始めない。
- SIGTERM 等で終了した場合も `WORK` の最終 JSON・途中のログ・イベントを調べる。
  143 は終了理由の一つであり、成果がないことや再実行してよいことを意味しない。
- 再試行は失敗原因と外部状態・新情報を確認し、AGENTS.md の許容候補・再試行規則に従って
  司令塔が判断する。adapter が自動で再起動しない。完了部分を保全し、同じ操作を重ねない。
- background 実行でも出力先は同じ。結果の受領・実物照合・証拠の回収を終えるまでログを残す。
  レビュー可能な範囲と実行期限を基準に分割し、必要な対象や検証を捨てない。

## 外部へ送られる範囲

AGENTS.md の「相互委譲の事前承認」に従い、OpenAI の公式サービスへの対象範囲内の送信は
事前承認済みとする。承認要求には具体的な入力・追加取得範囲、接続先の確認結果と検査結果を示す。

組み立てた `prompt.md` を gitleaks で走査し、検出ゼロを確認してから codex を起動する。プロンプトを
走査対象にするのは、それが Claude の書いた内容を外部へ渡す唯一の経路だからである。secrets-scan
skill は uncommitted の変更(worktree と HEAD の差分 + untracked)を対象とするため、プロンプトへ
書き起こした内容・tracked ファイルからの引用・リポジトリ外の情報は検査されない。

codex が作業中に読んだファイルの内容とコマンド出力も送られる。プロンプトの走査はこれを覆わない。

**codex に与える可視範囲は Claude Code 自身のそれと同じで、委譲によって読まれ得る範囲は
広がらない。** 変わるのは送信先で、同じ内容が OpenAI へも渡る。共有の `agent-memory` は
両エージェントに注入され、Codex native Memories は global config と委譲ごとの 3 設定で
無効化する。native Memories を有効にすると、過去の委譲から抽出された内容が別の
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

実行経路、sandbox、hook の拒否を区別し、既存設定の実効値とログを確認する。
`sandbox.excludedCommands` の不足を原因候補にできるが、エラーだけで除外追加を指示しない。
deny・sandbox を無断で弱めず、許可範囲内の経路か Claude 内の子・司令塔への引取りを選ぶ。
追加権限が必要な場合だけ、原因と最小限の権限を示して通常の承認経路へ戻す。

### 認証・利用枠の失敗

ログ末尾を読み、モデル単位の利用枠不足か、認証・サービス全体の問題かを区別する。
モデル単位なら許容候補で再実行し、共通の問題なら上の代替手順で Claude 内の子か司令塔へ移す。
代替で要件を満たせるなら完遂し、元の CLI の再認証を待たない。本人へ依頼するのは、
代替でも満たせない認証・権限が作業の完了に必要な場合だけとする。

### 96 で止まる

1 回目が返したパス、入力の存在、`run.claim` の有無と実行 handle を確認する。
目印があるだけでは実行中・停止済みのどちらとも断定しない。既存の結果と writer の停止を
確認して司令塔が再試行を選んだ場合だけ、新しい作業ディレクトリを用意する。

CLI の入出力は [OpenAI の非対話実行](https://learn.chatgpt.com/docs/non-interactive-mode)
および使用中の `codex exec --help` で確認する。
