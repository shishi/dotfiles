#!/usr/bin/env bash
# 監視 hook の共通処理 (間隔・状態の置き場所・会話記録の抜粋) を確かめる。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
work=$(mktemp -d "${TMPDIR:-/tmp}/task-monitor-common-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
export TASK_MONITOR_STATE_DIR="$work/state"
. "$HOOK_DIR/lib/task-monitor-common.sh"

fail() { echo "not ok: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
has() { grep -qF -- "$2" <<<"$1" || fail "$3: '$2' が無い: $1"; }
lacks() { ! grep -qF -- "$2" <<<"$1" || fail "$3: '$2' がある: $1"; }

[ "$(tm_interval 0) $(tm_interval 1) $(tm_interval 2) $(tm_interval 7)" = "10 20 40 40" ] || fail "間隔"
ok "間隔は 10・20・40・40 分"

d=$(tm_state_dir claude s1)
[ "$d" = "$work/state/claude/s1" ] && [ -d "$d" ] || fail "状態の置き場所: $d"
ok "状態の置き場所をセッションごとに作る"

cat > "$work/claude.jsonl" <<'EOF'
{"type":"assistant","sessionId":"x","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"1 failure"}]}}
not json
{"type":"attachment","sessionId":"x","attachment":{"type":"hook"}}
{"type":"event_msg","payload":{"type":"token_count"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"retrying"}]}}
EOF
out=$(tm_excerpt "$work/claude.jsonl")
has "$out" "[tool] Bash" "Claude の会話記録"
has "$out" "npm test" "Claude の会話記録"
has "$out" "[result] 1 failure" "Claude の会話記録"
has "$out" "[text] retrying" "Claude の会話記録"
lacks "$out" '{"type"' "Claude の会話記録"
ok "Claude の会話記録を操作と本文の行にする"

cat > "$work/codex.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"x"}}
{"type":"response_item","payload":{"type":"function_call","name":"wait_agent","arguments":"{\"timeout_ms\":10000}"}}
{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"text(await tools.write_stdin({session_id:1}))"}}
{"type":"response_item","payload":{"type":"function_call_output","output":"Wait timed out."}}
{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"still building"}]}}
EOF
out=$(tm_excerpt "$work/codex.jsonl")
has "$out" "[tool] wait_agent" "Codex の rollout"
has "$out" "[tool] exec" "Codex の rollout"
has "$out" "[result] Wait timed out." "Codex の rollout"
has "$out" "[text] still building" "Codex の rollout"
ok "Codex の rollout を操作と本文の行にする"

out=$(tm_excerpt "$work/claude.jsonl" 8)
[ "${#out}" -le 8 ] || fail "長さの上限: ${#out}"
ok "抜粋は指定した長さで切る"
