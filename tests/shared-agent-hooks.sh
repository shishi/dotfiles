#!/usr/bin/env bash
# Claude CodeとCodexが同じ共有hook実体を使う契約を検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

assert_jq() { # $1=description $2=file $3=filter
  if jq -e "$3" "$2" >/dev/null; then ok "$1"; else ng "$1"; fi
}

assert_jq "Claude uses the shared git push guard" "$REPO/claude/settings.json" \
  '.hooks.PreToolUse[0].hooks[0].command == "bash ~/.agents/hooks/git-push-guard.sh"'
assert_jq "Claude has no deny rule that overrides the git push guard" "$REPO/claude/settings.json" \
  '([.permissions.deny[] | select(test("^Bash\\(git push"))] | length) == 0'
assert_jq "Codex uses the shared git push guard" "$REPO/codex/hooks.json" \
  '.hooks.PreToolUse[0].hooks[0].command == "bash ~/.agents/hooks/git-push-guard.sh"'
assert_jq "Codex Windows uses the shared git push guard" "$REPO/codex/hooks.json" \
  '(.hooks.PreToolUse[0].hooks[0].commandWindows | test("-c '\''~/.agents/hooks/git-push-guard\\.sh'\''$"))'
assert_jq "Claude records explicit push authorization with the shared guard" "$REPO/claude/settings.json" \
  '([.hooks.UserPromptSubmit[].hooks[].command | select(. == "bash ~/.agents/hooks/git-push-guard.sh --record-approval")] | length) == 1'
assert_jq "Codex records explicit push authorization with the shared guard" "$REPO/codex/hooks.json" \
  '.hooks.UserPromptSubmit[0].hooks[0].command == "bash ~/.agents/hooks/git-push-guard.sh --record-approval"'
assert_jq "Codex Windows records authorization with the shared guard" "$REPO/codex/hooks.json" \
  '(.hooks.UserPromptSubmit[0].hooks[0].commandWindows | test("-c '\''~/.agents/hooks/git-push-guard\\.sh --record-approval'\''$"))'

if ! rg -q -- '--execute-approved' "$REPO/codex/rules/default.rules"; then
  ok "obsolete Codex approval runner has no execpolicy rule"
else
  ng "obsolete Codex approval runner has no execpolicy rule"
fi

if [ -f "$REPO/agents/hooks/git-push-guard.sh" ]; then
  ok "shared git push guard exists"
else
  ng "shared git push guard exists"
fi
if [ -f "$REPO/agents/hooks/git-push-guard.test.sh" ]; then
  ok "shared git push guard test exists"
else
  ng "shared git push guard test exists"
fi

for old_path in \
  claude/hooks/git-push-guard.sh \
  claude/hooks/git-push-guard.test.sh \
  codex/hooks/git-push-guard.sh \
  codex/hooks/git-push-guard.test.sh
do
  if [ ! -e "$REPO/$old_path" ]; then
    ok "old copy removed: $old_path"
  else
    ng "old copy removed: $old_path"
  fi
done

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
