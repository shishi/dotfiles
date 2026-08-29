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

assert_jq "one SessionStart group" '((.hooks.SessionStart // []) | length) == 1'
assert_jq "SessionStart matcher is exact" '.hooks.SessionStart[0].matcher == "startup|resume|clear|compact"'
assert_jq "one SessionStart handler" '((.hooks.SessionStart[0].hooks // []) | length) == 1'
assert_jq "SessionStart invokes the shared injector" \
  '.hooks.SessionStart[0].hooks[0].command == "bash ~/.agents/hooks/inject-memory.sh ~/.codex/memory"'
assert_jq "SessionStart Windows command is exact" \
  '(.hooks.SessionStart[0].hooks[0].commandWindows | test("^& '\''[^'\'']*bash\\.exe'\'' -c '\''~/.agents/hooks/inject-memory\\.sh ~/.codex/memory'\''$"))'
assert_jq "SessionStart context limit is 10000" \
  '.hooks.SessionStart[0].hooks[0].additionalContextLimit == 10000'
assert_jq "one PreToolUse Bash group" '((.hooks.PreToolUse // []) | length) == 1 and .hooks.PreToolUse[0].matcher == "Bash"'
assert_jq "PreToolUse keeps the git push guard" \
  '.hooks.PreToolUse[0].hooks[0].command == "bash ~/.agents/hooks/git-push-guard.sh"'
assert_jq "PreToolUse Windows keeps the shared git push guard" \
  '(.hooks.PreToolUse[0].hooks[0].commandWindows | test("-c '\''~/.agents/hooks/git-push-guard\\.sh'\''$"))'
assert_jq "one UserPromptSubmit approval recorder" \
  '((.hooks.UserPromptSubmit // []) | length) == 1 and .hooks.UserPromptSubmit[0].hooks[0].command == "bash ~/.agents/hooks/git-push-guard.sh --record-approval"'
assert_jq "UserPromptSubmit Windows approval recorder is exact" \
  '(.hooks.UserPromptSubmit[0].hooks[0].commandWindows | test("^& '\''[^'\'']*bash\\.exe'\'' -c '\''~/.agents/hooks/git-push-guard\\.sh --record-approval'\''$"))'
assert_jq "every handler has commandWindows" \
  '([.hooks | to_entries[] | .value[] | .hooks[] | .commandWindows | select((type != "string") or (length == 0))] | length) == 0'
assert_jq "every Windows handler starts with call operator" \
  '([.hooks | to_entries[] | .value[] | .hooks[] | .commandWindows | select(test("^& ") | not)] | length) == 0'
assert_jq "every Windows handler invokes bash.exe" \
  '([.hooks | to_entries[] | .value[] | .hooks[] | .commandWindows | select(test("bash\\.exe") | not)] | length) == 0'
assert_jq "no Windows handler invokes the WSL launcher" \
  '([.hooks | to_entries[] | .value[] | .hooks[] | .commandWindows | select(test("System32[/\\\\]bash\\.exe"; "i"))] | length) == 0'
assert_jq "every Windows handler passes -c as a token" \
  '([.hooks | to_entries[] | .value[] | .hooks[] | .commandWindows | select(test("(^|[[:space:]])-c([[:space:]]|$)") | not)] | length) == 0'
assert_jq "no Windows handler starts a login shell" \
  '([.hooks | to_entries[] | .value[] | .hooks[] | .commandWindows | select(test("(^|[[:space:]])-[A-Za-z]*l[A-Za-z]*([[:space:]]|$)"))] | length) == 0'

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
