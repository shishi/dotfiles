#!/usr/bin/env bash
# Claude Code と Codex の transcript からユーザー発言を同じ規則で読む契約を検証する。
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/response-rules-gate.sh"
PASS=0
FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/response-rules-gate.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

run_gate() {
  local transcript="$1" response="$2"
  jq -n --arg transcript "$transcript" --arg response "$response" \
    '{transcript_path:$transcript,last_assistant_message:$response}' \
    | bash "$HOOK"
}

cat >"$TMP/codex-vocabulary.jsonl" <<'EOF'
{"type":"event_msg","payload":{"type":"user_message","message":"API を使って"}}
EOF
out=$(run_gate "$TMP/codex-vocabulary.jsonl" 'API を使ったよ。')
if printf '%s' "$out" | jq -e 'type == "object" and length == 0' >/dev/null; then
  ok "Codex transcriptのユーザー語彙を定義済みとして扱う"
else
  ng "Codex transcriptのユーザー語彙を定義済みとして扱う"
fi

cat >"$TMP/codex-contradiction.jsonl" <<'EOF'
{"type":"event_msg","payload":{"type":"user_message","message":"それ矛盾してる"}}
EOF
out=$(run_gate "$TMP/codex-contradiction.jsonl" '説明は整合しています。')
if printf '%s' "$out" | jq -e '.decision == "block" and (.reason | contains("当時知っていたか"))' >/dev/null; then
  ok "Codex transcriptの直近ユーザー指摘を応答検査に使う"
else
  ng "Codex transcriptの直近ユーザー指摘を応答検査に使う"
fi

cat >"$TMP/codex-bootstrap.jsonl" <<'EOF'
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<INSTRUCTIONS>TDD を適用する</INSTRUCTIONS>"}]}}
{"type":"event_msg","payload":{"type":"user_message","message":"テストして"}}
EOF
out=$(run_gate "$TMP/codex-bootstrap.jsonl" 'TDD を採用したよ。')
if printf '%s' "$out" | jq -e '.decision == "block" and (.reason | contains("TDD"))' >/dev/null; then
  ok "Codex bootstrapをユーザー語彙に混ぜない"
else
  ng "Codex bootstrapをユーザー語彙に混ぜない"
fi

cat >"$TMP/claude-vocabulary.jsonl" <<'EOF'
{"type":"user","message":{"content":"API を使って"}}
EOF
out=$(run_gate "$TMP/claude-vocabulary.jsonl" 'API を使ったよ。')
if printf '%s' "$out" | jq -e 'type == "object" and length == 0' >/dev/null; then
  ok "Claude Code transcriptの既存契約を維持する"
else
  ng "Claude Code transcriptの既存契約を維持する"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
