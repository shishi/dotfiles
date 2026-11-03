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
check "stop moves the turn to blocked" "[ \"\$(gate_field g1 t1 phase)\" = blocked ]"
out=$(printf '{"session_id":"g1","turn_id":"t1","stop_hook_active":false}' | bash "$HOOK" stop)
check "a blocked turn is not blocked twice" "[ -z \"\$out\" ]"
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
check "held does not show a resolved turn" "bash '$HOOK' held r3 | grep -q '回収できる原文は無い'"
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
out=$(printf '{"session_id":"c1"}' | PATH="$CODEXBIN:$PATH" bash "$HOOK" session-end)
check "session end removes the registration" "[ ! -e '$REG/c1' ]"
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
