#!/usr/bin/env bash
# ターンの依頼と差分を独立 reviewer が照合し、不要構造を block する契約を検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$REPO/agents/hooks/task-necessity-gate.sh"
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
  *requested-change*'+added guard'*) ;;
  *) exit 2 ;;
esac
printf 'BLOCK: 追加した guard は依頼にも観測済み障害にも対応していない。\n' >"$output"
EOF
chmod +x "$TMP/codex"

start_input=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"turn",cwd:$cwd,prompt:"requested-change"}')
printf '%s' "$start_input" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" start >/dev/null

printf 'added guard\n' >>"$TMP/code.txt"
stop_input=$(jq -n --arg cwd "$TMP" '{session_id:"session",turn_id:"turn",cwd:$cwd,last_assistant_message:"done",stop_hook_active:false}')
result=$(printf '%s' "$stop_input" | CODEX_BIN_PATH="$TMP/codex" bash "$HOOK" stop)

if [ "$(printf '%s' "$result" | jq -r '.decision // ""')" = block ]; then
  echo 'ok: unsupported structure blocks Stop'
  echo 'PASS=1 FAIL=0'
else
  echo 'NG: unsupported structure blocks Stop'
  echo 'PASS=0 FAIL=1'
  exit 1
fi
