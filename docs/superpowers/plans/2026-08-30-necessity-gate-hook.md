# 要否判断 Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 現在の依頼へ具体的な実益がない作業を、既存の毎ターン指示で抑止します。

**Architecture:** 既存の `UserPromptSubmit` hook に要否判断の原則を 1 文追加します。新しい hook、設定、禁止対象の列挙は追加しません。

**Tech Stack:** Bash、jq

---

### Task 1: 要否判断を既存 hook へ追加

**Files:**
- Modify: `agents/hooks/enforce-continuation.test.sh`
- Modify: `agents/hooks/enforce-continuation.sh`

- [ ] **Step 1: 失敗する外部契約テストを書く**

既存のコンテキスト検証を、次の最小契約へ置き換えます。

```bash
if printf '%s' "$out" | jq -e '
  .hookSpecificOutput.hookEventName == "UserPromptSubmit"
  and (.hookSpecificOutput.additionalContext
    | contains("現在の依頼へ直接もたらす実益または回避する具体的リスク"))
' >/dev/null 2>&1; then
  ok "hook injects the necessity rule as UserPromptSubmit context"
else
  ng "hook injects the necessity rule as UserPromptSubmit context"
fi
```

- [ ] **Step 2: Red を確認する**

Run: `bash agents/hooks/enforce-continuation.test.sh`

Expected: `hook injects the necessity rule as UserPromptSubmit context` が `NG` になり、終了 status が nonzero になります。

- [ ] **Step 3: 最小実装を追加する**

`message` の先頭へ次の 1 項目を追加します。

```text
- 作業を始める前に、現在の依頼へ直接もたらす実益または回避する具体的リスクを説明できるか判断せよ。説明できなければ、その作業を行うな。論理的に成立することやレビューで指摘されたこと自体は、必要性の根拠にならない。
```

- [ ] **Step 4: Green を確認する**

Run: `bash agents/hooks/enforce-continuation.test.sh`

Expected: `PASS=5 FAIL=0` で終了 status が 0 になります。

- [ ] **Step 5: コミットする**

```bash
git add agents/hooks/enforce-continuation.sh agents/hooks/enforce-continuation.test.sh
git commit -m "fix(agent): require concrete benefit"
```
