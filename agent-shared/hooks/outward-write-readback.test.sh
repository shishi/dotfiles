#!/usr/bin/env bash
# 本文を再注入せず、取得結果だけを通知する契約を実際の hook 出力で確認する。
set -eu

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/outward-write-readback.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/readback.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$READBACK_BODY"
exit "$READBACK_STATUS"
EOF
chmod +x "$TMP/gh"
export PATH="$TMP:$PATH"
export READBACK_BODY='本文の再注入を検出する目印'
export READBACK_STATUS=0
PASS=0
FAIL=0

observe() {
  jq -n --arg cmd "$1" --arg key "${2:-command}" '{tool_input:{($key):$cmd},tool_response:{stdout:"https://github.com/example/repo/pull/1"}}' |
    bash "$HOOK" | jq -r '.hookSpecificOutput.additionalContext'
}
check() {
  if [[ "$2" == *"$3"* && "$2" != *"本文の再注入を検出する目印"* ]]; then
    PASS=$((PASS + 1)); echo "ok: $1"
  else
    FAIL=$((FAIL + 1)); echo "NG: $1"
  fi
}

out=$(observe 'gh pr edit 1 --body-file -')
check '本文を取得しても本文自身は注入しない' "$out" '本文を取得した'
out=$(observe 'gh pr edit 1 --body-file -' cmd)
check 'native cmd 入力でも取得処理へ到達する' "$out" '本文を取得した'
out=$(jq -n '{tool_input:{command:"",cmd:"gh pr edit 1 --body-file -"},tool_response:{stdout:"https://github.com/example/repo/pull/1"}}' |
  bash "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
check 'command が空なら cmd を読む (以前の判定と同じ)' "$out" '本文を取得した'
READBACK_BODY=''
out=$(observe 'gh pr edit 1 --body-file -')
check '空の本文も取得成功として扱う' "$out" '本文を取得した'
READBACK_STATUS=1
READBACK_BODY='unexpected failure'
out=$(observe 'gh pr edit 1 --body-file -')
check '終了コードによって取得失敗を区別する' "$out" '本文の取得に失敗'
READBACK_STATUS=0
out=$(observe 'gh pr comment 1 --body-file -')
check '親本文をコメントの実物として扱わない' "$out" 'コメント本文は未取得'


# 検出処理の出力を読めない (1 行目が ok でも undecidable でもない) ときは、確認していないことを 10 分に 1 回知らせる
mkdir -p "$TMP/garbled"
real_python=$(command -v python3 || command -v python)
cat >"$TMP/garbled/python3" <<EOF
#!/usr/bin/env bash
case "\$1" in
  *detect-invocation.py) cat >/dev/null; echo 'Traceback?'; exit 0 ;;
esac
exec "$real_python" "\$@"
EOF
chmod +x "$TMP/garbled/python3"
garbled() {
  jq -n '{tool_input:{command:"git push origin HEAD"}}' |
    PATH="$TMP/garbled:$PATH" XDG_STATE_HOME="$TMP/state" bash "$HOOK" | jq -r '.hookSpecificOutput.additionalContext'
}
out=$(garbled)
check '検出処理の出力を読めなければ知らせる' "$out" '出力を読めず'
out=$(garbled)
if [ -z "$out" ]; then PASS=$((PASS + 1)); echo "ok: 同じ通知は間引く"; else FAIL=$((FAIL + 1)); echo "NG: 同じ通知は間引く ($out)"; fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
