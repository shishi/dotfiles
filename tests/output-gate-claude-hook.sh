#!/usr/bin/env bash
# 出力ゲートの Claude Code 側の入口 (output-gate-claude.sh) の切り替えと、Python を起動しない早い経路を確かめる。
# 検査と表示の置き換えそのものは tests/output-gate-claude-hook.py が確かめる。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/agent-shared/hooks/output-gate-claude.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/output-gate-claude-hook.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export XDG_STATE_HOME="$TMP/state"
unset AGENT_DELEGATED_SESSION
failures=0

check() {
  if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi
}

# Windows の Python に渡すパスは、Git Bash の /tmp 形式を変換する (JSON の中の値は自動では変換されない)。
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# 検査処理の代わりに、呼ばれたことを記録する。
cat >"$TMP/checker.py" <<EOF
import json, sys
payload = json.load(sys.stdin)
open(r'$(native "$TMP/called")', 'a').write('x')
print(json.dumps({"status": "checked", "text": payload["draft"], "reason": None, "applied": 0}))
EOF
export OUTPUT_GATE_CHECK_CMD="[\"python3\", \"-I\", \"$(native "$TMP/checker.py")\"]"
event='{"session_id":"s1","transcript_path":"","hook_event_name":"MessageDisplay","turn_id":"t1","message_id":"m1","index":0,"final":true,"delta":"x"}'
# 回答ごとの扱いは message_id ごとに決まるため、別の回答の呼び出しは message_id を替えて作る。
event_of() { printf '%s' "${event//\"m1\"/\"$1\"}"; }

out=$(printf '%s' "$event" | bash "$HOOK" display)
check "disabled machines do nothing" "[ -z \"\$out\" ] && [ ! -e '$TMP/called' ]"

out=$(bash "$HOOK" enable)
check "enable turns the gate on" "[ -e '$XDG_STATE_HOME/output-gate/claude-enabled' ]"
out=$(printf '%s' "$event" | bash "$HOOK" display)
check "enabled machines check the answer" "printf '%s' \"\$out\" | grep -q displayContent && [ -e '$TMP/called' ]"

rm -f "$TMP/called"
mkdir -p "$XDG_STATE_HOME/output-gate/claude-mod" && printf t1 >"$XDG_STATE_HOME/output-gate/claude-mod/s1"
out=$(event_of m3 | bash "$HOOK" display)
check "sessions where the mod runs are left to the mod" "[ -z \"\$out\" ] && [ ! -e '$TMP/called' ]"

# 印が新しいセッションでは Python を起動しない (MessageDisplay は行ごとに呼ばれるため)。
mkdir -p "$TMP/fakebin"
for name in python3 python; do
  printf '#!/bin/sh\n: >"%s"\nexit 0\n' "$TMP/python-started" >"$TMP/fakebin/$name"
  chmod +x "$TMP/fakebin/$name"
done
out=$(event_of m4 | PATH="$TMP/fakebin:$PATH" bash "$HOOK" display)
check "a marker of this turn skips Python" "[ ! -e '$TMP/python-started' ]"
# 対話 CLI の MessageDisplay の turn_id は mod の turnId と別の値なので、印の中身によらず Python を起動しない。
printf mod-turn >"$XDG_STATE_HOME/output-gate/claude-mod/s1"
out=$(event_of m5 | PATH="$TMP/fakebin:$PATH" bash "$HOOK" display)
check "a marker naming another turn id also skips Python" "[ ! -e '$TMP/python-started' ]"
# 最初の呼び出しで mod に任せた回答 (m5) は、途中で印が消えても最後まで Python を起動しない。
rm -f "$XDG_STATE_HOME/output-gate/claude-mod/s1"
out=$(event_of m5 | PATH="$TMP/fakebin:$PATH" bash "$HOOK" display)
check "a message left to the mod stays with it after the marker is gone" "[ ! -e '$TMP/python-started' ]"
printf mod-turn >"$XDG_STATE_HOME/output-gate/claude-mod/s1"
# 印が無いときに貯め始めた回答は、途中で印が現れても最後まで本体が扱う (貯めた行を失わない)。
mkdir -p "$XDG_STATE_HOME/output-gate/claude-display/s1" && printf hold >"$XDG_STATE_HOME/output-gate/claude-display/s1/m2.how"
out=$(event_of m2 | PATH="$TMP/fakebin:$PATH" bash "$HOOK" display)
check "a message held before the marker appeared still goes to Python" "[ -e '$TMP/python-started' ]"
rm -f "$TMP/python-started" "$XDG_STATE_HOME/output-gate/claude-display/s1/m2.how"

out=$(bash "$HOOK" disable)
check "disable turns the gate off" "[ ! -e '$XDG_STATE_HOME/output-gate/claude-enabled' ]"

[ "$failures" -eq 0 ] || exit 1
