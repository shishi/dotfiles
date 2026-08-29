#!/usr/bin/env bash
# enforce-continuation.sh が毎ターンの継続監査を Claude/Codex へ注入する契約を検証する。
set -u

HOOK_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)"
REPO="$(cd "$HOOK_DIR/../.." && pwd -P)"
HOOK="$HOOK_DIR/enforce-continuation.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

out=$(printf '{"hook_event_name":"UserPromptSubmit"}' | bash "$HOOK" 2>/dev/null)
rc=$?

if [ "$rc" -eq 0 ]; then
  ok "hook exits successfully"
else
  ng "hook exits successfully (exit=$rc)"
fi

if printf '%s' "$out" | jq -e '
  .hookSpecificOutput.hookEventName == "UserPromptSubmit"
  and (.hookSpecificOutput.additionalContext | contains("必要があると報告しただけでターンを終えるな"))
  and (.hookSpecificOutput.additionalContext | contains("問い合わせで代替するな"))
  and (.hookSpecificOutput.additionalContext | contains("未完了タスクが 1 件でもあれば"))
  and (.hookSpecificOutput.additionalContext | contains("トークン消費"))
  and (.hookSpecificOutput.additionalContext | contains("停止してよいのは"))
' >/dev/null 2>&1; then
  ok "hook injects the continuation audit as UserPromptSubmit context"
else
  ng "hook injects the continuation audit as UserPromptSubmit context"
fi

if jq -e '
  ([.hooks.UserPromptSubmit[]?.hooks[]?
    | select(.command == "bash ~/.agents/hooks/enforce-continuation.sh")]
   | length) == 1
' "$REPO/claude/settings.json" >/dev/null; then
  ok "Claude runs the shared continuation hook on every user prompt"
else
  ng "Claude runs the shared continuation hook on every user prompt"
fi

if jq -e '
  ([.hooks.UserPromptSubmit[]?.hooks[]?
    | select(.command == "bash ~/.agents/hooks/enforce-continuation.sh")]
   | length) == 1
' "$REPO/codex/hooks.json" >/dev/null; then
  ok "Codex runs the shared continuation hook on every user prompt"
else
  ng "Codex runs the shared continuation hook on every user prompt"
fi

if jq -e '
  ([.hooks.UserPromptSubmit[]?.hooks[]?
    | select(.command == "bash ~/.agents/hooks/enforce-continuation.sh")
    | .commandWindows]
   == ["& (Join-Path $HOME '\''.agents/bin/invoke-git-bash-hook.ps1'\'') '\''~/.agents/hooks/enforce-continuation.sh'\''"])
' "$REPO/codex/hooks.json" >/dev/null; then
  ok "Codex Windows uses the portable launcher for the continuation hook"
else
  ng "Codex Windows uses the portable launcher for the continuation hook"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
