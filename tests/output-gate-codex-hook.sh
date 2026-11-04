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

FIRST="$TMP/first"
mkdir -p "$FIRST/agent-shared/hooks" "$FIRST/agent-shared/bin" "$FIRST/codex" "$FIRST/bin"
cp "$HOOK" "$FIRST/agent-shared/hooks/output-gate-codex.sh"
cp "$REPO/agent-shared/bin/output-gate-codex-config.py" "$FIRST/agent-shared/bin/output-gate-codex-config.py"
cat >"$FIRST/agent-shared/bin/output-gate-relay.py" <<'EOF'
import json
def kill_tree(process):
    process.kill()
    process.wait()
if __name__ == '__main__':
    print(json.dumps({'state': 'running'}))
EOF
printf '#!/bin/sh\nexit 1\n' >"$FIRST/bin/codex"
chmod +x "$FIRST/bin/codex"
printf 'model = "m"\n' >"$FIRST/codex/config.toml"
first_out=$(printf '{"session_id":"first","source":"startup"}' | XDG_STATE_HOME="$FIRST/state" CODEX_HOME="$FIRST/codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start)
check "first session enables gate without setup" "python3 -I -c 'import json,sys; assert json.load(open(sys.argv[1]))[\"enabled\"] is True' '$FIRST/state/output-gate/codex.json' && grep -q '^openai_base_url' '$FIRST/codex/config.toml'"
check "first session is stopped before using the old endpoint" "printf '%s' \"\$first_out\" | python3 -I -c 'import json,sys; assert json.load(sys.stdin)[\"continue\"] is False'"
check "first session asks for all sessions to restart" "printf '%s' \"\$first_out\" | python3 -I -c 'import json,sys; s=json.load(sys.stdin)[\"stopReason\"]; assert \"すべて\" in s and \"再起動\" in s'"
check "first session explains shared server and resending input politely" "printf '%s' \"\$first_out\" | python3 -I -c 'import json,sys; s=json.load(sys.stdin)[\"stopReason\"]; assert \"app-server\" in s and \"送り直\" in s and \"ください\" in s'"
check "first setup reports the configuration change politely" "printf '%s' \"\$first_out\" | python3 -I -c 'import json,sys; assert json.load(sys.stdin)[\"systemMessage\"].endswith(\"ました。\")'"
printf '{"session_id":"first","source":"resume"}' | XDG_STATE_HOME="$FIRST/state" CODEX_HOME="$FIRST/codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start >/dev/null
resumed_prompt=$(printf '{"session_id":"first"}' | XDG_STATE_HOME="$FIRST/state" CODEX_HOME="$FIRST/codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" prompt)
check "resumed session can use the configured endpoint" "! printf '%s' \"\$resumed_prompt\" | grep -q '\"continue\"'"
next_out=$(printf '{"session_id":"next","source":"startup"}' | XDG_STATE_HOME="$FIRST/state" CODEX_HOME="$FIRST/codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start)
check "next session continues after reading the new endpoint" "! printf '%s' \"\$next_out\" | grep -q '\"continue\"'"
XDG_STATE_HOME="$FIRST/state" CODEX_HOME="$FIRST/codex" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" disable >/dev/null
disabled_before=$(cat "$FIRST/state/output-gate/codex.json")
printf '{"session_id":"disabled","source":"startup"}' | XDG_STATE_HOME="$FIRST/state" CODEX_HOME="$FIRST/codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start >/dev/null
check "explicitly disabled gate stays disabled" "[ \"\$(cat '$FIRST/state/output-gate/codex.json')\" = \"\$disabled_before\" ] && ! grep -q '^openai_base_url' '$FIRST/codex/config.toml'"
mkdir -p "$FIRST/child-codex" "$FIRST/bad-codex"
printf 'model = "m"\n' >"$FIRST/child-codex/config.toml"
printf '{"session_id":"child","source":"startup"}' | AGENT_DELEGATED_SESSION=1 XDG_STATE_HOME="$FIRST/child-state" CODEX_HOME="$FIRST/child-codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start >/dev/null
check "delegated sessions do not activate the gate" "[ ! -e '$FIRST/child-state/output-gate/codex.json' ] && ! grep -q '^openai_base_url' '$FIRST/child-codex/config.toml'"
printf 'model = \n' >"$FIRST/bad-codex/config.toml"
bad_out=$(printf '{"session_id":"bad","source":"startup"}' | XDG_STATE_HOME="$FIRST/bad-state" CODEX_HOME="$FIRST/bad-codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start)
check "failed automatic setup stops the session without marking it enabled" "[ ! -e '$FIRST/bad-state/output-gate/codex.json' ] && printf '%s' \"\$bad_out\" | python3 -I -c 'import json,sys; assert json.load(sys.stdin)[\"continue\"] is False'"
check "failed setup reports its cause and how to disable the gate" "printf '%s' \"\$bad_out\" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert \"disable\" in d[\"stopReason\"] and \"TOML\" in d[\"systemMessage\"]'"
check "failure explains restart after disabling" "printf '%s' \"\$bad_out\" | python3 -I -c 'import json,sys; assert \"再起動\" in json.load(sys.stdin)[\"stopReason\"]'"
bad_prompt=$(printf '{"session_id":"bad"}' | XDG_STATE_HOME="$FIRST/bad-state" CODEX_HOME="$FIRST/bad-codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" prompt)
check "failed initialization keeps later prompts stopped" "printf '%s' \"\$bad_prompt\" | python3 -I -c 'import json,sys; assert json.load(sys.stdin)[\"continue\"] is False'"
mkdir -p "$FIRST/no-python"
for name in python3 python; do
  printf '#!/bin/sh\nexit 1\n' >"$FIRST/no-python/$name"
  chmod +x "$FIRST/no-python/$name"
done
no_python=$(printf '{"session_id":"no-python","source":"startup"}' | XDG_STATE_HOME="$FIRST/no-python-state" CODEX_HOME="$FIRST/codex" PATH="$FIRST/no-python:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start)
check "missing Python stops initial session" "printf '%s' \"\$no_python\" | python3 -I -c 'import json,sys; assert json.load(sys.stdin)[\"continue\"] is False'"
check "missing Python provides a recovery procedure" "printf '%s' \"\$no_python\" | python3 -I -c 'import json,sys; assert \"docs/output-gate.md\" in json.load(sys.stdin)[\"stopReason\"]'"
mkdir -p "$FIRST/disabled-codex"
printf 'model = "m"\n' >"$FIRST/disabled-codex/config.toml"
printf '{"session_id":"disable-resume","source":"startup"}' | XDG_STATE_HOME="$FIRST/disabled-state" CODEX_HOME="$FIRST/disabled-codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start >/dev/null
XDG_STATE_HOME="$FIRST/disabled-state" CODEX_HOME="$FIRST/disabled-codex" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" disable >/dev/null
printf '{"session_id":"disable-resume","source":"resume"}' | XDG_STATE_HOME="$FIRST/disabled-state" CODEX_HOME="$FIRST/disabled-codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" session-start >/dev/null
disabled_prompt=$(printf '{"session_id":"disable-resume"}' | XDG_STATE_HOME="$FIRST/disabled-state" CODEX_HOME="$FIRST/disabled-codex" PATH="$FIRST/bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" prompt)
check "resuming after disabling does not keep the old stop" "! printf '%s' \"\$disabled_prompt\" | grep -q '\"continue\"'"

mkdir -p "$FIRST/daemon-codex" "$FIRST/daemon-bin"
printf 'model = "m"\n' >"$FIRST/daemon-codex/config.toml"
cat >"$FIRST/daemon-bin/codex" <<'EOF'
#!/bin/sh
case "$*" in
  "app-server daemon version") [ "${DAEMON_ABSENT:-}" != 1 ] ;;
  "app-server daemon restart")
    grep -q '^openai_base_url' "$CODEX_HOME/config.toml" || exit 2
    printf 'restart\n' >> "$DAEMON_CALLS"
    [ "${DAEMON_RESTART_FAIL:-}" != 1 ] || exit 1
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FIRST/daemon-bin/codex"
DAEMON_CALLS="$FIRST/daemon-calls" XDG_STATE_HOME="$FIRST/daemon-state" CODEX_HOME="$FIRST/daemon-codex" PATH="$FIRST/daemon-bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" enable >/dev/null
check "enabling updated settings restarts the shared daemon" "[ \"\$(wc -l < '$FIRST/daemon-calls' 2>/dev/null)\" = 1 ]"
DAEMON_CALLS="$FIRST/daemon-calls" XDG_STATE_HOME="$FIRST/daemon-state" CODEX_HOME="$FIRST/daemon-codex" PATH="$FIRST/daemon-bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" enable >/dev/null
check "unchanged enable does not restart the shared daemon" "[ \"\$(wc -l < '$FIRST/daemon-calls' 2>/dev/null)\" = 1 ]"
mkdir -p "$FIRST/daemon-fail-codex"
printf 'model = "m"\n' >"$FIRST/daemon-fail-codex/config.toml"
if DAEMON_RESTART_FAIL=1 DAEMON_CALLS="$FIRST/daemon-calls" XDG_STATE_HOME="$FIRST/daemon-fail-state" CODEX_HOME="$FIRST/daemon-fail-codex" PATH="$FIRST/daemon-bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" enable >"$FIRST/daemon-fail.log" 2>&1; then
  failures=$((failures + 1)); echo "FAIL: daemon restart failure is reported"
else
  check "daemon restart failure is reported" "grep -q '再起動できませんでした' '$FIRST/daemon-fail.log'"
fi
check "daemon restart failure retains enabled settings" "grep -q '^openai_base_url' '$FIRST/daemon-fail-codex/config.toml' && python3 -I -c 'import json,sys; assert json.load(open(sys.argv[1]))[\"enabled\"]' '$FIRST/daemon-fail-state/output-gate/codex.json'"
check "daemon restart failure still explains hook trust and answer recovery" "grep -q PreCompact '$FIRST/daemon-fail.log' && grep -q held '$FIRST/daemon-fail.log'"
mkdir -p "$FIRST/daemon-absent-codex"
printf 'model = "m"\n' >"$FIRST/daemon-absent-codex/config.toml"
absent_out=$(DAEMON_ABSENT=1 DAEMON_CALLS="$FIRST/daemon-calls" XDG_STATE_HOME="$FIRST/daemon-absent-state" CODEX_HOME="$FIRST/daemon-absent-codex" PATH="$FIRST/daemon-bin:$PATH" bash "$FIRST/agent-shared/hooks/output-gate-codex.sh" enable)
check "no daemon does not start one" "[ \"\$(wc -l < '$FIRST/daemon-calls')\" = 2 ] && printf '%s' \"\$absent_out\" | grep -q '使用中の場合'"

out=$(bash "$HOOK" enable "$PORT")
check "enable writes the base url line" "grep -q 'openai_base_url = \"http://127.0.0.1:$PORT/backend-api/codex\"' '$CODEX_HOME/config.toml'"
check "enable writes the feature lines" "grep -q '^enable_request_compression = false' '$CODEX_HOME/config.toml'"
check "enable starts the relay" "[ -n \"\$(relay_pid)\" ]"
check "enable names all hooks needed for recovery" "printf '%s' \"\$out\" | grep -q PreCompact && printf '%s' \"\$out\" | grep -q PreModelRequest"

mkdir -p "$TMP/bad-codex"
printf 'model = \n' >"$TMP/bad-codex/config.toml"
if XDG_STATE_HOME="$TMP/bad-state" CODEX_HOME="$TMP/bad-codex" bash "$HOOK" enable "$PORT" >"$TMP/bad-enable.log" 2>&1; then
  failures=$((failures + 1)); echo "FAIL: enable reports an unwritable configuration"
else
  echo "ok: enable reports an unwritable configuration"
fi
check "failed first enable does not leave the gate enabled" "[ ! -e '$TMP/bad-state/output-gate/codex.json' ]"
mkdir -p "$TMP/bad-state/output-gate"
printf '{"enabled": false, "port": 12345}\n' >"$TMP/bad-state/output-gate/codex.json"
XDG_STATE_HOME="$TMP/bad-state" CODEX_HOME="$TMP/bad-codex" bash "$HOOK" enable "$PORT" >"$TMP/bad-enable.log" 2>&1 || :
check "failed enable preserves the previous disabled state" "python3 -I -c 'import json,sys; assert json.load(open(sys.argv[1])) == {\"enabled\": False, \"port\": 12345}' '$TMP/bad-state/output-gate/codex.json'"
out=$(XDG_STATE_HOME="$TMP/optout-state" CODEX_HOME="$TMP/missing-codex" bash "$HOOK" disable)
check "disable before setup succeeds without a missing config warning" "! printf '%s' \"\$out\" | grep -Eq '外せ(ない|ません)'"

# pull や checkout で行が消えた状態から、次の入力の hook が書き戻す。
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' | bash "$HOOK" prompt)
check "prompt restores the lines" "grep -q 'openai_base_url' '$CODEX_HOME/config.toml'"
check "prompt reports the restore" "printf '%s' \"\$out\" | grep -q systemMessage"
out=$(printf '{"session_id":"s1"}' | bash "$HOOK" prompt)
check "prompt is silent when nothing changed" "[ -z \"\$out\" ]"

out=$(printf '{"session_id":"child-1"}' | AGENT_DELEGATED_SESSION=1 bash "$HOOK" session-start)
check "delegated session is registered" "[ -f '$XDG_STATE_HOME/output-gate/relay/delegated/child-1' ]"
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
# 行を書けない設定 (TOML として読めない) で始まったセッションも中継を通らないので止める。
printf 'model = \n' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"s5","source":"startup"}' | bash "$HOOK" session-start)
check "session whose config cannot be written is stopped" "printf '%s' \"\$out\" | grep -q '\"continue\": *false'"
printf 'model = "m"\n\n[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"

# ほかのプロセスが待受のポートを使っている: 原因と復旧手順を、セッションごとに 1 回だけ伝える。
BUSY_PORT=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -I -c 'import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(50); s.settimeout(0.5)
end = time.time() + 60
while time.time() < end:
    try:
        s.accept()[0].close()
    except socket.timeout:
        pass' "$BUSY_PORT" &
busy_pid=$!
sleep 1
saved_state=$(cat "$XDG_STATE_HOME/output-gate/codex.json")
printf '{"enabled": true, "port": %s}\n' "$BUSY_PORT" >"$XDG_STATE_HOME/output-gate/codex.json"
printf '{"session_id":"b0"}' | bash "$HOOK" prompt >/dev/null   # 設定の行をこのポートに合わせておく
out=$(printf '{"session_id":"b1","source":"startup"}' | bash "$HOOK" session-start)
message=$(printf '%s' "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("systemMessage", ""))' 2>/dev/null)
check "a busy port is reported with the recovery command" "printf '%s' \"\$message\" | grep -q 'output-gate-codex.sh disable'"
check "the port in the message has no stray CR" "printf '%s' \"\$message\" | grep -q '127.0.0.1:$BUSY_PORT で'"
out=$(printf '{"session_id":"b1"}' | bash "$HOOK" prompt)
check "the same session is not told twice" "[ -z \"\$out\" ]"
out=$(printf '{"session_id":"b2"}' | bash "$HOOK" prompt)
check "another session is told" "printf '%s' \"\$out\" | grep -q systemMessage"
kill "$busy_pid" 2>/dev/null
wait "$busy_pid" 2>/dev/null
printf '%s\n' "$saved_state" >"$XDG_STATE_HOME/output-gate/codex.json"

# PreModelRequest は Codex がモデルへの要求 (再試行を含む) のたびに待つ。中継を直せないときに再試行ごとに
# 秒単位を足さないよう、要求を待たせない async の hook にする (Codex はこの hook の標準出力を読まない)。
check "the PreModelRequest hook does not hold model requests" "python3 -I -c '
import json, sys
hooks = json.load(open(sys.argv[1], encoding=\"utf-8\"))[\"hooks\"][\"PreModelRequest\"]
gate = [h for g in hooks for h in g[\"hooks\"] if \"output-gate-codex.sh pre-model\" in h[\"command\"]]
assert gate and all(h.get(\"async\") is True for h in gate), gate
' '$REPO/codex/hooks.json'"

# ---- 差し戻し (Stop)・回収 (prompt・held)・続行の登録 (SessionStart) -------------------------------
GATE="$XDG_STATE_HOME/output-gate/relay/gate"
write_gate() {   # session turn json
  mkdir -p "$GATE/$1" && printf '%s' "$3" >"$GATE/$1/$2.json"
}
gate_field() {   # session turn field
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); v=d.get(sys.argv[2]); print("" if v is None else v)' "$GATE/$1/$2.json" "$3"
}
SUBSTITUTED='{"phase":"substituted","round":0,"findings":[],"agent_message":"AGENT-MSG","original":"RAW-ANSWER","display":"ORIGINAL-ANSWER UNMET-ITEMS","notice_marker":"m","created":9999999999}'

write_gate g1 t1 "$SUBSTITUTED"
out=$(printf '{"session_id":"g2","turn_id":"t1","stop_hook_active":false}' | bash "$HOOK" stop)
check "stop does not block another session's turn" "[ -z \"\$out\" ] && [ \"\$(gate_field g1 t1 phase)\" = substituted ]"
out=$(printf '{"session_id":"g1","turn_id":"t1","stop_hook_active":true}' | bash "$HOOK" stop)
check "stop blocks a substituted turn even when another hook blocked first" "printf '%s' \"\$out\" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d[\"decision\"] == \"block\" and d[\"reason\"] == \"AGENT-MSG\"'"
check "stop moves the turn to blocked and counts the send-back" "[ \"\$(gate_field g1 t1 phase)\" = blocked ] && [ \"\$(gate_field g1 t1 round)\" = 1 ]"
out=$(printf '{"session_id":"g1","turn_id":"t1","stop_hook_active":false}' | bash "$HOOK" stop)
check "a blocked turn is not blocked twice" "[ -z \"\$out\" ] && [ \"\$(gate_field g1 t1 round)\" = 1 ]"
# 直させた後の回答にも未達が残れば、中継がもう一度案内に差し替える (substituted)。Stop hook はそのたびに block する。
write_gate g1 t1 '{"phase":"substituted","round":1,"findings":[],"agent_message":"AGENT-MSG-2","original":"RAW-2","notice_marker":"m2","created":9999999999}'
out=$(printf '{"session_id":"g1","turn_id":"t1","stop_hook_active":true}' | bash "$HOOK" stop)
check "a turn substituted again is blocked again" "printf '%s' \"\$out\" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d[\"decision\"] == \"block\" and d[\"reason\"] == \"AGENT-MSG-2\"' && [ \"\$(gate_field g1 t1 phase)\" = blocked ] && [ \"\$(gate_field g1 t1 round)\" = 2 ]"
write_gate g1 t0 '{"phase":"resolved","round":1,"findings":[],"created":9999999999}'
out=$(printf '{"session_id":"g1","turn_id":"t0","stop_hook_active":false}' | bash "$HOOK" stop)
check "a resolved turn is not blocked" "[ -z \"\$out\" ]"
write_gate g1 t5 "$SUBSTITUTED"
out=$(printf '{"session_id":"g1","turn_id":"t5","stop_hook_active":false}' | bash "$HOOK" stop)
check "stop blocks a substituted turn with stop_hook_active false" "printf '%s' \"\$out\" | grep -q '\"decision\": *\"block\"'"

FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
for name in python3 python; do
  printf '#!/bin/sh\n: >"%s/python-ran"\nexit 1\n' "$TMP" >"$FAKEBIN/$name"
  chmod +x "$FAKEBIN/$name"
done
out=$(printf '{"session_id":"g1","turn_id":"none","stop_hook_active":false}' | PATH="$FAKEBIN:$PATH" bash "$HOOK" stop)
check "stop without a state is silent and does not start Python" "[ -z \"\$out\" ] && [ ! -e '$TMP/python-ran' ]"
saved_state=$(cat "$XDG_STATE_HOME/output-gate/codex.json")
printf '{"enabled": false, "port": 0}\n' >"$XDG_STATE_HOME/output-gate/codex.json"
write_gate g1 t6 "$SUBSTITUTED"
out=$(printf '{"session_id":"g1","turn_id":"t6","stop_hook_active":false}' | PATH="$FAKEBIN:$PATH" bash "$HOOK" stop)
check "stop on a disabled machine is silent and does not start Python" "[ -z \"\$out\" ] && [ ! -e '$TMP/python-ran' ]"
printf '%s\n' "$saved_state" >"$XDG_STATE_HOME/output-gate/codex.json"
rm -f "$GATE/g1/t6.json"

# 次のターンの入力で、利用者に届いていない原文と未達の項目を一度だけ表示する (状態は消さない)。
write_gate r1 t1 "$SUBSTITUTED"
out=$(printf '{"session_id":"r1","turn_id":"t1"}' | bash "$HOOK" prompt)
check "the same turn does not show the original" "! printf '%s' \"\$out\" | grep -q ORIGINAL-ANSWER"
out=$(printf '{"session_id":"other","turn_id":"t9"}' | bash "$HOOK" prompt)
check "another session does not show or mark the state" "! printf '%s' \"\$out\" | grep -q ORIGINAL-ANSWER && [ -z \"\$(gate_field r1 t1 shown)\" ]"
out=$(printf '{"session_id":"r1","turn_id":"t2"}' | bash "$HOOK" prompt)
message=$(printf '%s' "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("systemMessage", ""))' 2>/dev/null)
check "the recovery shows the rewritten answer, not the raw original" "! printf '%s' \"\$message\" | grep -q RAW-ANSWER"
check "the next turn shows the original and the unmet items" "printf '%s' \"\$message\" | grep -q ORIGINAL-ANSWER && printf '%s' \"\$message\" | grep -q UNMET-ITEMS"
check "the shown mark is set and the state is kept" "[ \"\$(gate_field r1 t1 shown)\" = True ] && [ \"\$(gate_field r1 t1 original)\" = RAW-ANSWER ] && [ \"\$(gate_field r1 t1 phase)\" = substituted ] && [ \"\$(gate_field r1 t1 round)\" = 0 ]"
out=$(printf '{"session_id":"r1","turn_id":"t3"}' | bash "$HOOK" prompt)
check "the original is not shown twice" "! printf '%s' \"\$out\" | grep -q ORIGINAL-ANSWER"
# blocked のまま止まったターン (block の前に hook が止まった・続けた作業の途中で中断した) も回収する。
write_gate r2 t1 '{"phase":"blocked","round":0,"findings":[],"agent_message":"AGENT-MSG","original":"RAW-B","display":"BLOCKED-ORIGINAL UNMET-B","notice_marker":"m","created":9999999999}'
out=$(printf '{"session_id":"r2","turn_id":"t2"}' | bash "$HOOK" prompt)
check "a turn left blocked is recovered on the next input" "printf '%s' \"\$out\" | grep -q BLOCKED-ORIGINAL && [ \"\$(gate_field r2 t1 shown)\" = True ]"
write_gate r3 t1 '{"phase":"resolved","round":1,"findings":[],"created":9999999999}'
out=$(printf '{"session_id":"r3","turn_id":"t2"}' | bash "$HOOK" prompt)
check "a resolved turn without the original shows nothing" "! printf '%s' \"\$out\" | grep -q systemMessage"
# Windows のコマンド行の上限 (32,767 文字) を超える原文も、表示できてから shown を付ける。
big=$(python3 -I -c 'print("BIG-" + "x" * 40000, end="")')
write_gate r4 t1 "{\"phase\":\"substituted\",\"round\":0,\"findings\":[],\"agent_message\":\"A\",\"original\":\"R\",\"display\":\"$big\",\"notice_marker\":\"m\",\"created\":9999999999}"
out=$(printf '{"session_id":"r4","turn_id":"t2"}' | bash "$HOOK" prompt)
message=$(printf '%s' "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("systemMessage", ""), end="")' 2>/dev/null)
check "a recovery longer than the command line limit is shown" "printf '%s' \"\$message\" | grep -q 'BIG-xxxx' && [ \${#message} -gt 40000 ] && [ \"\$(gate_field r4 t1 shown)\" = True ]"

# held: shown の印に関係なく表示し、消さない。session_id を渡すとそのセッションだけ。
out=$(bash "$HOOK" held)
check "held shows substituted and blocked originals even after they were shown" "printf '%s' \"\$out\" | grep -q ORIGINAL-ANSWER && printf '%s' \"\$out\" | grep -q BLOCKED-ORIGINAL"
out=$(bash "$HOOK" held r2)
check "held does not show a resolved turn" "bash '$HOOK' held r3 | grep -q '回収できる原文はありません'"
check "held with a session id shows only that session" "printf '%s' \"\$out\" | grep -q BLOCKED-ORIGINAL && ! printf '%s' \"\$out\" | grep -q ORIGINAL-ANSWER"
check "held keeps the states" "[ -f '$GATE/r1/t1.json' ] && [ -f '$GATE/r2/t1.json' ]"

# 続行の登録: app-server の hooks/list で出力ゲートの Stop hook が信頼済みのときだけ書く。
CODEXBIN="$TMP/codexbin"
mkdir -p "$CODEXBIN"
cat >"$CODEXBIN/fake-codex.py" <<'PY'
import json, os, sys
mode = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mode'), encoding='utf-8').read().strip()
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'called'), 'a').write('x')
if mode == 'fail':
    sys.exit(1)
for line in sys.stdin:
    message = json.loads(line)
    if message.get('id') == 1:
        print(json.dumps({'id': 1, 'result': {}}), flush=True)
    elif message.get('id') == 2:
        hook = {'eventName': 'stop', 'command': "bash ~/.agent-shared/hooks/output-gate-codex.sh stop",
                'enabled': True, 'trustStatus': 'trusted' if mode == 'trusted' else 'untrusted'}
        print(json.dumps({'id': 2, 'result': {'data': [{'cwd': '.', 'hooks': [hook]}]}}), flush=True)
        break
PY
printf '#!/bin/sh\nexec python3 -I "%s/fake-codex.py" "$@"\n' "$CODEXBIN" >"$CODEXBIN/codex"
chmod +x "$CODEXBIN/codex"
printf '@python -I "%%~dp0fake-codex.py" %%*\r\n' >"$CODEXBIN/codex.cmd"
REG="$XDG_STATE_HOME/output-gate/relay/continue"
echo trusted >"$CODEXBIN/mode"
out=$(printf '{"session_id":"c1","source":"startup","cwd":"."}' | PATH="$CODEXBIN:$PATH" bash "$HOOK" session-start)
check "a session whose Stop hook is trusted is registered" "[ -f '$REG/c1' ]"
echo untrusted >"$CODEXBIN/mode"
out=$(printf '{"session_id":"c2","source":"startup","cwd":"."}' | PATH="$CODEXBIN:$PATH" bash "$HOOK" session-start)
check "an untrusted Stop hook is not registered" "[ ! -e '$REG/c2' ]"
echo fail >"$CODEXBIN/mode"
out=$(printf '{"session_id":"c3","source":"startup","cwd":"."}' | PATH="$CODEXBIN:$PATH" bash "$HOOK" session-start)
check "a failed hooks/list does not register" "[ ! -e '$REG/c3' ]"
# compact は同じスレッドの中で続くので、登録を書き換えない。
echo trusted >"$CODEXBIN/mode"
printf '{"session_id":"c4","source":"startup","cwd":"."}' | PATH="$CODEXBIN:$PATH" bash "$HOOK" session-start >/dev/null
echo untrusted >"$CODEXBIN/mode"
printf '{"session_id":"c4","source":"compact","cwd":"."}' | PATH="$CODEXBIN:$PATH" bash "$HOOK" session-start >/dev/null
check "a compact session start keeps the registration" "[ -f '$REG/c4' ]"
# 起動し直しを求めるセッションは、信頼の確認 (app-server の起動) を省く (hook の時間制限に収めるため)。
rm -f "$CODEXBIN/called"
echo trusted >"$CODEXBIN/mode"
printf 'model = "m"

[features]
hooks = true
' >"$CODEX_HOME/config.toml"
out=$(printf '{"session_id":"c5","source":"startup","cwd":"."}' | PATH="$CODEXBIN:$PATH" bash "$HOOK" session-start)
check "a session told to restart skips the trust check" "printf '%s' \"\$out\" | grep -q '\"continue\": *false' && [ ! -e '$CODEXBIN/called' ] && [ ! -e '$REG/c5' ]"
check "the Stop hook is in hooks.json" "python3 -I -c '
import json, sys
hooks = json.load(open(sys.argv[1], encoding=\"utf-8\"))[\"hooks\"][\"Stop\"]
assert [h for g in hooks for h in g[\"hooks\"] if \"output-gate-codex.sh stop\" in h[\"command\"] and \"output-gate-codex.sh stop\" in h[\"commandWindows\"]]
' '$REPO/codex/hooks.json'"
out=$(bash "$HOOK" enable "$PORT")
check "enable explains re-trusting the hooks and held" "printf '%s' \"\$out\" | grep -q held && printf '%s' \"\$out\" | grep -q '24 時間'"

out=$(bash "$HOOK" disable)
check "disable removes the lines" "! grep -q 'openai_base_url' '$CODEX_HOME/config.toml'"
check "disable keeps other lines" "grep -q '^hooks = true' '$CODEX_HOME/config.toml'"
out=$(printf '{"session_id":"s1"}' | bash "$HOOK" prompt)
check "prompt does not restore while disabled" "! grep -q 'openai_base_url' '$CODEX_HOME/config.toml'"

[ "$failures" -eq 0 ] || exit 1
