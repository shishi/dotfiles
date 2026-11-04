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
out=$(jq -n '{tool_input:{command:["gh","pr","edit","1","--body-file","-"]},tool_response:{stdout:"https://github.com/example/repo/pull/1"}}' |
  bash "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
check 'argv 配列のコマンドも読む' "$out" '本文を取得した'

# 検出処理を動かせないときは、確認していないことを知らせる
export XDG_STATE_HOME="$TMP/state"
mkdir -p "$TMP/nopy"
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c '' >/dev/null 2>&1; then
    real_python=$(command -v "$candidate")
    break
  fi
done
printf '#!/usr/bin/env bash\nexit 9\n' >"$TMP/nopy/python3"
# ホストに python が無くても、起動できる python を 1 つ用意して試す
printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_python" >"$TMP/nopy/python"
chmod +x "$TMP/nopy/python3" "$TMP/nopy/python"
out=$(PATH="$TMP/nopy:$PATH" observe 'gh pr edit 1 --body-file -')
check '起動できない python3 があっても、起動できる python で確認する' "$out" '本文を取得した'
cp "$TMP/nopy/python3" "$TMP/nopy/python"
out=$(PATH="$TMP/nopy:$PATH" observe 'git push origin HEAD')
check '起動できる python が無いことを黙って通さない' "$out" 'を確認していない'
rm -f "$TMP/nopy/python"
printf '#!/usr/bin/env bash\n[ "$1" = -c ] && exit 0\nexit 2\n' >"$TMP/nopy/python3"
out=$(PATH="$TMP/nopy:$PATH" observe 'git push origin HEAD')
check '検出処理の失敗を黙って通さない' "$out" '終了コード 2'
out=$(PYTHONIOENCODING=cp932 observe 'gh pr edit 1 --body "あ"')
check '既定の符号化が UTF-8 でなくても日本語を含む入力を読む' "$out" '本文を取得した'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
