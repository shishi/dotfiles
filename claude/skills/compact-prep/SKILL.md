---
name: compact-prep
description: 利用者が /compact-prep を実行したとき、または「圧縮準備」「compact の準備」「圧縮前の状態保存」を頼まれたときに、Claude Code の /compact の前に現セッションの作業状態を state file へ保存する。圧縮後の復旧、通常の進捗報告、計画の作成には使わない。
argument-hint: "[復旧メモ]"
allowed-tools: Read, Write, Bash(echo:*), Bash(date:*), Bash(mkdir:*)
---

# compact-prep

Claude Code の `/compact` 前に、圧縮サマリーへ残りにくい「判断構造」と
「セッション状態」を `~/.claude/compact-state/<session_id>.md` へ保存する。
圧縮要約は「過去の作業記録」になりがちで、却下理由・現在フェーズ・委譲状態が
落ちる。この state file が圧縮直後の復旧材料になる(SessionStart hook が参照する)。

## 必ず守ること

- session_id が取得できない場合は state file を推測名で作らず、
  「session_id が取得できないため準備未完了」と報告して停止する。
- 保存後にファイルを Read で読み返し、必須見出しの有無を確認する。

## 提案が出る経路

使用率が閾値を超えると、statusline (`claude/statusline.sh`) が印を書き、UserPromptSubmit の hook がこの skill の実行を提案させる。
この提案は statusline が動く Claude Code CLI の会話でしか出ていない。T3 Code と Claude デスクトップアプリの会話では、
提案が出ないまま圧縮が起きている。そこでは、利用者が /compact-prep を実行したときにこの skill を使う。

## 手順

1. session_id を取得する。
   - `echo "$CLAUDE_CODE_SESSION_ID"` を実行する。
   - 空の場合は上の「必ず守ること」に従い、報告して停止する。
2. `mkdir -p ~/.claude/compact-state` を実行し、
   保存先を `~/.claude/compact-state/<session_id>.md` に決める。
3. 現セッションを振り返り、保存内容を収集する。
   - TaskList の in-progress / pending タスクと補足
   - active plan(あれば plan ファイルのパスと現在フェーズ)
   - セッション中の判断: 採用した案、却下した案、**却下した理由**
   - 制約・ブロッカー・未完了の検証
   - 委譲中の作業(subagent、background task、agent team の担当と状態)
   - 編集中のファイルと未保存・未検証の注意点
4. `date -Iseconds` で現在時刻を取得し、次の構成で state file を Write する。
   見出しはこの順で固定。該当なしの項目は「なし」と書く(見出し自体は省略しない)。

   # Compact Prep State
   Prepared: <ISO 8601 タイムスタンプ>

   ## Active Plan
   ## Current Phase
   ## TaskList Summary
   ## Session Decisions
   ## Constraints and Blockers
   ## Delegated Work
   ## Editing Files
   ## Recovery Notes

   Recovery Notes は「圧縮後の自分への手紙」。ユーザーから引数で復旧メモが
   渡されていればここに含める。
5. 保存後に state file を Read で読み直し、上記見出しがすべて存在することを
   確認する。欠落があれば書き直して再確認する。
6. 完了レシートを報告する。
   - state file パス
   - 保存した主要項目
   - 未確認項目と理由
   - 「準備完了。`/compact` を実行してください。」
