# compact 対策 3点セット 設計書

日付: 2026-07-05
状態: レビュー指摘反映済み(実装前)

## 背景と問題

Claude Code の compact(手動 `/compact` / 自動)は会話履歴を LLM 要約に置き換える。
要約は「過去の作業記録」であり「次の行動指示」ではないため、圧縮後のエージェントは
次の誤認識を起こしやすい。

- 却下済みの案を再提案・再実行する(却下理由が要約から落ちる)
- 検証フェーズを飛ばして破壊的操作に入る(フェーズ情報が落ちる)
- plan mode や委譲中タスクなどのセッション状態を失う

この環境は `autoCompactEnabled: false` + `DISABLE_MICROCOMPACT=1` のため自動 compact は
走らないが、代わりに context 上限へ到達すると手詰まりになる。よって「上限前に気付いて
手動 compact へ誘導する」仕組みと「圧縮前後で判断構造を保全する」仕組みの両方が要る。

参考: u1 氏の記事「claude code の compact の問題点と対策」の 3 コンポーネント構成
(compact-prep skill / 圧縮後復旧 hook / 60% 通知)を shishi 環境向けに再設計した。

## 全体アーキテクチャ

```
[通常運転]
statusline.sh ──(used_percentage >= 80)──> warn marker 書き込み
      │ 次のユーザープロンプト
      ▼
UserPromptSubmit hook (reminder) ──> additionalContext で /compact-prep を提案 (one-shot)
      │ ユーザーが /compact-prep
      ▼
compact-prep skill ──> ~/.claude/compact-state/<session_id>.md に判断構造を保存
      │ ユーザーが /compact
      ▼
SessionStart hook (matcher: compact) ──> state file の再読指示を additionalContext で注入
                                         + warn/warned marker 掃除
```

## 検証済みの事実(2026-07-05 時点)

設計はすべて以下の裏取り済み事実に基づく。

1. `SessionStart` hook は matcher `compact` で圧縮直後に発火し、
   `hookSpecificOutput.additionalContext` を返せる(公式 docs 確認済み)。
   記事の「PostCompact は additionalContext 不可 → UserPromptSubmit で 2 段リレー」は
   この経路で 1 段に短縮できる。
2. `UserPromptSubmit` hook は additionalContext を返せる。stdin JSON に `session_id` を含む。
3. statusline の stdin JSON は `session_id` と `context_window.used_percentage` を含む
   (公式 docs 確認済み。実機の値は実装時にスモークで確認する)。
4. Bash tool の環境変数に `CLAUDE_CODE_SESSION_ID` が存在する(実機確認済み)。
   skill はこれで session_id を取得する。記事の `get-session-id.sh` は不要。
5. Windows では hook のコマンドパスにスラッシュ区切りを使う(バックスラッシュは
   サイレントに失敗する)。既存 hook と同じ `bash ~/.claude/hooks/<name>.sh` 形式を踏襲。
6. この環境の jq は stdout に CRLF を出力する(実機確認済み:
   `printf '{"session_id":"abc-123"}' | jq -r '.session_id' | od -c` → `a b c - 1 2 3 \r \n`)。
   `$(jq -r ...)` は末尾 `\n` しか除去しないため、変数に `\r` が残り
   `<sid>\r.md` のような不可視の別ファイル名になる。937ef4a で同種のバグを修正済み。
   **全スクリプトで `jq -r` の出力は必ず `tr -d '\r'` を通すこと。**

### 実装時に検証する項目

- statusline stdin の `context_window.used_percentage` の実値(事実 3 のスモーク)
- session_id が `/compact` `/clear` の前後で連続しているか
  (marker 掃除と state file 参照の前提。非連続なら matcher 別の掃除設計を見直す)

## 記事からの変更点と理由

| # | 変更 | 理由 |
|---|------|------|
| 1 | PostCompact 2 段リレー → `SessionStart(compact)` 1 段 | 上記事実 1。marker(claude-compacted)が丸ごと不要になり、注入も次プロンプト待ちでなく即時 |
| 2 | session_id 取得を `$CLAUDE_CODE_SESSION_ID` に | 上記事実 4。ハードゲート(空なら停止)は維持 |
| 3 | 閾値 60% → 80%、公式 `used_percentage` を使用 | この環境の context は 200K 前提。記事も 200K なら 80% 台を推奨。公式フィールドなら context サイズ非依存 |
| 4 | state 置き場を `/tmp` → `~/.claude/compact-state/` | Git Bash では hook 実行時と Bash tool 実行時で TMPDIR 解決がズレうる。symlink 先の固定パスなら両方から同一に見える |
| 5 | Worker Topology(tmux-bridge)→ Delegated Work に一般化 | tmux-bridge 未使用。agent teams / background task の委譲状況を記録する欄として残す |

## コンポーネント詳細

### 1. compact-prep skill(新規: `claude/skills/compact-prep/SKILL.md`)

`/compact-prep` で起動する personal skill。圧縮要約に載りにくい「判断構造」と
「セッション状態」を state file に保存する。

- session_id は `echo "$CLAUDE_CODE_SESSION_ID"` で取得。
  **Hard gate**: 空なら state file を作らず「準備未完了」と報告して停止。
- 保存先: `~/.claude/compact-state/<session_id>.md`(書き込み前に `mkdir -p`)
- `# Compact Prep State` 見出しの直下に `Prepared: <ISO 8601 タイムスタンプ>` の
  メタデータ行を書く(復旧時の鮮度判定に使う)。
- 見出しを次の順で固定(**Forcing function**: 保存後に読み返して全見出しの存在を確認):
  `# Compact Prep State` / `## Active Plan` / `## Current Phase` / `## TaskList Summary` /
  `## Session Decisions`(採用案・却下案・却下理由)/ `## Constraints and Blockers` /
  `## Delegated Work`(委譲中の agent・background task)/ `## Editing Files` /
  `## Recovery Notes`(圧縮後の自分への手紙)
- `allowed-tools` で副作用を絞る(Read / Write / 最小限の Bash)。
- 完了レシート: state file パス、保存項目、未確認項目、`/compact` 実行案内。

### 2. 圧縮後復旧 hook(新規: `claude/hooks/session-start-compaction-recovery.sh`)

- 登録: `SessionStart` に 3 エントリ。**どの matcher で発火したかは第1引数で渡す**
  (stdin の `source` フィールドに依存しない):
  - matcher `compact` → `bash <script> recover`
  - matcher `clear` → `bash <script> cleanup`(clear 後に古い cooldown が通知を殺すのを防ぐ)
  - matcher `startup` → `bash <script> cleanup`
- 共通処理(`cleanup` / `recover` 両モード):
  - stdin JSON から `session_id` を取得(`jq -r` + `tr -d '\r'`。空なら即 exit 0)
  - 当該 sid の warn / warned marker を削除(通知 cooldown のリセット)
  - TTL 掃除: `find ~/.claude/compact-state -type f -mtime +30 -delete 2>/dev/null || true`
    (state file・orphan marker の無限蓄積を防ぐ。テキストのみで容量は軽微なため
    30 日と長めに取り、過去セッションの振り返り材料としても残す)
- `recover` モードのみ、additionalContext で注入:
  - state file `~/.claude/compact-state/<sid>.md` が存在すれば: Read して作業状態を
    復元せよ(Session Decisions と Recovery Notes を重視)。**先頭の `Prepared:`
    タイムスタンプを確認し、直近の /compact-prep より古い(= 前回圧縮より前の)
    state に見える場合は TaskList / plan を正としてその旨を報告せよ**
  - state file が無くても: TaskList で現在のタスクを確認せよ /
    圧縮サマリーの next step は仮説として扱い、plan / rules を正とせよ /
    plan mode が解除されていたらユーザーに再突入を確認せよ
- **fail-open**: いかなる場合も exit 0。

### 3. 閾値通知

#### 3a. statusline 変更(`claude/statusline.sh`)

- % 計算を stdin の `context_window.used_percentage` 優先に変更。
- fallback(フィールドが取れない場合): 現行の transcript 自前計算を使うが、
  **分母は 819200(1M の 80%)ではなく 200000(200K context の実サイズ)に変更**する。
  現行値のままだと実際の使用率の約 1/5 に過小表示され、閾値 80 が実質 64% 相当の
  別スケールになるため。fallback 値でも warn marker は同じ閾値 80 で書く。
- 色分け(70%/90%)は「実使用率」基準としてそのまま維持(分母修正で意味が正しくなる)。
- `使用率 >= 80` かつ warned marker が無ければ
  `~/.claude/compact-state/warn/<session_id>` に使用率を書く(書き込み前に `mkdir -p`)。
  session_id は stdin JSON から `jq -r` + `tr -d '\r'` で取得する。
- 表示フォーマットは現行を維持。

#### 3b. reminder hook(新規: `claude/hooks/userpromptsubmit-compact-reminder.sh`)

- 登録: `UserPromptSubmit`(matcher なし、毎ターン発火)。
- session_id は stdin JSON から `jq -r` + `tr -d '\r'` で取得
  (statusline が warn marker 名に使った sid と一致させるため必須)。
- warn marker が無ければ `test -f` 1 回で即 exit 0(通常ターンのコストほぼゼロ)。
- warn marker があれば、**この順で**:
  1. `~/.claude/compact-state/warned/<session_id>` を先に作成(二重通知防止。
     warn 削除より先に作ることで、並行して走る statusline が「warn なし・warned なし」の
     瞬間を見て warn を再作成する再通知レースを塞ぐ)
  2. marker から使用率を読み、warn marker を削除(one-shot)
  3. additionalContext で注入: 「context 使用率が N% に達した。作業の区切りで
     `/compact-prep` → `/compact` をユーザーに提案せよ。scope 縮小や別セッション化でなく
     圧縮前 state 保存で対処せよ」
- **fail-open**: 常に exit 0。

### marker / state ファイル一覧

| パス | 書く人 | 消す人 | 意味 |
|------|--------|--------|------|
| `compact-state/<sid>.md` | compact-prep skill | TTL 掃除(30日超で削除。同一 sid の再 prep は上書き) | 圧縮前の判断構造 |
| `compact-state/warn/<sid>` | statusline | reminder hook(通知時)/ recovery hook(compact/clear/startup 時の掃除) | 通知したい |
| `compact-state/warned/<sid>` | reminder hook | recovery hook(compact/clear/startup 時)/ TTL 掃除 | 通知済み(cooldown) |

- 全 writer は書き込み前に `mkdir -p` を実行する(fail-open)。
- hook / statusline は保存先ディレクトリを `${COMPACT_STATE_DIR:-$HOME/.claude/compact-state}`
  で解決する(テストを本番ディレクトリから隔離するための env 上書き口)。

### 4. settings.json 変更

既存の `PreToolUse`(git-push-guard)はそのまま。以下を追加:

```json
"SessionStart": [
  { "matcher": "compact", "hooks": [
    { "type": "command", "command": "bash ~/.claude/hooks/session-start-compaction-recovery.sh recover", "timeout": 10 }
  ]},
  { "matcher": "clear", "hooks": [
    { "type": "command", "command": "bash ~/.claude/hooks/session-start-compaction-recovery.sh cleanup", "timeout": 10 }
  ]},
  { "matcher": "startup", "hooks": [
    { "type": "command", "command": "bash ~/.claude/hooks/session-start-compaction-recovery.sh cleanup", "timeout": 10 }
  ]}
],
"UserPromptSubmit": [
  { "hooks": [
    { "type": "command", "command": "bash ~/.claude/hooks/userpromptsubmit-compact-reminder.sh", "timeout": 10 }
  ]}
]
```

### 5. .gitignore 変更

`/claude/*` ホワイトリスト方式のため:

- `!/claude/hooks/` と `!/claude/hooks/**` を追加(新規 hook を track するため。
  既存 git-push-guard.sh は過去に force-add されており、今後は通常 add で揃う)
- `claude/compact-state/` は `/claude/*` により自動的に ignore される(追記不要)

## エラー処理方針

- 全 hook は fail-open(常に exit 0)。hook の破損で Claude Code 本体を止めない。
- session_id が取れない場合: hook は即 exit 0、skill はハードゲートで停止・報告。
- jq 不在・JSON 破損時も exit 0(`2>/dev/null` + デフォルト値)。
- **CRLF 対策(検証済みの事実 6)**: `jq -r` の出力は必ず `tr -d '\r'` を通す。
  怠ると sid に `\r` が残り、state file / marker の参照が不可視に空振りする。
  fail-open 設計では症状が出ないため、スモークテストでファイル名の CR 混入を検査する。
- ディレクトリ不在: 各 writer が `mkdir -p` するため起きない(失敗時も exit 0)。

## テスト計画

スモークテストは `COMPACT_STATE_DIR` を一時ディレクトリに向けて実行し、
本番の `~/.claude/compact-state/` を汚さない。

1. **hook 単体スモーク**: 偽の stdin JSON を食わせて出力 JSON と marker の増減を確認。
   例: `echo '{"session_id":"test-sid"}' | bash claude/hooks/userpromptsubmit-compact-reminder.sh`
   - warn marker あり → additionalContext JSON が出て warned 作成 → warn 消滅(この順)
   - warn marker なし → 出力なしで exit 0
   - recovery hook: `recover` で state file あり/なし両方の注入内容と marker 削除、
     `cleanup` で注入なし・marker 削除のみ、TTL 掃除(古いファイルの削除)
   - **CR 検査**: 各スクリプト実行後、`find "$COMPACT_STATE_DIR" -name $'*\r*'` が
     空であること(検証済みの事実 6 の回帰テスト)
2. **statusline スモーク**: `used_percentage` 入り JSON で % 表示と warn marker 作成、
   フィールド欠落 JSON で fallback 計算(分母 200000)と閾値 80 での marker 作成を確認。
3. **実セッション通し**: 実セッションで `/compact-prep` → state file 生成
   (`Prepared:` 行付き)を確認 → `/compact` → 直後のターンに復旧指示が
   効いているか(state file 参照言及)を確認。session_id が compact 前後で
   連続していることもここで確認する(実装時検証項目)。

## 非スコープ

- 自動 compact の再有効化(現行の無効運用を維持)
- 圧縮要約プロンプト自体のカスタマイズ
- 複数セッション並行時の state file 共有(session_id で分離されるため不要)
- `--resume` 後の state file 引き継ぎ: resume で session_id が変わる場合、
  旧 sid の state file は参照されない(TTL 掃除で消える)。
  「prep → 終了 → 翌日 resume → compact」の流れは非対応と割り切る。
  必要になったら resume 時の sid 連続性を検証してから設計する
