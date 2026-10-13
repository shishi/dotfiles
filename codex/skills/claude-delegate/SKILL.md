---
name: claude-delegate
description: Codex の最上位司令塔から Claude Code へ探索・定型変更・実装を委譲するときに使う。受託側からの再委譲には使わない。独立レビューは claude-review / review-gate を使う。
---

# Claude への作業委譲

`codex-delegate` の逆方向の入口です。担当範囲と受入条件を渡し、進捗ログとは別に
上限付きの JSON を受け取ります。成果物の検証・独立レビュー・統合は呼出元が担当します。

## 担当と権限

送信の許可と承認要求の組成は AGENTS.md の「相互委譲の事前承認」に従います。
Anthropic の公式サービスへの対象範囲内の送信は事前承認済みです。プロンプトだけでなく、
CLI が読む共通指示・関連記憶・対象ファイル・コマンド出力も送信範囲として扱います。

最上位の Codex だけが起動します。AGENTS.md の担当選択とモデル代替規則に従い、
必要なツール・既存文脈・引継ぎ量・レビュー余力で選びます。工程名だけで往復させません。
通常は Sonnet / medium、複雑な調査・実装は Opus / medium〜high、
広い影響や矛盾の判断は Fable / high を初期値にします。

| 種別 | ツール | 許可 |
|---|---|---|
| explore | Read,Grep,Glob | 読み取りのみ。シェルが必要な検証は司令塔が行う |
| chore / implement | Read,Grep,Glob,Edit,Write と必要な場合だけ Bash | 対象の `Edit(./path)` と検証用 `Bash(command)` を事前許可 |

- `claude`、`jq`、`gitleaks` が必要です。書込委譲では `readlink ~/.claude` が dotfiles の
  `claude/` を指し、`CLAUDE.md` と skills が現在の規則を持つことを確認します。
  この前提を満たさない環境では chore / implement を渡しません。設計の最終判断・ユーザー対話・個人記憶の
  更新・レビューゲートは渡しません。独立した設計調査は explore として渡せます。
- 対象の repo / タスク用 worktree を cwd にします。並列 writer は worktree を分けます。
  同じ範囲の未コミット変更がある場合は、その成果を保全するか範囲を分けてから渡します。
- 外側の実行環境は Claude 自身の認証通信とセッション保存を許可する必要があります。
  受託側の Bash が使うネットワーク・書込範囲とは別です。既存の sandbox・hook・deny を
  維持し、必要な許可は司令塔が扱います。`--bare` や権限 bypass は使いません。
- `--allowedTools` は既存許可への追加です。既存の広い許可を狭める OS の隔離境界とは
  扱いません。書込時は下の `--disallowedTools` で通常の Git 書込・push コマンドも拒否し、
  再委譲用の `codex` 呼出しも拒否します。共有設定の allow をそのまま適用しません。コマンド形式の照合は間接実行全体を隔離する
  仕組みではないため、既存 hook と役割指示・実物照合も維持します。
- Agent と MCP は既定で渡しません。同じ CLI 内の子が必要なら司令塔が明示許可し、
  受託中・別 CLI 再委譲禁止をその子にも引き継がせます。

## 入力を作る

```sh
WORK=$(mktemp -d "${TMPDIR:-/tmp}/claude-delegate-XXXXXX") && chmod 700 "$WORK" && echo "$WORK"
```

返されたディレクトリの `prompt.md` をファイル編集ツールで作ります。本文をシェル文字列へ
埋め込みません。元の要件、担当ファイル、維持する保証、受入コマンド、基準 commit、期限を
含めます。会話全文や無関係な記憶はコピーしません。次の役割文を添えます。

```text
You are a delegated worker called by Codex. Work only on the supplied scope.
Do not delegate to another CLI, including Codex. Pass this restriction to any in-process subagents. Return evidence and any required reassignment to the delegating coordinator.
Do not run an independent review, commit, stash, or create branches. The coordinator verifies and reviews your work. Leave changes in the working tree.
Return the supplied JSON schema. Report partial or blocked when required work or verification is incomplete; do not claim done merely because a tool ran.
```

書込時は既存の検証手順も具体名で渡します。schema の `findings` に検証コマンドと実結果を
含めさせます。結果が schema の容量に収まらない場合は対象を分割し、必要な根拠を捨てません。

## 実行と受領

次は explore の実行例です。`WORK` は作成済みの実パスに置き換え、モデルと推論量を選びます。
各呼出しは一度だけ起動し、実行 handle を保持します。必要な通信を許可した経路で実行します。

```sh
WORK=/tmp/claude-delegate-XXXXXX
DELEGATE_MODEL=sonnet
DELEGATE_EFFORT=medium
ROLE=explore
gitleaks dir "$WORK/prompt.md" --no-banner || exit 98
mkdir "$WORK/run.claim" || exit 96
SCHEMA=$(jq -c . "$HOME/.codex/skills/claude-delegate/schema.json") || exit 1
STARTED_AT=$(date +%s)
claude -p --model "$DELEGATE_MODEL" --effort "$DELEGATE_EFFORT" --permission-mode dontAsk --tools Read,Grep,Glob --strict-mcp-config --json-schema "$SCHEMA" --output-format json < "$WORK/prompt.md" > "$WORK/result.json" 2> "$WORK/run.log"
rc=$?
FINISHED_AT=$(date +%s)
RUN_RECORD=$(bash "$HOME/.agent-shared/bin/agent-run-record.sh" claude "$DELEGATE_MODEL" "$DELEGATE_EFFORT" "$ROLE" "$STARTED_AT" "$rc" "$WORK/result.json" "" "$FINISHED_AT") || exit 95
printf 'Run record: %s\n' "$RUN_RECORD" >&2
[ "$rc" -eq 0 ] || { tail -c 4000 "$WORK/run.log"; exit "$rc"; }
jq -e '.is_error == false and .subtype == "success" and (.structured_output | type == "object")' "$WORK/result.json" >/dev/null || exit 97
jq '.structured_output' "$WORK/result.json"
```

chore / implement は `ROLE` を変更し、上の Claude コマンドのツールと許可を対象に合わせます。
たとえば `src/` の編集と `python3 verify.py` による検証を承認済みなら、次の形です。
`Edit` のパス許可は Write にも適用されます。Bash 不要ならツールと許可から外します。

```sh
claude -p --model "$DELEGATE_MODEL" --effort "$DELEGATE_EFFORT" --permission-mode dontAsk --tools Read,Grep,Glob,Edit,Write,Bash --allowedTools 'Edit(./src/**)' 'Bash(python3 verify.py)' --disallowedTools 'Bash(codex:*)' 'Bash(git commit:*)' 'Bash(git push:*)' 'Bash(git stash:*)' 'Bash(git checkout:*)' 'Bash(git switch:*)' 'Bash(git merge:*)' 'Bash(git rebase:*)' 'Bash(git pull:*)' 'Bash(git cherry-pick:*)' 'Bash(git branch:*)' --strict-mcp-config --json-schema "$SCHEMA" --output-format json < "$WORK/prompt.md" > "$WORK/result.json" 2> "$WORK/run.log"
```

- 正常終了と JSON 受領は作業完了の証明ではありません。`status`、`blockers`、検証結果を
  読み、`done` なら blockers が空、未完了なら理由があることを確認します。
  `permission_denials` に必要な操作の拒否があれば、完了した代替操作の証拠か未完了理由が必要です。
- `modelUsage` で実モデルを確認します。別モデルに替わっていれば指定条件と照合します。
- 書込時は開始 commit と現在の HEAD、stash、`git status --short --untracked-files=all`、
  `git diff HEAD` を確認します。`changed_files` と一致しない変更、対象外変更、
  生成物など必要な ignored ファイルも照合します。探索では対象が不変であることを確認します。
- 結果の引用先と検証を確認し、review-gate に渡します。レビューは内側で重ねません。
- 記録は司令塔が private state へ書ける経路で行います。保存失敗なら元の出力を保全して
  記録だけを再実行し、委譲作業を重ねません。記録のパスはレビューまで保持します。
- 観測の timeout だけで再起動しません。実失敗時はログと残った変更を確認し、AGENTS.md の
  許容候補・再試行規則で引取りを判断します。停止を確認するまで新しい writer を起動しません。
- 結果と記録を保全した後、自分が作った `WORK` だけを削除します。失敗時は切り分けに必要な
  `result.json` とログを回収してから片付けます。

CLI の構造化出力と権限は [公式の非対話実行](https://code.claude.com/docs/en/headless) と
[権限規則](https://code.claude.com/docs/en/permissions) に従います。

| 終了コード | 意味 |
|---|---|
| 0 | 結果を受領。作業完了は `status` と実物で判断 |
| 95 | 記録保存失敗。結果を保全して記録だけを回復 |
| 96 | 同じ `WORK` で起動済み、または起動目印の作成失敗 |
| 97 | 正常終了したが利用可能な構造化結果が無い |
| 98 | 秘密情報検査で停止。検出ありと検査不能をともに含む |

その他の非ゼロは CLI 自体の失敗です。実行期限でプロセスを停止した場合、途中の変更は
残っていても最終 JSON が無いことがあります。停止と実物を確認してから引き取ります。
