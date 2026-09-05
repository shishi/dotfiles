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
git -C "$TMP" add code.txt
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
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$TMP/codex"

start_input=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"turn",cwd:$cwd,prompt:"requested-change"}')
printf '%s' "$start_input" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

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
  printf '%s' "$report_result" | jq -r '.reason // ""' | grep -qF '実行したことと結果が報告されていない'; then
  echo 'ok: missing report blocks Stop without a repository diff'
  echo 'PASS=2 FAIL=0'
else
  echo 'NG: missing report blocks Stop without a repository diff'
  echo 'PASS=1 FAIL=1'
  exit 1
fi
