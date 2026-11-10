#!/usr/bin/env bash
# kata の完了確認 hook と kata-active を、偽の判定役と最小の会話記録で確かめる。
set -eu

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HOOK_DIR/kata-completion.sh"
ACTIVE="$HOOK_DIR/../bin/kata-active"
work=$(mktemp -d "${TMPDIR:-/tmp}/kata-completion-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
export KATA_STATE_DIR="$work/state" TASK_MONITOR_STATE_DIR="$work/task-monitor"
export CLAUDE_CODE_SESSION_ID=s1 CODEX_THREAD_ID=c1
printf '# Plan\n## Task 1\n' > "$work/plan.md"
printf 'Task 1: verified (review pending)\n' > "$work/progress.md"
T="$work/transcript.jsonl"
cat > "$T" <<'EOF'
{"type":"user","message":{"content":"最初の依頼"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"make test"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"続けて"}],"internal_chat_message_metadata_passthrough":{"content_item_metadata":[{"provenance":{"type":"user"}}]}}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<hook_prompt>差し戻し</hook_prompt>"}],"internal_chat_message_metadata_passthrough":{"content_item_metadata":[{"provenance":{"type":"harness","hook":true}}]}}}
{"type":"user","isMeta":true,"message":{"content":"注入された指示"}}
EOF

fail() { echo "not ok: $1" >&2; exit 1; }
ok() { echo "ok: $1"; }
# 判定役の代わり: 受け取った入力を残し、JUDGE_STATUS の判定を claude -p の JSON 出力の形で返す
cat > "$work/judge.sh" <<'EOF'
cat > "$JUDGE_INPUT"
[ "$JUDGE_STATUS" = fail ] && exit 1
jq -cn --arg s "$JUDGE_STATUS" '{is_error:false, subtype:"success", structured_output:{status:$s, reason:"テストの理由"}}'
EOF
export KATA_COMPLETION_JUDGE="bash $work/judge.sh" JUDGE_INPUT="$work/judge-input"
# stop <判定> [追加の入力 JSON] [CLI]。同じターンの 2 回目以降の Stop は stop_hook_active が true になる
stop() {
  rm -f "$JUDGE_INPUT"
  jq -cn --arg t "$T" "{session_id:\"s1\", cwd:\"/\", transcript_path:\$t, last_assistant_message:\"Task 1 を終えました\"} + ${2:-{\}}" |
    JUDGE_STATUS=$1 bash "$HOOK" "${3:-claude}" 2>/dev/null
}
again='{stop_hook_active:true}'
marked() { [ -f "$work/state/claude/s1/plan" ]; }

[ -z "$(stop continue)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "記録が無いのに判定した"
ok "記録が無いセッションでは判定役を呼ばずに止める"

bash "$ACTIVE" claude start "$work/plan.md" >/dev/null
[ "$(bash "$ACTIVE" claude status)" = "$(realpath "$work/plan.md")" ] || fail "start の記録"
CLAUDE_CODE_SESSION_ID=other bash "$ACTIVE" claude status | grep -q 記録はありません || fail "別セッションに記録が見える"
CODEX_THREAD_ID=c1 bash "$ACTIVE" codex status | grep -q 記録はありません || fail "Claude の記録が Codex のセッションに見える"
ok "kata-active は指定した CLI のこのセッションにだけ計画を記録する"

out=$(stop continue)
[ "$(jq -r .decision <<<"$out")" = block ] || fail "continue で差し戻さない: $out"
grep -qF "$(realpath "$work/plan.md")" <<<"$out" && grep -qF テストの理由 <<<"$out" || fail "差し戻しの理由: $out"
for want in "## Task 1" "Task 1: verified" "[tool] Bash"; do
  grep -qF -- "$want" "$JUDGE_INPUT" || fail "判定役への入力に '$want' が無い"
done
# 見出しの次の行に、その欄の値が入っている
after() { sed -n "/^$1:\$/{n;p;q}" "$JUDGE_INPUT"; }
[ "$(after "LAST USER MESSAGE")" = 続けて ] || fail "最後の利用者の発言: $(after "LAST USER MESSAGE")"
[ "$(after "FINAL MESSAGE")" = "Task 1 を終えました" ] || fail "最後の応答: $(after "FINAL MESSAGE")"
grep -qF -e 注入された指示 -e 差し戻し <(sed -n '/LAST USER MESSAGE:/,/RECENT ACTIVITY:/p' "$JUDGE_INPUT") && fail "注入された指示や hook の差し戻しを利用者の発言として渡した"
ok "未完了なら計画・進捗・直近の発言・最後の応答を判定させて差し戻す"

[ -z "$(stop waiting_on_human)" ] && marked || fail "本人待ちで止めない・記録を消した"
[ ! -e "$work/state/claude/s1/blocks" ] || fail "本人待ちで連続回数を数え直さない"
ok "本人の判断待ちなら記録を残して止める"

[ -z "$(stop fail)" ] && marked || fail "判定役の失敗で差し戻した"
ok "判定役が失敗したら止める"

[ -n "$(stop continue)" ] || fail "ターン最初の Stop で差し戻さない"
for _ in $(seq 9); do [ -n "$(stop continue "$again")" ] || fail "上限前に止めた"; done
[ -z "$(stop continue "$again")" ] && [ ! -e "$JUDGE_INPUT" ] || fail "連続 10 回の後も差し戻した"
[ -n "$(stop continue "$again")" ] || fail "上限で止めた後に数え直さない"
for _ in $(seq 5); do stop continue "$again" >/dev/null; done
[ -n "$(stop continue)" ] && [ "$(cat "$work/state/claude/s1/blocks")" = 1 ] || fail "利用者の新しいターンで数え直さない"
ok "差し戻しが同じターンで連続 10 回続いたら止め、利用者の新しいターンでは数え直す"

[ -z "$(stop continue '{background_tasks:[{id:"b1", type:"subagent"}]}')" ] && [ ! -e "$JUDGE_INPUT" ] || fail "Claude のバックグラウンド待ちを差し戻した"
mkdir -p "$TASK_MONITOR_STATE_DIR/codex/s1/running" && : > "$TASK_MONITOR_STATE_DIR/codex/s1/running/agent-x"
mkdir -p "$work/state/codex/s1" && cp "$work/state/claude/s1/plan" "$work/state/codex/s1/plan"
[ -z "$(stop continue '{}' codex)" ] && [ ! -e "$JUDGE_INPUT" ] || fail "Codex のバックグラウンド待ちを差し戻した"
rm -rf "$TASK_MONITOR_STATE_DIR/codex/s1/running"/*
[ -n "$(stop continue '{}' codex)" ] || fail "Codex で待つものが無いのに差し戻さない"
rm -rf "$work/state/codex"
ok "バックグラウンドのタスクを待つターン終了は判定しない"

[ -z "$(stop complete)" ] && ! marked || fail "完了で記録を消さない"
ok "完了なら記録を消して止める"

bash "$ACTIVE" claude start "$work/plan.md" >/dev/null && bash "$ACTIVE" claude done >/dev/null && ! marked || fail "done で消えない"
CLAUDE_CODE_SESSION_ID= bash "$ACTIVE" claude start "$work/plan.md" 2>/dev/null && fail "セッション ID 無しで記録した"
bash "$ACTIVE" claude start "$work/none.md" 2>/dev/null && fail "無い計画ファイルを記録した"
ok "kata-active done で消え、セッション ID や計画ファイルが無ければ失敗する"

bash "$ACTIVE" claude start "$work/plan.md" >/dev/null
{ head -c 30000 /dev/zero | tr '\0' x; printf '\n## Task 9: 末尾の task\n'; } >> "$work/plan.md"
stop continue >/dev/null
grep -qF "Task 9: 末尾の task" "$JUDGE_INPUT" || fail "長い計画の末尾の task を判定役へ渡さない"
ok "長い計画も末尾の task まで判定役へ渡す"

mv "$work/plan.md" "$work/plan.gone"
[ -z "$(stop continue)" ] && [ ! -e "$JUDGE_INPUT" ] && ! marked || fail "計画ファイルが消えた記録で判定した"
ok "計画ファイルが消えていたら記録を消して止める"
