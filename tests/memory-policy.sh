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
