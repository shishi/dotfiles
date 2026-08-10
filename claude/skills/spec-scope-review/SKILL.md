---
name: spec-scope-review
description: |
  spec-scope-reviewer agent(仕様・スコープ照合)を単独実行するラッパー。
  タスク記述・レビュー対象・設計 doc を組成して dispatch する。review-gate の
  レーン1 と同じ観点を任意タイミングで単独発動するときに使う。
  マイルストーン判断は持たない。
---

# Spec-scope review(単独発動ラッパー)

仕様・スコープ観点(`~/.claude/agents/spec-scope-reviewer.md`)を 1 レーンだけ走らせる。

## 入力組成(review-gate のレーン1 と同一規則)

1. **タスク記述 — 既存テキストの逐語コピーに限る**: 元のユーザー依頼・plan doc の
   該当セクション・spec のいずれか。実装後に要約・言い換えして渡すことを禁止
   (実装中の合理化がタスク記述へ逆流し、レビューが「合理化への準拠確認」に化けるため)。
   該当テキストが無ければ停止してユーザーに求める(新規に書き起こして代用しない)
2. **レビュー対象**: `git diff HEAD` の全文 + untracked ファイル
   (`git status --short --untracked-files=all` で列挙)の本文
3. **設計 doc**: repo 内 doc(`docs/` 等)の存在を確認し、あれば該当部を含める。
   存在確認をせずにレビューを開始しない
4. CLAUDE.md(global + project)の該当規約

**実装中の会話内容をプロンプトに書かない**(この観点の存在意義は情報の隔離)。

## 実行

Task tool で `spec-scope-reviewer` subagent を dispatch し、上記入力をプロンプトで渡す。

## 結果処理(単独発動時)

1. 引用検証: 欠陥主張の引用はレビュー対象と、要件未達の引用は要件ソースと照合。
   不一致は棄却し [A-n] 付きで記録
2. blocker/should を修正 → 入力を再組成して再 dispatch。blocker/should ゼロで clean
3. 「判断できない」が多発したらタスク記述の品質シグナル: 別の既存逐語ソースを探すか
   ユーザーに確認する(主エージェントの新規書き起こしは不可)
4. 膠着判定: 同一指摘 2 回連続未解消 → 停止してユーザーへ報告

## Final report(単独発動時)

```
## Spec-scope レビュー結果
- 反復: <X> 回 / ステータス: ✅ clean | ⚠️ 膠着で停止
- 要件判定の要約(満たしている/いない/判断できない の件数)
- 修正した指摘: [A-n] と要約 / 棄却: [A-n] + 理由 / 未対応 note: [A-n]
```
