# compact 対策 3点セット 設計書

日付: 2026-07-05
状態: 承認済み(設計レビュー完了)

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
- 保存先: `~/.claude/compact-state/<session_id>.md`
- 見出しを次の順で固定(**Forcing function**: 保存後に読み返して全見出しの存在を確認):
  `# Compact Prep State` / `## Active Plan` / `## Current Phase` / `## TaskList Summary` /
  `## Session Decisions`(採用案・却下案・却下理由)/ `## Constraints and Blockers` /
  `## Delegated Work`(委譲中の agent・background task)/ `## Editing Files` /
  `## Recovery Notes`(圧縮後の自分への手紙)
- `allowed-tools` で副作用を絞る(Read / Write / 最小限の Bash)。
- 完了レシート: state file パス、保存項目、未確認項目、`/compact` 実行案内。

### 2. 圧縮後復旧 hook(新規: `claude/hooks/session-start-compaction-recovery.sh`)

- 登録: `SessionStart`、matcher `compact`。
- stdin JSON から `session_id` を取得(空なら即 exit 0)。
- `~/.claude/compact-state/<session_id>.md` が存在すれば additionalContext で注入:
  - state file を Read して作業状態を復元せよ(Session Decisions と Recovery Notes を重視)
  - TaskList で現在のタスクを確認せよ
  - 圧縮サマリーの next step は仮説として扱い、plan / rules を正とせよ
  - plan mode が解除されていたらユーザーに再突入を確認せよ
- state file が無くても、上記の一般復旧指示(TaskList 確認・サマリーは仮説扱い)は注入する。
- warn / warned marker を削除する(通知 cooldown のリセット)。
- **fail-open**: いかなる場合も exit 0。

### 3. 閾値通知

#### 3a. statusline 変更(`claude/statusline.sh`)

- % 計算を stdin の `context_window.used_percentage` 優先に変更。
  フィールドが取れない場合は現行の transcript 自前計算に fallback
  (その際の分母 1M 決め打ちも `context_window.context_window_size` があれば置換)。
- `used_percentage >= 80` かつ warned marker が無ければ
  `~/.claude/compact-state/warn/<session_id>` に使用率を書く。
- 表示フォーマットは現行を維持。

#### 3b. reminder hook(新規: `claude/hooks/userpromptsubmit-compact-reminder.sh`)

- 登録: `UserPromptSubmit`(matcher なし、毎ターン発火)。
- warn marker が無ければ `test -f` 1 回で即 exit 0(通常ターンのコストほぼゼロ)。
- warn marker があれば:
  1. marker から使用率を読み、warn marker を削除(one-shot)
  2. `~/.claude/compact-state/warned/<session_id>` を作成(二重通知防止)
  3. additionalContext で注入: 「context 使用率が N% に達した。作業の区切りで
     `/compact-prep` → `/compact` をユーザーに提案せよ。scope 縮小や別セッション化でなく
     圧縮前 state 保存で対処せよ」
- **fail-open**: 常に exit 0。

### marker / state ファイル一覧

| パス | 書く人 | 消す人 | 意味 |
|------|--------|--------|------|
| `compact-state/<sid>.md` | compact-prep skill | (残置。同一 sid の再 prep で上書き) | 圧縮前の判断構造 |
| `compact-state/warn/<sid>` | statusline | reminder hook(通知時)/ recovery hook(圧縮時の掃除) | 通知したい |
| `compact-state/warned/<sid>` | reminder hook | recovery hook | 通知済み(cooldown) |

### 4. settings.json 変更

既存の `PreToolUse`(git-push-guard)はそのまま。以下を追加:

```json
"SessionStart": [
  { "matcher": "compact", "hooks": [
    { "type": "command", "command": "bash ~/.claude/hooks/session-start-compaction-recovery.sh", "timeout": 10 }
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

## テスト計画

1. **hook 単体スモーク**: 偽の stdin JSON を食わせて出力 JSON と marker の増減を確認。
   例: `echo '{"session_id":"test-sid"}' | bash claude/hooks/userpromptsubmit-compact-reminder.sh`
   - warn marker あり → additionalContext JSON が出て warn 消滅・warned 作成
   - warn marker なし → 出力なしで exit 0
   - recovery hook: state file あり/なし両方の注入内容、warned 削除
2. **statusline スモーク**: `used_percentage` 入り JSON で % 表示と warn marker 作成、
   フィールド欠落 JSON で fallback 計算を確認。
3. **実セッション通し**: 実セッションで `/compact-prep` → state file 生成を確認 →
   `/compact` → 直後のターンに復旧指示が効いているか(state file 参照言及)を確認。

## 非スコープ

- 自動 compact の再有効化(現行の無効運用を維持)
- 圧縮要約プロンプト自体のカスタマイズ
- 複数セッション並行時の state file 共有(session_id で分離されるため不要)
