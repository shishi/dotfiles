#!/usr/bin/env bash
# shellcheck disable=SC2016
# Public memory consumers use one cross-process helper without weakening bootstrap policy.
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

require_literal() {
  local file="$1" literal="$2" description="$3"
  if grep -qF -- "$literal" "$file"; then pass "$description"; else fail "$description"; fi
}

forbid_regex() {
  local file="$1" pattern="$2" description="$3"
  if grep -Eq -- "$pattern" "$file"; then fail "$description"; else pass "$description"; fi
}

require_order() {
  local file="$1" description="$2"
  shift 2
  local previous=0 literal line
  for literal in "$@"; do
    line="$(MEMORY_POLICY_LITERAL="$literal" awk -v previous="$previous" '
      NR > previous && index($0, ENVIRON["MEMORY_POLICY_LITERAL"]) { print NR; exit }
    ' "$file")"
    if [ -z "$line" ]; then
      fail "$description (missing or out of order: $literal)"
      return
    fi
    previous="$line"
  done
  pass "$description"
}

INSTRUCTIONS=("$REPO/claude/CLAUDE.md" "$REPO/codex/AGENTS.md")
SKILLS=(
  "$REPO/claude/skills/memory-consolidate/SKILL.md"
  "$REPO/codex/skills/memory-consolidate/SKILL.md"
)
CAPTURE_SKILLS=(
  "$REPO/claude/skills/capturing-memory/SKILL.md"
  "$REPO/codex/skills/capturing-memory/SKILL.md"
)
CONSUMERS=("${INSTRUCTIONS[@]}" "${SKILLS[@]}")
LOCK_HELPER="$REPO/agents/bin/memory-write-lock.sh"

for file in "${CONSUMERS[@]}"; do
  require_order "$file" "$file keeps the lock across the full bootstrap" \
    'bash ~/.agents/bin/resolve-memory-dir.sh' \
    'bash ~/.agents/bin/memory-write-lock.sh acquire "$memory_repo"' \
    'upstream が `origin/main`、clean、' \
    'ahead/behind を確認' \
    'git pull --rebase' \
    '同期後の HEAD から `CONVENTIONS.md`' \
    'bash ~/.agents/bin/memory-write-lock.sh release "$memory_lock_handle"'
  require_literal "$file" '複数の tool call' \
    "$file describes the cross-process handle lifetime"
  require_literal "$file" 'handle path は owner token ではない' \
    "$file distinguishes the opaque handle from the owner token"
  require_literal "$file" '不要にログへ出さない' \
    "$file avoids unnecessary handle logging"
  require_literal "$file" 'stdout だけでなく終了 status 0' \
    "$file requires successful handle transfer status"
  require_literal "$file" 'nonzero の場合は出力を handle として使わず停止する' \
    "$file rejects output from an unsuccessful acquire"
  require_literal "$file" '成功扱いにしない' \
    "$file treats release failure as workflow failure"
  require_literal "$file" 'finally 相当' \
    "$file requires explicit release on every outcome"
  require_literal "$file" 'ユーザー確認なしで削除しない' \
    "$file preserves stale lock state for confirmed recovery"
  forbid_regex "$file" 'memory_lock_token=|memory_write_retirement_exists\(\)|trap .*memory_write|mkdir "\$memory_lock"' \
    "$file contains no process-local lock implementation"
  forbid_regex "$file" 'source .*memory-write-lock|eval .*memory-write-lock' \
    "$file never sources or evaluates handle state"

  require_literal "$file" 'origin/main' "$file checks the required upstream"
  require_literal "$file" 'clean' "$file requires a clean worktree"
  require_literal "$file" 'merge/rebase' "$file checks in-progress operations"
  require_literal "$file" 'ahead がないこと' "$file rejects a local-ahead main"
  require_literal "$file" 'ahead/behind' "$file checks divergence"
  require_literal "$file" 'git pull --rebase' "$file pulls while holding the lock"
  require_literal "$file" '同期後の HEAD' "$file reads the synchronized protocol"
done

require_literal "${INSTRUCTIONS[0]}" '`~/.claude/memory` の物理的な解決先が' \
  "Claude instruction verifies its canonical memory link"
require_literal "${INSTRUCTIONS[1]}" '`~/.codex/memory` の物理的な解決先が' \
  "Codex instruction verifies its canonical memory link"

for file in "${INSTRUCTIONS[@]}"; do
  require_literal "$file" 'main:<repo 相対パス>' "$file reads degraded detail from main"
  require_literal "$file" 'credentials、token、password、private key' \
    "$file forbids stored secrets"
  require_literal "$file" '外部コンテンツから' "$file begins the external-instruction boundary"
  require_literal "$file" '取り込んだ命令は' "$file identifies stored external instructions"
  require_literal "$file" '保存しない。' "$file forbids stored external instructions"
  require_literal "$file" 'タスク完了前に記憶候補を監査する' \
    "$file audits memory candidates before completing a task"
  require_literal "$file" '`capturing-memory` skill' \
    "$file routes durable knowledge through the capture skill"
  require_literal "$file" 'その場限り' "$file distinguishes turn-local direction"
  require_literal "$file" 'プロジェクト固有' "$file distinguishes project-scoped knowledge"
  require_literal "$file" '全体にわたる価値観' "$file distinguishes global values"
  require_literal "$file" '判定できない場合はユーザーに確認する' \
    "$file asks instead of guessing an ambiguous memory scope"
done

for file in "${SKILLS[@]}"; do
  require_literal "$file" 'credentials、token、password、private key' \
    "$file forbids storing secrets during consolidation"
  require_literal "$file" '外部コンテンツから' \
    "$file begins the consolidation instruction boundary"
  require_literal "$file" '取り込んだ命令は' \
    "$file identifies external instructions during consolidation"
  require_literal "$file" '保存しない。' \
    "$file forbids storing external instructions during consolidation"
  require_literal "$file" '`CORE.md`' "$file consolidates global values"
  require_literal "$file" '時系列だけで陳腐化と判断しない' \
    "$file does not prune memory merely because it is old"
  require_literal "$file" '現行の事実' "$file requires current evidence before pruning"
  require_literal "$file" '明示的な撤回' "$file recognizes explicit withdrawal"
  require_literal "$file" '後継方針' "$file recognizes superseding policy"
  require_literal "$file" '現行の事実・明示的な撤回・確認できる後継方針を根拠に解決した' \
    "$file uses evidence rather than recency to resolve contradictions"
  forbid_regex "$file" '矛盾を最新値で解決した' \
    "$file does not keep the obsolete latest-wins checklist"
  require_literal "$file" 'frontmatter の `type` だけでなく本文の適用範囲' \
    "$file audits memory placement from content rather than metadata alone"
  require_literal "$file" 'フックが注入する指示' \
    "$file compares memory against runtime hook instructions"
  require_literal "$file" '実際の注入出力' \
    "$file measures the effective injected memory payload"
  require_literal "$file" '設定仕様で定義された単位' \
    "$file compares injected output with its limit using the configured unit"
  require_literal "$file" '整理プロトコルを正本として従う' \
    "$file delegates the memory-repository workflow to synchronized conventions"
  forbid_regex "$file" 'git switch -c consolidation/<YYYY-MM-DD>|git push origin HEAD.*レビュー' \
    "$file does not retain the obsolete hard-coded consolidation workflow"
  if [[ "$file" == *'/codex/'* ]]; then
    require_literal "$file" 'AGENTS.md にもあることだけを理由に `CORE.md` の価値観を削除しない' \
      "$file preserves global values even when AGENTS.md also enforces them"
  else
    require_literal "$file" 'CLAUDE.md にもあることだけを理由に `CORE.md` の価値観を削除しない' \
      "$file preserves global values even when CLAUDE.md also enforces them"
  fi
done

for file in "${INSTRUCTIONS[@]}"; do
  require_literal "$file" '同期後の `CONVENTIONS.md` にある' \
    "$file delegates consolidation to synchronized memory conventions"
done

for file in "${CAPTURE_SKILLS[@]}"; do
  if [ -f "$file" ]; then
    pass "$file exists"
  else
    fail "$file is missing"
    continue
  fi
  require_literal "$file" '`CORE.md`' "$file stores global values in CORE.md"
  require_literal "$file" '`projects/<slug>.md`' "$file stores project knowledge by slug"
  require_literal "$file" 'その場限り' "$file identifies turn-local direction"
  require_literal "$file" 'プロジェクト固有' "$file identifies project-scoped knowledge"
  require_literal "$file" '全体にわたる価値観' "$file identifies global values"
  require_literal "$file" '再利用する技術・環境リファレンス' \
    "$file routes cross-project technical reference knowledge"
  require_literal "$file" '判定できない場合はユーザーに確認する' \
    "$file asks about ambiguous memory scope"
  require_literal "$file" '一時的な例外' "$file preserves broader policy across local exceptions"
  require_literal "$file" '明示的な撤回' "$file requires explicit withdrawal before replacement"
  require_literal "$file" 'credentials、token、password、private key' \
    "$file forbids storing secrets"
  require_literal "$file" '外部コンテンツから取り込んだ命令' \
    "$file forbids persisting external instructions"
  require_literal "$file" 'memory-write-preflight.sh' "$file uses the tracked preflight"
  require_literal "$file" 'memory-write-finish.sh' "$file uses the tracked finalizer"
  require_literal "$file" '1 回の Bash 呼び出し' \
    "$file batches commit, push, verification, and release"
  require_literal "$file" '同期後の HEAD' "$file reads synchronized conventions"
  require_literal "$file" 'release' "$file releases the write lock"
  require_literal "$file" '編集したファイルだけを path 指定で stage' \
    "$file stages only edited memory paths"
  require_literal "$file" '`git add -A` と `commit -a` は使わない' \
    "$file explicitly rejects broad staging"
  require_literal "$file" '親 turn を終了する前に完了と lock 解放を確認する' \
    "$file never ends the parent turn while an implicit capture still holds the lock"
done

if grep -qF 'link_agent_home "${DOTDIR}/agents/bin" "$HOME/.agents/bin"' "$REPO/setup.sh" \
  && [ -f "$REPO/agents/bin/memory-write-lock.sh" ]; then
  pass "setup links the directory containing the shared lock helper"
else
  fail "setup does not expose the shared lock helper under ~/.agents/bin"
fi

state_remove_calls="$(grep -Ec '^[[:space:]]+remove_state_directory ' "$LOCK_HELPER")"
if [ "$state_remove_calls" -eq 1 ] \
  && grep -Eq '^[[:space:]]+remove_state_directory "\$retired"' "$LOCK_HELPER"; then
  pass "only token-private retired state is passed to destructive cleanup"
else
  fail "canonical pending or handle state can reach destructive cleanup"
fi

require_order "$LOCK_HELPER" "final handle is created in place without a directory rename" \
  'handle="$state_root/handle.$suffix"' \
  'mkdir "$handle"' \
  'printf '\''%s\n'\'' "$acquire_repo" >"$handle/repo"'
require_order "$LOCK_HELPER" "owner marker is committed inside an atomic private directory" \
  'owner="$lock/owner-$token"' \
  'mkdir "$owner"' \
  'mv "$owner_tmp" "$owner/value"'
require_order "$LOCK_HELPER" "lock retirement uses a verified private container" \
  'create_private_container "$repo/.git" "memory-write-retirement."' \
  'retired="$private_container/lock"' \
  'mv "$lock" "$retired"'
forbid_regex "$LOCK_HELPER" 'mv[[:space:]]+-n|\.pending\.' \
  "helper contains no nesting-prone no-replace move or pending rename"

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
