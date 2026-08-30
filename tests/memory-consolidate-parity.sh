#!/usr/bin/env bash
# Claude / Codex の memory-consolidate Skill が agent-specific memory path と
# instruction file 以外で drift していないことを検査する。
set -u
export LC_ALL=C

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_SKILL="$REPO/claude/skills/memory-consolidate/SKILL.md"
CODEX_SKILL="$REPO/codex/skills/memory-consolidate/SKILL.md"
TMP=""
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

literal_count() {
  token="$1"
  file="$2"
  awk -v token="$token" '
    {
      line = $0
      while ((position = index(line, token)) != 0) {
        count++
        line = substr(line, position + length(token))
      }
    }
    END { print count + 0 }
  ' "$file"
}

boundary_token_count() {
  token="$1"
  file="$2"
  awk -v token="$token" '
    {
      search_from = 1
      while ((relative = index(substr($0, search_from), token)) != 0) {
        position = search_from + relative - 1
        before = position == 1 ? "" : substr($0, position - 1, 1)
        after_position = position + length(token)
        after = after_position > length($0) ? "" : substr($0, after_position, 1)
        if ((before == "" || before !~ /[[:alnum:]_.-]/) &&
            (after == "" || after !~ /[[:alnum:]_.-]/)) {
          count++
        }
        search_from = position + length(token)
      }
    }
    END { print count + 0 }
  ' "$file"
}

assert_count() {
  expected="$1"
  actual="$2"
  label="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected=$expected actual=${actual:-empty})"
  fi
}

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

CLAUDE_MEMORY_TOKEN='`~/.claude/memory/`'
CODEX_MEMORY_TOKEN='`~/.codex/memory/`'
CLAUDE_INSTRUCTION_TOKEN='CLAUDE.md'
CODEX_INSTRUCTION_TOKEN='AGENTS.md'

assert_count 1 "$(literal_count "$CLAUDE_MEMORY_TOKEN" "$CLAUDE_SKILL")" \
  "Claude Skill contains its exact memory path once"
assert_count 1 "$(literal_count "$CODEX_MEMORY_TOKEN" "$CODEX_SKILL")" \
  "Codex Skill contains its exact memory path once"
assert_count 0 "$(literal_count "$CODEX_MEMORY_TOKEN" "$CLAUDE_SKILL")" \
  "Claude Skill contains no exact Codex memory path"
assert_count 0 "$(literal_count "$CLAUDE_MEMORY_TOKEN" "$CODEX_SKILL")" \
  "Codex Skill contains no exact Claude memory path"

assert_count 3 "$(literal_count "$CLAUDE_INSTRUCTION_TOKEN" "$CLAUDE_SKILL")" \
  "Claude Skill contains three raw Claude instruction tokens"
assert_count 3 "$(boundary_token_count "$CLAUDE_INSTRUCTION_TOKEN" "$CLAUDE_SKILL")" \
  "Claude Skill contains three bounded Claude instruction tokens"
assert_count 3 "$(literal_count "$CODEX_INSTRUCTION_TOKEN" "$CODEX_SKILL")" \
  "Codex Skill contains three raw Codex instruction tokens"
assert_count 3 "$(boundary_token_count "$CODEX_INSTRUCTION_TOKEN" "$CODEX_SKILL")" \
  "Codex Skill contains three bounded Codex instruction tokens"
assert_count 0 "$(literal_count "$CODEX_INSTRUCTION_TOKEN" "$CLAUDE_SKILL")" \
  "Claude Skill contains no raw Codex instruction token"
assert_count 0 "$(literal_count "$CLAUDE_INSTRUCTION_TOKEN" "$CODEX_SKILL")" \
  "Codex Skill contains no raw Claude instruction token"
assert_count 0 "$(printf '%s\n' 'CLAUDE.mdCLAUDE.md' | \
  boundary_token_count "$CLAUDE_INSTRUCTION_TOKEN" -)" \
  "adjacent instruction tokens are not boundary matches"

TMP="$(mktemp -d)" || {
  echo "fatal: mktemp failed" >&2
  exit 1
}
NORMALIZATION_FAILED=0
if ! sed \
  -e 's|`~/\.claude/memory/`|`~/.agent/memory/`|g' \
  -e 's|CLAUDE\.md|AGENT.md|g' \
  "$CLAUDE_SKILL" > "$TMP/claude.normalized"; then
  fail "failed to normalize Claude Skill"
  NORMALIZATION_FAILED=1
fi
if ! sed \
  -e 's|`~/\.codex/memory/`|`~/.agent/memory/`|g' \
  -e 's|AGENTS\.md|AGENT.md|g' \
  "$CODEX_SKILL" > "$TMP/codex.normalized"; then
  fail "failed to normalize Codex Skill"
  NORMALIZATION_FAILED=1
fi

if [ "$NORMALIZATION_FAILED" -eq 0 ]; then
  if cmp -s "$TMP/claude.normalized" "$TMP/codex.normalized"; then
    pass "normalized Skills are byte-for-byte identical"
  else
    fail "Skills differ beyond agent-specific paths and instruction files"
    diff -u "$TMP/claude.normalized" "$TMP/codex.normalized" || true
  fi
fi

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
