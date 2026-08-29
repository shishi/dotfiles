#!/usr/bin/env bash
# codex/hooks.json の SessionStart memory hook 契約を Bash + jq で検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${HOOKS_CONFIG:-$REPO/codex/hooks.json}"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }
assert_jq() { # $1=description $2=filter
  if jq -e "$2" "$CONFIG" >/dev/null; then
    ok "$1"
  else
    ng "$1"
  fi
}

if jq -e 'type == "object"' "$CONFIG" >/dev/null 2>&1; then
  ok "hooks.json is a valid JSON object"
else
  ng "hooks.json is a valid JSON object"
fi

if python3 - "$CONFIG" 2>/dev/null <<'PY'
import json
import sys

def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result

with open(sys.argv[1], encoding="utf-8") as config:
    json.load(config, object_pairs_hook=reject_duplicate_keys)
PY
then
  ok "hooks.json has no duplicate object keys"
else
  ng "hooks.json has no duplicate object keys"
fi

assert_jq "one SessionStart shared injector" \
  '([.hooks.SessionStart[]? | .hooks[]? | select(.command == "bash ~/.agents/hooks/inject-memory.sh ~/.codex/memory")] | length) == 1'
assert_jq "SessionStart shared injector matcher is exact" \
  '([.hooks.SessionStart[]? | select(any(.hooks[]?; .command == "bash ~/.agents/hooks/inject-memory.sh ~/.codex/memory")) | .matcher] == ["startup|resume|clear|compact"])'
assert_jq "SessionStart shared injector context limit is 10000" \
  '([.hooks.SessionStart[]? | .hooks[]? | select(.command == "bash ~/.agents/hooks/inject-memory.sh ~/.codex/memory") | .additionalContextLimit] == [10000])'
assert_jq "SessionStart Windows command uses the portable launcher" \
  '([.hooks.SessionStart[]? | .hooks[]? | select(.command == "bash ~/.agents/hooks/inject-memory.sh ~/.codex/memory") | .commandWindows] == ["& (Join-Path $HOME '\''.agents/bin/invoke-git-bash-hook.ps1'\'') '\''~/.agents/hooks/inject-memory.sh ~/.codex/memory'\''"])'
assert_jq "one PreToolUse shared git push guard" \
  '([.hooks.PreToolUse[]? | .hooks[]? | select(.command == "bash ~/.agents/hooks/git-push-guard.sh")] | length) == 1'
assert_jq "PreToolUse shared git push guard belongs to the Bash matcher" \
  '([.hooks.PreToolUse[]? | select(any(.hooks[]?; .command == "bash ~/.agents/hooks/git-push-guard.sh")) | .matcher] == ["Bash"])'
assert_jq "PreToolUse Windows command uses the portable launcher" \
  '([.hooks.PreToolUse[]? | .hooks[]? | select(.command == "bash ~/.agents/hooks/git-push-guard.sh") | .commandWindows] == ["& (Join-Path $HOME '\''.agents/bin/invoke-git-bash-hook.ps1'\'') '\''~/.agents/hooks/git-push-guard.sh'\''"])'
assert_jq "one UserPromptSubmit approval recorder" \
  '([.hooks.UserPromptSubmit[]? | .hooks[]? | select(.command == "bash ~/.agents/hooks/git-push-guard.sh --record-approval")] | length) == 1'
assert_jq "UserPromptSubmit Windows command uses the portable launcher" \
  '([.hooks.UserPromptSubmit[]? | .hooks[]? | select(.command == "bash ~/.agents/hooks/git-push-guard.sh --record-approval") | .commandWindows] == ["& (Join-Path $HOME '\''.agents/bin/invoke-git-bash-hook.ps1'\'') '\''~/.agents/hooks/git-push-guard.sh --record-approval'\''"])'
assert_jq "Herdr SessionStart uses the portable launcher" \
  '([.hooks.SessionStart[]? | .hooks[]? | select(.command == "bash ~/.codex/herdr-agent-state.sh session") | .commandWindows] == ["& (Join-Path $HOME '\''.agents/bin/invoke-git-bash-hook.ps1'\'') '\''~/.codex/herdr-agent-state.sh session'\''"])'
assert_jq "every Windows handler uses the portable launcher" \
  '([.hooks | to_entries[] | .value[]? | .hooks[]? | .commandWindows | select(startswith("& (Join-Path $HOME '\''.agents/bin/invoke-git-bash-hook.ps1'\'') '\''") | not)] | length) == 0'
assert_jq "Windows handlers contain no absolute home path" \
  '([.hooks | to_entries[] | .value[]? | .hooks[]? | (.commandWindows // "") | select(test("C:/Users/|C:\\\\Users\\\\|/Users/|/home/"; "i"))] | length) == 0'

registered=""
while IFS= read -r script; do
  if [ -f "$REPO/codex/hooks/$script" ]; then
    ok "registered Codex hook exists: $script"
    registered="${registered}${script}"$'\n'
  else
    ng "registered Codex hook is missing: $script"
  fi
done < <(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | .command | scan("~/.codex/hooks/([A-Za-z0-9._-]+)")[]] | .[]' "$CONFIG")

while IFS= read -r path; do
  script="${path##*/}"
  case $'\n'"$registered" in
    *$'\n'"$script"$'\n'*) ok "Codex hook is registered: $script" ;;
    *) ng "Codex hook is not registered: $script" ;;
  esac
done < <(rg --files "$REPO/codex/hooks" -g '!*.test.*')

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
