#!/usr/bin/env bash
# ターンの依頼と差分を独立 reviewer が照合し、不要構造を block する契約を検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/agent-shared/hooks/task-necessity-gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/task-necessity-gate.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

git -C "$TMP" init -q
git -C "$TMP" config user.name test
git -C "$TMP" config user.email test@example.invalid
printf 'base\n' >"$TMP/code.txt"
printf 'base\n' >"$TMP/owned.txt"
printf 'base\n' >"$TMP/unrelated.txt"
git -C "$TMP" add code.txt owned.txt unrelated.txt
git -C "$TMP" -c commit.gpgSign=false commit -qm init

cat >"$TMP/codex" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    output=$2
    shift 2
  else
    shift
  fi
done
prompt=$(cat)
case "$prompt" in
  *'元のユーザー依頼に対して実行したこと、結果、未完了事項を報告していない'*requested-change*'+added guard'*)
    printf 'BLOCK: 追加した guard は依頼にも観測済み障害にも対応していない。\n' >"$output"
    ;;
  *'作業を求める依頼'*report-work*'<assistant-response>'*done*)
    printf 'BLOCK: 実行したことと結果が報告されていない。\n' >"$output"
    ;;
  *retry-work*'<assistant-response>'*hook-only*)
    printf 'BLOCK: hook への返答だけで、ユーザーへの作業報告がない。\n' >"$output"
    ;;
  *retry-work*'<assistant-response>'*'実施内容: fixed'*'結果: ok'*'未完了: なし'*)
    printf 'PASS\n' >"$output"
    ;;
  *other-hook-work*'<assistant-response>'*'実施内容: ok'*)
    printf 'PASS\n' >"$output"
    ;;
  *other-hook-work*'<assistant-response>'*hook-only*)
    printf 'BLOCK: retry response does not satisfy the user request.\n' >"$output"
    ;;
  *'ユーザーにしか実行できない'*user-action-work*'<assistant-response>'*'ユーザーの必要な行動: approve'*)
    printf 'PASS\n' >"$output"
    ;;
  *'ユーザーにしか実行できない'*user-action-work*'<assistant-response>'*'未完了: approval required'*)
    printf 'BLOCK: ユーザーに必要な行動が報告されていない。\n' >"$output"
    ;;
  *'提案・選択肢・今後の候補は実装差分ではありません'*proposal-work*'<assistant-response>'*'提案: path ownership を使う'*)
    printf 'PASS\n' >"$output"
    ;;
  *proposal-work*'<assistant-response>'*'提案: path ownership を使う'*)
    printf 'BLOCK: 正当な提案を未実施として訂正している。\n' >"$output"
    ;;
  *ownership-work*'+unrelated change'*)
    printf 'BLOCK: 別セッションの差分が混入している。\n' >"$output"
    ;;
  *ownership-work*'+owned change'*)
    printf 'PASS\n' >"$output"
    ;;
  *never-pass-work*)
    printf 'BLOCK: reviewer failure repeats.\n' >"$output"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$TMP/codex"

start_input=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"turn",cwd:$cwd,prompt:"requested-change"}')
printf '%s' "$start_input" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

track_input=$(jq -n --arg cwd "$TMP" --arg path "$TMP/code.txt" \
  '{session_id:"session",turn_id:"turn",cwd:$cwd,tool_input:{file_path:$path}}')
printf '%s' "$track_input" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" track >/dev/null
printf 'added guard\n' >>"$TMP/code.txt"
stop_input=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"turn",cwd:$cwd,last_assistant_message:"done",stop_hook_active:false}')
result=$(printf '%s' "$stop_input" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)

if [ "$(printf '%s' "$result" | jq -r '.decision // ""')" = block ] &&
  printf '%s' "$result" | jq -r '.reason // ""' | grep -qF 'hook の指摘への返答を主文にせず、元のユーザー依頼に対して実行したこと、結果、未完了事項を報告'; then
  echo 'ok: unsupported structure blocks Stop'
else
  echo 'NG: unsupported structure blocks Stop'
  exit 1
fi

report_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"report",cwd:$cwd,prompt:"report-work"}')
printf '%s' "$report_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

report_stop=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"report",cwd:$cwd,last_assistant_message:"done",stop_hook_active:false}')
report_result=$(printf '%s' "$report_stop" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)

if [ "$(printf '%s' "$report_result" | jq -r '.decision // ""')" = block ] &&
  printf '%s' "$report_result" | jq -r '.reason // ""' | grep -qF '実行したことと結果が報告されていない' &&
  [ ! -e "$TMP/.git/codex-task-necessity/session-turn" ]; then
  echo 'ok: missing report blocks Stop without a repository diff'
else
  echo 'NG: missing report blocks Stop without a repository diff'
  echo 'PASS=1 FAIL=1'
  exit 1
fi

retry_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"retry",cwd:$cwd,prompt:"retry-work"}')
printf '%s' "$retry_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

retry_stop=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"retry",cwd:$cwd,last_assistant_message:"hook-only",stop_hook_active:false}')
retry_result=$(printf '%s' "$retry_stop" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
retry_state="$TMP/.git/codex-task-necessity/session-retry"
state_preserved=false
[ ! -d "$retry_state" ] || state_preserved=true
hook_prompt_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"retry",cwd:$cwd,prompt:"<hook_prompt hook_run_id=\"stop:test\">internal feedback</hook_prompt>"}')
printf '%s' "$hook_prompt_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

active_result=$(printf '%s' "$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"retry",cwd:$cwd,last_assistant_message:"hook-only",stop_hook_active:true}')" |
  CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
final_result=$(printf '%s' "$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"retry",cwd:$cwd,last_assistant_message:"実施内容: fixed\n結果: ok\n未完了: なし",stop_hook_active:true}')" |
  CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
retry_state_after_pass=false
[ ! -d "$retry_state" ] || retry_state_after_pass=true
retry_next_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"retry-next",cwd:$cwd,prompt:"next-work"}')
printf '%s' "$retry_next_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

if [ "$(printf '%s' "$retry_result" | jq -r '.decision // ""')" = block ] &&
  [ "$state_preserved" = true ] &&
  printf '%s' "$retry_result" | jq -r '.reason // ""' | grep -qF $'元のユーザー依頼:\nretry-work' &&
  [ "$(printf '%s' "$active_result" | jq -r '.decision // ""')" = block ] &&
  [ "$(printf '%s' "$final_result" | jq -r '.decision // ""')" != block ] &&
  [ "$retry_state_after_pass" = true ] &&
  [ ! -e "$retry_state" ]; then
  echo 'ok: blocked retries preserve and recheck the original user request'
else
  echo 'NG: blocked retries preserve and recheck the original user request'
  echo 'PASS=2 FAIL=1'
  exit 1
fi

other_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"other",cwd:$cwd,prompt:"other-hook-work"}')
printf '%s' "$other_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
other_stop=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"other",cwd:$cwd,last_assistant_message:"実施内容: ok",stop_hook_active:false}')
printf '%s' "$other_stop" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop >/dev/null
other_state="$TMP/.git/codex-task-necessity/session-other"
state_after_pass=false
[ ! -d "$other_state" ] || state_after_pass=true
other_hook_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"other",cwd:$cwd,prompt:"<hook_prompt hook_run_id=\"stop:other\">style feedback</hook_prompt>"}')
printf '%s' "$other_hook_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
other_retry=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"other",cwd:$cwd,last_assistant_message:"hook-only",stop_hook_active:true}')
other_retry_result=$(printf '%s' "$other_retry" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
next_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"next",cwd:$cwd,prompt:"next-work"}')
printf '%s' "$next_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

if [ "$state_after_pass" = true ] &&
  [ "$(printf '%s' "$other_retry_result" | jq -r '.decision // ""')" = block ] &&
  printf '%s' "$other_retry_result" | jq -r '.reason // ""' | grep -qF $'元のユーザー依頼:\nother-hook-work' &&
  [ ! -e "$other_state" ]; then
  echo 'ok: another Stop hook cannot replace or bypass the user request'
else
  echo 'NG: another Stop hook cannot replace or bypass the user request'
  echo 'PASS=3 FAIL=1'
  exit 1
fi

action_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"action",cwd:$cwd,prompt:"user-action-work"}')
printf '%s' "$action_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
action_missing=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"action",cwd:$cwd,last_assistant_message:"実行: requested\n結果: blocked\n未完了: approval required",stop_hook_active:false}')
action_missing_result=$(printf '%s' "$action_missing" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
action_reported=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"action",cwd:$cwd,last_assistant_message:"実行: requested\n結果: blocked\n未完了: approval required\nユーザーの必要な行動: approve",stop_hook_active:true}')
action_reported_result=$(printf '%s' "$action_reported" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)

if [ "$(printf '%s' "$action_missing_result" | jq -r '.decision // ""')" = block ] &&
  printf '%s' "$action_missing_result" | jq -r '.reason // ""' | grep -qF 'ユーザーに必要な行動が報告されていない' &&
  [ "$(printf '%s' "$action_reported_result" | jq -r '.decision // ""')" != block ]; then
  echo 'ok: required user action is preserved in the final report'
else
  echo 'NG: required user action is preserved in the final report'
  echo 'PASS=4 FAIL=1'
  exit 1
fi

proposal_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"proposal",cwd:$cwd,prompt:"proposal-work"}')
printf '%s' "$proposal_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
proposal_stop=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"proposal",cwd:$cwd,last_assistant_message:"提案: path ownership を使う",stop_hook_active:false}')
proposal_result=$(printf '%s' "$proposal_stop" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
proposal_review="$TMP/.git/codex-task-necessity/session-proposal/review.prompt"
proposal_verdict="$TMP/.git/codex-task-necessity/session-proposal/review.result"

if [ "$(printf '%s' "$proposal_result" | jq -r '.decision // ""')" != block ] &&
  [ -f "$proposal_review" ] &&
  [ "$(sed -n '1p' "$proposal_verdict")" = PASS ]; then
  echo 'ok: legitimate proposals are not treated as unimplemented changes'
else
  echo 'NG: legitimate proposals are not treated as unimplemented changes'
  echo 'PASS=5 FAIL=1'
  exit 1
fi

ownership_start=$(jq -n --arg cwd "$TMP" \
  '{session_id:"owner-session",turn_id:"parallel",cwd:$cwd,prompt:"ownership-work"}')
printf '%s' "$ownership_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
child_start=$(jq -n --arg cwd "$TMP" \
  '{session_id:"owner-session",turn_id:"child-turn",agent_id:"child",agent_type:"default",cwd:$cwd,prompt:"child-work"}')
printf '%s' "$child_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
other_session_start=$(jq -n --arg cwd "$TMP" \
  '{session_id:"other-session",turn_id:"parallel",cwd:$cwd,prompt:"other-work"}')
printf '%s' "$other_session_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

other_track=$(jq -n --arg cwd "$TMP" --arg path "$TMP/unrelated.txt" \
  '{session_id:"other-session",turn_id:"parallel",cwd:$cwd,tool_input:{file_path:$path}}')
printf '%s' "$other_track" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" track >/dev/null
printf 'unrelated change\n' >>"$TMP/unrelated.txt"

# subagent hook は親 session_id と固有 turn_id を受け取り、親 state へ集約される。
delegated_track=$(jq -n --arg cwd "$TMP" \
  '{session_id:"owner-session",turn_id:"child-turn",agent_id:"child",agent_type:"default",cwd:$cwd,tool_input:{command:"*** Begin Patch\n*** Update File: owned.txt\n*** End Patch"}}')
printf '%s' "$delegated_track" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" track >/dev/null
printf 'owned change\n' >>"$TMP/owned.txt"

ownership_stop=$(jq -n --arg cwd "$TMP" \
  '{session_id:"owner-session",turn_id:"parallel",cwd:$cwd,last_assistant_message:"done",stop_hook_active:false}')
ownership_result=$(printf '%s' "$ownership_stop" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
ownership_review="$TMP/.git/codex-task-necessity/owner-session-parallel/review.prompt"
codex_tracker_count=$(jq '[.hooks.PreToolUse[] |
  select((.matcher // "") | test("apply_patch")) | .hooks[] |
  select(.command == "bash ~/.agent-shared/hooks/task-necessity-gate.sh track")] | length' "$REPO/codex/hooks.json")

if [ "$(printf '%s' "$ownership_result" | jq -r '.decision // ""')" != block ] &&
  [ -f "$ownership_review" ] &&
  grep -qF '+owned change' "$ownership_review" &&
  ! grep -qF '+unrelated change' "$ownership_review" &&
  [ "$codex_tracker_count" -eq 1 ]; then
  echo 'ok: reviewer diff is limited to the parent session and turn'
else
  echo 'NG: reviewer diff is limited to the parent session and turn'
  echo 'PASS=5 FAIL=1'
  exit 1
fi

never_start=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"never",cwd:$cwd,prompt:"never-pass-work"}')
printf '%s' "$never_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
never_state="$TMP/.git/codex-task-necessity/session-never"
never_blocks=0
for active in false true true true; do
  never_stop=$(jq -n --arg cwd "$TMP" --argjson active "$active" \
    '{session_id:"session",turn_id:"never",cwd:$cwd,last_assistant_message:"still wrong",stop_hook_active:$active}')
  never_result=$(printf '%s' "$never_stop" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)
  if [ "$(printf '%s' "$never_result" | jq -r '.decision // ""')" = block ]; then
    never_blocks=$((never_blocks + 1))
  fi
done

if [ "$never_blocks" -eq 3 ] && [ ! -e "$never_state" ]; then
  echo 'ok: repeated reviewer failures stop after three corrections'
else
  echo "NG: repeated reviewer failures stop after three corrections (blocks=$never_blocks)"
  echo 'PASS=4 FAIL=1'
  exit 1
fi

ending_start=$(jq -n --arg cwd "$TMP" '{session_id:"ending",turn_id:"end",cwd:$cwd,prompt:"ending-work"}')
printf '%s' "$ending_start" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null
ending_state="$TMP/.git/codex-task-necessity/ending-end"
ending_cleanup=$(jq -n --arg cwd "$TMP" '{session_id:"ending",cwd:$cwd}')
printf '%s' "$ending_cleanup" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" cleanup-session >/dev/null

if [ ! -e "$ending_state" ]; then
  echo 'ok: session end removes the preserved request state'
  echo 'PASS=9 FAIL=0'
else
  echo 'NG: session end removes the preserved request state'
  echo 'PASS=8 FAIL=1'
  exit 1
fi
