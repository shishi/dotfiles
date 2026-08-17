#!/usr/bin/env bash
# Claude / Codex の memory-consolidate Skill が agent-specific path 以外で
# drift していないことを検査する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_SKILL="$REPO/claude/skills/memory-consolidate/SKILL.md"
CODEX_SKILL="$REPO/codex/skills/memory-consolidate/SKILL.md"
TMP=""
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

cleanup() {
  [ -z "$TMP" ] || rm -rf "$TMP"
}
exit_on_signal() {
  status="$1"
  trap - EXIT
  cleanup
  exit "$status"
}
trap cleanup EXIT
trap 'exit_on_signal 129' HUP
trap 'exit_on_signal 130' INT
trap 'exit_on_signal 143' TERM

if [ -f "$CLAUDE_SKILL" ]; then
  pass "Claude Skill exists"
else
  fail "Claude Skill missing: $CLAUDE_SKILL"
fi

if [ -f "$CODEX_SKILL" ]; then
  pass "Codex Skill exists"
else
  fail "Codex Skill missing: $CODEX_SKILL"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo
  echo "PASS/FAIL: FAILURES=$FAILURES"
  exit 1
fi

grep -qF '~/.claude/memory' "$CLAUDE_SKILL" \
  && pass "Claude Skill uses Claude memory path" \
  || fail "Claude Skill does not use ~/.claude/memory"
grep -qF '~/.codex/memory' "$CODEX_SKILL" \
  && pass "Codex Skill uses Codex memory path" \
  || fail "Codex Skill does not use ~/.codex/memory"

if grep -qF '~/.codex/memory' "$CLAUDE_SKILL"; then
  fail "Claude Skill contains Codex memory path"
else
  pass "Claude Skill contains no Codex memory path"
fi
if grep -qF '~/.claude/memory' "$CODEX_SKILL"; then
  fail "Codex Skill contains Claude memory path"
else
  pass "Codex Skill contains no Claude memory path"
fi

TMP="$(mktemp -d)" || {
  echo "fatal: mktemp failed" >&2
  exit 1
}
NORMALIZATION_FAILED=0
if ! sed 's|~/\.claude/memory|~/.agent/memory|g' "$CLAUDE_SKILL" > "$TMP/claude.normalized"; then
  fail "failed to normalize Claude Skill"
  NORMALIZATION_FAILED=1
fi
if ! sed 's|~/\.codex/memory|~/.agent/memory|g' "$CODEX_SKILL" > "$TMP/codex.normalized"; then
  fail "failed to normalize Codex Skill"
  NORMALIZATION_FAILED=1
fi

if [ "$NORMALIZATION_FAILED" -eq 0 ]; then
  if cmp -s "$TMP/claude.normalized" "$TMP/codex.normalized"; then
    pass "normalized Skills are byte-for-byte identical"
  else
    fail "Skills differ beyond the agent-specific memory path"
    diff -u "$TMP/claude.normalized" "$TMP/codex.normalized" || true
  fi
fi

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
