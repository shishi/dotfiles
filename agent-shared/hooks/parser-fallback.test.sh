#!/usr/bin/env bash
# shfmt が無い環境で、ガードが落ちずに以前の判定 (b337715 と同じ) だけで判定し、導入をバックグラウンドで一度だけ始めて通知することを確かめる。
# 導入コマンドはスタブに差し替える (実際の nix / scoop / brew は実行しない)。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/reboot-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# PATH から shfmt のあるディレクトリを外す。同じ場所にある jq・python は転送用のスクリプトで補う。
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/state"
for tool in jq python3; do
  real="$(command -v "$tool" || command -v python)"
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$real" >"$TMP/bin/$tool"
  chmod +x "$TMP/bin/$tool"
done
filtered="$TMP/bin"
IFS=: read -ra path_dirs <<<"$PATH"
for dir in "${path_dirs[@]}"; do
  [[ -e "$dir/shfmt" || -e "$dir/shfmt.exe" ]] && continue
  filtered="$filtered:$dir"
done

cat >"$TMP/stub-install.sh" <<'EOF'
#!/usr/bin/env bash
echo started >>"$STUB_COUNTER"
# テストが終わらせるまで導入中のままにする (負荷で時間がずれても判定がぶれないように)
for _ in $(seq 1 600); do
  [ -e "$STUB_RELEASE" ] && exit 1
  sleep 0.2
done
exit 1
EOF
bash_path="$BASH"
stub_path="$TMP/stub-install.sh"
if command -v cygpath >/dev/null 2>&1; then
  bash_path="$(cygpath -m "$BASH")"
  stub_path="$(cygpath -m "$stub_path")"
fi

run_hook() {
  local command=$1
  shift
  jq -cn --arg command "$command" '{session_id:"test-session",tool_name:"Bash",tool_input:{command:$command}}' |
    env -u SCOOP PATH="$filtered" HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" \
      REBOOT_GUARD_STATE_DIR="$TMP/approvals" STUB_COUNTER="$TMP/counter" STUB_RELEASE="$TMP/release" \
      AGENT_GUARD_SHFMT_INSTALL_CMD="'$bash_path' '$stub_path'" bash "$HOOK" "$@"
}

failures=0
fail() {
  echo "NG: $1"
  failures=$((failures + 1))
}

if env PATH="$filtered" HOME="$TMP/home" bash -c 'command -v shfmt' >/dev/null 2>&1; then
  fail "テストの前提: PATH から shfmt を外せていない"
fi

start=$(date +%s%N)
out="$(run_hook 'git status --short')"
elapsed_ms=$((($(date +%s%N) - start) / 1000000))
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${out:-null}" >/dev/null; then
  fail "shfmt が無くても対象外のコマンドは止めない ($out)"
fi
if ! jq -e '.systemMessage | contains("shfmt") and contains("以前の判定") and contains("導入を開始")' <<<"${out:-null}" >/dev/null; then
  fail "以前の判定だけで判定したことと導入の開始を通知する ($out)"
fi
if [[ "$elapsed_ms" -ge 2500 ]]; then
  fail "導入の完了を待たずに応答する (${elapsed_ms}ms)"
fi

out="$(run_hook 'sudo reboot')"
if ! jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("以前の判定") and contains("導入中"))' <<<"${out:-null}" >/dev/null; then
  fail "以前の判定でも再起動は止め、理由に導入中であることを書く ($out)"
fi
# 以前の判定が分割できない形は解析器を使わずに止め、理由に閉じられない引用符の行と文字、解析器の導入状況を書く
out="$(run_hook $'cat <<\'EOF\' > note.txt\ndon\'t stop\nEOF' --shell powershell)"
if ! jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("2 行目の \u0027 を閉じられない") and contains("導入中"))' <<<"${out:-null}" >/dev/null; then
  fail "以前の判定が分割できない形は止め、理由に行と引用符と導入状況を書く ($out)"
fi

run_hook 'git status --short' >/dev/null # 文面が「導入中」に変わったので一度は通知する
out="$(run_hook 'git status --short')"
if [[ -n "$out" ]]; then
  fail "同じ通知は繰り返さない ($out)"
fi

# 解析器が使えず検出が完全でないときは、readback も呼び出しが見つからなかったことを知らせる
out="$(jq -cn '{tool_input:{command:"ls"},tool_response:{stdout:"ok"}}' |
  env -u SCOOP PATH="$filtered" HOME="$TMP/home" XDG_STATE_HOME="$TMP/readback-state" \
    AGENT_GUARD_SHFMT_INSTALL_CMD="'$bash_path' '$stub_path'" STUB_COUNTER="$TMP/readback-counter" \
    STUB_RELEASE="$TMP/release" bash "$SCRIPT_DIR/outward-write-readback.sh")"
jq -e '.hookSpecificOutput.additionalContext | contains("検出は完全ではない")' <<<"${out:-null}" >/dev/null ||
  fail "検出が完全でないことを readback が知らせる ($out)"

touch "$TMP/release"
# 子は導入の結果として失敗の印を書く。印ができたら終わったとみなす
for _ in $(seq 1 300); do
  [[ -e "$TMP/state/agent-guards/shfmt-install.failed" ]] && break
  sleep 0.2
done
out="$(run_hook 'git status --short')"
if ! jq -e '.systemMessage | contains("導入に失敗") and contains("shfmt-install.log")' <<<"${out:-null}" >/dev/null; then
  fail "導入の失敗をログの場所つきで通知する ($out)"
fi
# 導入が 1 回だけ起動することと、失敗の後に待つことは lib/parser-tools-cases.py が確かめる

# 解析が締切を超えたら、以前の判定に戻して理由を知らせる (hook の timeout より前に結論を出す)
deadline_hook() {
  jq -cn --arg command "$2" '{session_id:"test-session",tool_name:"Bash",tool_input:{command:$command}}' |
    env AGENT_GUARD_DEADLINE_SECONDS=0.001 XDG_STATE_HOME="$TMP/deadline-state" \
      REBOOT_GUARD_STATE_DIR="$TMP/approvals" bash "$SCRIPT_DIR/$1"
}
out="$(deadline_hook reboot-guard.sh "echo 'unterminated")"
if ! jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("1 行目の \u0027 を閉じられない"))' <<<"${out:-null}" >/dev/null; then
  fail "締切を超えても、以前の判定が分割できない形は止め、理由に閉じられない引用符の行を書く ($out)"
fi
out="$(deadline_hook reboot-guard.sh 'git status --short')"
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${out:-null}" >/dev/null ||
  ! jq -e '.systemMessage | contains("締切")' <<<"${out:-null}" >/dev/null; then
  fail "締切を超えても対象外のコマンドは通し、締切を通知する ($out)"
fi

# python が無いとき、止めない hook も判定していないことを知らせる
mkdir -p "$TMP/nopy"
cp "$TMP/bin/jq" "$TMP/nopy/jq"
no_python() {
  jq -cn --arg command "$2" '{session_id:"s",tool_name:"Bash",tool_input:{command:$command},tool_response:{stdout:"ok"}}' |
    env PATH="$TMP/nopy:/usr/bin" XDG_STATE_HOME="$TMP/nopy-state" bash "$SCRIPT_DIR/$1"
}
out="$(no_python gh-body-file-guard.sh 'gh pr create --body-file /tmp/x.md')"
jq -e '.systemMessage | contains("python が見つからない")' <<<"${out:-null}" >/dev/null ||
  fail "python が無いとき gh-body-file-guard が通知する ($out)"
out="$(no_python outward-write-readback.sh 'git push origin HEAD')"
jq -e '.hookSpecificOutput.additionalContext | contains("python が見つからない")' <<<"${out:-null}" >/dev/null ||
  fail "python が無いとき readback が通知する ($out)"

# python があっても起動できない (Microsoft Store の別名など) ときは、python が無いときと同じに扱う
mkdir -p "$TMP/badpy"
printf '#!/usr/bin/env bash\nexit 49\n' >"$TMP/badpy/python3"
chmod +x "$TMP/badpy/python3"
bad_python() {
  jq -cn --arg command "$2" '{session_id:"s",tool_name:"Bash",tool_input:{command:$command},tool_response:{stdout:"ok"}}' |
    env PATH="$TMP/badpy:$TMP/nopy:/usr/bin" XDG_STATE_HOME="$TMP/badpy-state" \
      REBOOT_GUARD_STATE_DIR="$TMP/approvals" bash "$SCRIPT_DIR/$1"
}
out="$(bad_python gh-body-file-guard.sh 'gh pr view 1')"
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${out:-null}" >/dev/null ||
  ! jq -e '.systemMessage | contains("python を起動できない")' <<<"${out:-null}" >/dev/null; then
  fail "起動できない python では gh-body-file-guard は通して通知する ($out)"
fi
out="$(bad_python outward-write-readback.sh 'git push origin HEAD')"
jq -e '.hookSpecificOutput.additionalContext | contains("python を起動できない")' <<<"${out:-null}" >/dev/null ||
  fail "起動できない python では readback が通知する ($out)"
out="$(bad_python reboot-guard.sh 'git status')"
jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("python を起動できない"))' <<<"${out:-null}" >/dev/null ||
  fail "起動できない python では reboot-guard は理由を書いて止める ($out)"

# 作業ディレクトリに標準モジュールと同名のファイル (json.py) があっても、判定がそれを読まない
mkdir -p "$TMP/shadow"
: >"$TMP/shadow/json.py"
: >"$TMP/shadow-release" # shfmt が無いマシンで導入のスタブが起動しても、すぐ終わらせる
shadowed() {
  jq -cn --arg command "$2" '{session_id:"s",tool_name:"Bash",tool_input:{command:$command}}' |
    (cd "$TMP/shadow" && REBOOT_GUARD_STATE_DIR="$TMP/approvals" XDG_STATE_HOME="$TMP/shadow-state" \
      AGENT_GUARD_SHFMT_INSTALL_CMD="'$bash_path' '$stub_path'" STUB_COUNTER="$TMP/shadow-counter" \
      STUB_RELEASE="$TMP/shadow-release" bash "$SCRIPT_DIR/$1")
}
out="$(shadowed reboot-guard.sh 'sudo reboot')"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${out:-null}" >/dev/null ||
  fail "作業ディレクトリの json.py があっても reboot を止める ($out)"
out="$(shadowed gh-body-file-guard.sh 'gh pr create --body-file x.md')"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${out:-null}" >/dev/null ||
  fail "作業ディレクトリの json.py があっても gh の --body-file を止める ($out)"

# PowerShell の解析器が無いときは導入せず、PowerShell の本文は構文木では読まない (以前の判定はそのまま走る)
"$(command -v python3 || command -v python)" "$SCRIPT_DIR/lib/nested-parser-cases.py" || fail "入れ子の解析器が使えないときの判定"
# 以前の判定 (head_judge.py) が b337715 の本文から 1 文字も変わっていない
"$(command -v python3 || command -v python)" "$SCRIPT_DIR/lib/head-judge-cases.py" >/dev/null || fail "以前の判定の凍結"
# 導入中かは導入本体が持つ OS の排他ロックで判定し、導入本体はどの終わり方でも失敗の印を残す
"$(command -v python3 || command -v python)" "$SCRIPT_DIR/lib/parser-tools-cases.py" || fail "導入の lock と失敗の記録"

[[ "$failures" -eq 0 ]]
echo 'parser-fallback tests passed'
