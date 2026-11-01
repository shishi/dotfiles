#!/usr/bin/env bash
# 出力ゲートの Codex 用 hook が、中継の起動・設定の書き戻し・委譲の登録を行うことを確かめる。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/agent-shared/hooks/output-gate-codex.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/output-gate-hook.XXXXXX")"
export XDG_STATE_HOME="$TMP/state" CODEX_HOME="$TMP/codex"
mkdir -p "$CODEX_HOME"
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
PORT=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
failures=0

relay_pid() {
  curl -s "http://127.0.0.1:$PORT/__gate/version" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["pid"])' 2>/dev/null
}

cleanup() {
  local pid
  pid=$(relay_pid)
  if [ -n "$pid" ]; then
    if command -v taskkill >/dev/null 2>&1; then taskkill //PID "$pid" //F >/dev/null 2>&1; else kill "$pid" 2>/dev/null; fi
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

check() {
  if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi
}

out=$(bash "$HOOK" enable "$PORT")
check "enable writes the base url line" "grep -q 'openai_base_url = \"http://127.0.0.1:$PORT/backend-api/codex\"' '$CODEX_HOME/config.toml'"
check "enable writes the feature lines" "grep -q '^enable_request_compression = false' '$CODEX_HOME/config.toml'"
check "enable starts the relay" "[ -n \"\$(relay_pid)\" ]"

# pull や checkout で行が消えた状態から、次の入力の hook が書き戻す。
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' | bash "$HOOK" prompt)
check "prompt restores the lines" "grep -q 'openai_base_url' '$CODEX_HOME/config.toml'"
check "prompt reports the restore" "printf '%s' \"\$out\" | grep -q systemMessage"
out=$(printf '{"session_id":"s1"}' | bash "$HOOK" prompt)
check "prompt is silent when nothing changed" "[ -z \"\$out\" ]"

out=$(printf '{"session_id":"child-1"}' | AGENT_DELEGATED_SESSION=1 bash "$HOOK" session-start)
check "delegated session is registered" "[ -f '$XDG_STATE_HOME/output-gate/relay/delegated/child-1' ]"
out=$(printf '{"session_id":"child-1"}' | AGENT_DELEGATED_SESSION=1 bash "$HOOK" session-end)
check "delegated session is removed at the end" "[ ! -e '$XDG_STATE_HOME/output-gate/relay/delegated/child-1' ]"
out=$(printf '{"session_id":"../../x"}' | AGENT_DELEGATED_SESSION=1 bash "$HOOK" session-start)
check "unsafe session ids are not used as paths" "[ ! -e '$XDG_STATE_HOME/output-gate/x' ] && [ ! -e '$XDG_STATE_HOME/x' ]"

# 行が無い状態で設定を読んで始まったセッション (起動・resume) は中継を通らない。止めて起動し直させる。
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"s2","source":"startup"}' | bash "$HOOK" session-start)
check "session started without the lines is stopped" "printf '%s' \"\$out\" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d[\"continue\"] is False and d[\"stopReason\"]'"
check "hook output is ASCII JSON" "printf '%s' \"\$out\" | LC_ALL=C grep -q '^[[:print:]]*$'"
out=$(printf '{"session_id":"s2"}' | bash "$HOOK" prompt)
check "later prompts of that session are stopped too" "printf '%s' \"\$out\" | grep -q '\"continue\": *false'"
out=$(printf '{"session_id":"s3"}' | bash "$HOOK" prompt)
check "other sessions are not stopped" "! printf '%s' \"\$out\" | grep -q '\"continue\"'"
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"s4","source":"compact"}' | bash "$HOOK" session-start)
check "compaction inside a running session is not stopped" "! printf '%s' \"\$out\" | grep -q '\"continue\"'"
# /clear と fork は設定を読み直して新しいスレッドを始めるので、行が無ければ中継を通らない。
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"s6","source":"clear"}' | bash "$HOOK" session-start)
check "a cleared thread started without the lines is stopped" "printf '%s' \"\$out\" | grep -q '\"continue\": *false'"
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"child-2","source":"startup"}' | AGENT_DELEGATED_SESSION=1 bash "$HOOK" session-start)
check "delegated sessions are not stopped" "! printf '%s' \"\$out\" | grep -q '\"continue\"'"
out=$(printf '{"session_id":"s2"}' | bash "$HOOK" session-end)
check "session end clears the stop" "[ ! -e '$XDG_STATE_HOME/output-gate/relay/unrouted/s2' ]"
# 行を書けない設定 (TOML として読めない) で始まったセッションも中継を通らないので止める。
printf 'model = \n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"s5","source":"startup"}' | bash "$HOOK" session-start)
check "session whose config cannot be written is stopped" "printf '%s' \"\$out\" | grep -q '\"continue\": *false'"
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"

out=$(bash "$HOOK" disable)
check "disable removes the lines" "! grep -q 'openai_base_url' '$CODEX_HOME/config.toml'"
check "disable keeps other lines" "grep -q '^hooks = true' '$CODEX_HOME/config.toml'"
out=$(printf '{"session_id":"s1"}' | bash "$HOOK" prompt)
check "prompt does not restore while disabled" "! grep -q 'openai_base_url' '$CODEX_HOME/config.toml'"

[ "$failures" -eq 0 ] || exit 1
