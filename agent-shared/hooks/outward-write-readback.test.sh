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
  jq -n --arg cmd "$1" '{tool_input:{command:$cmd},tool_response:{stdout:"https://github.com/example/repo/pull/1"}}' |
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

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
