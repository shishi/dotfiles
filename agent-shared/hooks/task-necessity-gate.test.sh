#!/usr/bin/env bash
# 回答が続いてもユーザー前提を保持し、前回指摘を最新の回答と照合できることを検証する。
set -eu

HOOK=${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/task-necessity-gate.sh"}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/task-necessity-gate.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
git init -q "$TMP/repo"
git -C "$TMP/repo" -c user.name=HookTest -c user.email=hook-test@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m initial
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

cat >"$TMP/reviewer" <<'EOF'
#!/usr/bin/env bash
set -eu
cat >"$REVIEW_CAPTURE"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then printf '%s\n' "$REVIEW_VERDICT" >"$2"; exit 0; fi
  shift
done
exit 1
EOF
chmod +x "$TMP/reviewer"
export CODEX_BIN_PATH="$TMP/reviewer"
export REVIEW_CAPTURE="$TMP/captured.prompt"
export REVIEW_VERDICT=PASS

jq -nc '{type:"event_msg",payload:{type:"user_message",message:"これからつくるかどうかを判断している"}}' >"$TMP/transcript.jsonl"
jq -nc '{type:"event_msg",payload:{type:"user_message",message:"Plusで使う方法を調べ、手順を確定しろ"}}' >>"$TMP/transcript.jsonl"
input=$(jq -nc --arg cwd "$TMP/repo" --arg transcript "$TMP/transcript.jsonl" \
  '{cwd:$cwd,session_id:"content-test",turn_id:"turn",transcript_path:$transcript,prompt:"Plusで使う方法を調べ、手順を確定しろ",last_assistant_message:"本人のログインが必要だよ。"}')
printf '%s' "$input" | bash "$HOOK" start >/dev/null
jq -nc 'range(30) | {type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:("調査結果を補足するよ。" + (. | tostring))}]}}' >>"$TMP/transcript.jsonl"
printf '%s' "$input" | bash "$HOOK" stop >/dev/null
context=$(awk '/^<conversation-context>$/{getline; print; exit}' "$REVIEW_CAPTURE")
if printf '%s' "$context" | jq -e '.messages | any(.role == "user" and .text == "これからつくるかどうかを判断している")' >/dev/null; then
  ok "回答の反復で構築前の採用判断というユーザー前提が落ちない"
else
  ng "回答の反復で構築前の採用判断というユーザー前提が落ちない"
fi

export REVIEW_VERDICT='BLOCK: 接続可否を断定しているが、本人のログインが必要。'
out=$(printf '%s' "$input" | bash "$HOOK" stop)
if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null; then
  export REVIEW_VERDICT=PASS
  printf '%s' "$input" | bash "$HOOK" stop >/dev/null
  previous=$(awk '/^<previous-review>$/{f=1;next} /^<\/previous-review>$/{f=0} f' "$REVIEW_CAPTURE")
  if [ "$previous" = 'BLOCK: 接続可否を断定しているが、本人のログインが必要。' ]; then
    ok "前回指摘を新しい依頼にせず再審査の比較対象に渡す"
  else
    ng "前回指摘を新しい依頼にせず再審査の比較対象に渡す"
  fi
else
  ng "最初の不適合は引き続きblockする"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
