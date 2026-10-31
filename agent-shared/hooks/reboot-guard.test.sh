#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/reboot-guard.sh"
STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$STATE_DIR"' EXIT

export REBOOT_GUARD_STATE_DIR="$STATE_DIR"

hook_input() {
  jq -cn --arg command "$1" '{session_id:"test-session",tool_name:"Bash",tool_input:{command:$command}}'
}

prompt_input() {
  jq -cn --arg prompt "$1" '{session_id:"test-session",prompt:$prompt}'
}

assert_denied() {
  local output
  output="$(hook_input "$1" | bash "$HOOK")"
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$output" >/dev/null
}

assert_allowed() {
  local output
  output="$(hook_input "$1" | bash "$HOOK")"
  [[ -z "$output" ]]
}

assert_denied 'sudo -n systemctl reboot --no-block'
assert_denied 'sudo -u root systemctl reboot'
assert_denied 'sudo env systemctl reboot'
assert_denied 'bash -c "systemctl reboot"'

# 判定の期待はまとめて並列に走らせ、最後に件名つきで照合する (承認を記録する前なので互いに影響しない)。
# expect 期待 件名 コマンド [hook への引数 (--shell powershell 等)] [理由に含むべき文字列 (reason=...)]
CASES="$STATE_DIR/cases"
mkdir -p "$CASES"
case_count=0
expect() {
  local want=$1 label=$2 command=$3 file
  shift 3
  local reason=""
  if [[ "${*: -1}" == reason=* ]]; then
    reason=${*: -1}
    reason=${reason#reason=}
    set -- "${@:1:$#-1}"
  fi
  case_count=$((case_count + 1))
  file="$CASES/$case_count"
  printf '%s\n%s\n%s\n' "$want" "$label" "$reason" >"$file.meta"
  (hook_input "$command" | bash "$HOOK" "$@" >"$file.out") &
  while (($(jobs -rp | wc -l) >= 8)); do
    wait -n
  done
}
# hook 入力の JSON をそのまま渡す (bash の引数に入らない NUL を含む入力用)
raw_expect() {
  case_count=$((case_count + 1))
  printf '%s\n%s\n\n' "$1" "$2" >"$CASES/$case_count.meta"
  (printf '%s' "$3" | bash "$HOOK" >"$CASES/$case_count.out") &
}

# 合成 1: 以前の判定 (b337715 の判定をそのまま実行) が対象を見つけたら止める
expect deny '以前の判定で対象あり' 'command -v reboot' 'reason=各行をコマンドとして読む'
expect deny '以前の判定で入れ子が 4 段を超えた' "sh -c \"sh -c 'sh -c \\\"sh -c true\\\"'\"" 'reason=4 段を超えた'
expect deny '以前の判定で対象あり: env -' 'env - reboot'
# 合成 2: 以前の判定が分割できないときは書き換えて読み直さずに止め、理由に閉じられない引用符の行と文字を書く
expect deny '"$SHELL" -s へ流す本文の Don\x27t' $'"$SHELL" -s <<EOF\nsudo reboot\nDon\'t\nEOF' "reason=3 行目の ' を閉じられない"
expect deny 'ssh へ流す本文の Don\x27t' $'ssh pi <<EOF\nsudo reboot\nDon\'t\nEOF'
expect deny '別の fd のここ文字列と本文の Don\x27t' $'cat <<\'EOF\' | bash 3<<<true\nsudo reboot\nDon\'t\nEOF'
expect deny '本文の引用符が後の行と対になる形' $'"$SHELL" -s <<\'EOF\'\nre"boot"; echo $\'it\\\'s\'\nEOF' "reason=2 行目の ' を閉じられない"
expect deny 'PowerShell: 退避した引用符と [scriptblock]::Create' "[scriptblock]::Create('Restart-Computer').Invoke(); Write-Output \"say \`\"hi\"" --shell powershell
expect deny '引用の中の引用' $'git commit -m "$(printf "it\'s")"' "reason=1 行目の ' を閉じられない"
expect deny '閉じない引用' "echo 'unterminated" 'reason=対になる書き方'
expect deny '末尾の \' 'echo x \' 'reason=末尾の \ の後に文字が無い'
expect deny 'bash -c の文字列の中の閉じない引用 (外側のコメントの引用符は数えない)' $'bash -c "echo \'x" # it\'s' 'reason=bash -c 等に渡した文字列'
expect deny '配列の実行と Don\x27t' $'a=(sudo reboot); "${a[@]}"\necho Don\'t'
expect deny 'eval と Don\x27t' $'eval "$s"\necho Don\'t'
# 以前の判定が分割できないものは、構文木で対象が無くても止める (以前の判定のまま)
expect deny 'cat へのヒアドキュメント本文の引用符' $'cat <<\'EOF\' > note.txt\ndon\'t stop\nEOF' "reason=2 行目の ' を閉じられない"

# 合成 3: 構文木の判定 (以前の判定が対象なしとする形。性質ごとの代表)
expect deny 'URL の # の後ろ (以前はコメントとして捨てた)' 'curl https://x/#frag && sudo reboot'
expect deny 'bash 5.3 の ${ cmd; }' 'echo ${ sudo reboot; }'
expect deny '二重引用内の ${x:-\x27$(...)\x27}' $'echo "${x:-\'$(sudo reboot)\'}"'
expect deny '二重引用内のコマンド置換' 'echo "$(sudo reboot)"'
expect deny 'bash -s へ流す本文の二重引用内の置換' $'bash -s <<\'EOF\'\necho "$(sudo reboot)"\nEOF'
expect deny 'bash /dev/stdin へ流す本文の二重引用内の置換' $'bash /dev/stdin <<\'EOF\'\necho "$(sudo reboot)"\nEOF'
expect deny 'source /dev/stdin へ流す本文の二重引用内の置換' $'source /dev/stdin <<\'EOF\'\necho "$(sudo reboot)"\nEOF'
expect deny '未引用のヒアドキュメントの外側の展開' $'bash <<EOF\necho "$(sudo reboot)"\nEOF'
expect deny 'ANSI-C 引用で連結した語' "re\$'boo't now"
expect deny '行継続で分けた語' $'reboo\\\nt'
expect deny '前置き: timeout' 'timeout 5 reboot'
expect deny '前置き: sudo -T の値' 'sudo -T 10 reboot'
expect deny '前置き: env -S' "env -S 'sudo reboot now'"
expect deny '前置き: su -c' "su -c 'sudo reboot'"
expect deny '前置き: nix develop -c' 'nix develop -c sudo reboot'
expect deny '前置き: docker exec' 'docker exec -u root c reboot'
expect deny '前置き: pkexec' 'pkexec reboot'
expect deny '前置き: setsid' 'setsid reboot'
expect deny '前置き: wsl' 'wsl -d Ubuntu reboot'
expect deny 'bash -c -- の後' "bash -c -- 'sudo reboot'"
expect deny 'eval の引数' "eval 'sudo reboot'"
expect deny 'trap の処理' "trap 'sudo reboot' EXIT"
expect deny 'ssh の遠隔コマンド' "ssh -p 22 host 'sudo systemctl reboot'"
expect deny 'pwsh -EncodedCommand' 'pwsh -EncodedCommand UgBlAHMAdABhAHIAdAAtAEMAbwBtAHAAdQB0AGUAcgA='
expect deny 'powershell.exe の位置引数は -Command' 'powershell.exe Restart-Computer -Force'
expect deny '大文字の .EXE' 'SHUTDOWN.EXE /r'
expect deny 'shutdown //r' 'shutdown //r //t 0'
expect deny 'PowerShell: Start-Process の ArgumentList' "Start-Process shutdown -ArgumentList '\"/r\"'" --shell powershell
expect deny 'PowerShell: iex の引数' "iex 'Restart-Computer'" --shell powershell
expect deny 'PowerShell: cmd /c の引数' 'cmd /c "shutdown /r /t 0"' --shell powershell
expect deny 'PowerShell: 外側を bash として読むと実行する形' 'Write-Output "`reboot`n"' --shell powershell 'reason=外側を bash として読むと実行する'
expect deny 'PowerShell: PowerShell の木の中の bash -c' "bash -c 'echo \`sudo reboot\`'" --shell powershell 'reason=構文木の判定 (bash として読んだbash -c の引数)'

# どちらの判定でも対象にならないもの
expect allow 'rg の検索語' "rg -n 'sudo reboot' -t sh ."
expect allow 'git log --grep' '/usr/bin/git log --grep "reboot"'
expect allow 'commit message の markdown のバッククォート' $'git commit -m "$(cat <<\'EOF\'\n- `sudo reboot` inside the docs\nEOF\n)"'
expect allow 'PowerShell: --% の後の環境変数' 'icacls.exe --% C:\work /grant %USERNAME%:F' --shell powershell
expect allow 'PowerShell: Get-Content と git' 'Get-Content -Raw x; git status' --shell powershell

wait
failures=0
for meta in "$CASES"/*.meta; do
  { IFS= read -r want; IFS= read -r label; IFS= read -r reason; } <"$meta"
  output="$(cat "${meta%.meta}.out")"
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"${output:-null}" >/dev/null; then
    got=deny
  else
    got=allow
  fi
  if [[ "$got" != "$want" ]]; then
    echo "NG: $label (期待=$want 実際=$got) $output"
    failures=$((failures + 1))
  elif [[ -n "$reason" ]] && ! jq -e --arg r "$reason" '.hookSpecificOutput.permissionDecisionReason | contains($r)' <<<"$output" >/dev/null; then
    echo "NG: $label (理由に「$reason」が無い) $output"
    failures=$((failures + 1))
  fi
done

[[ "$failures" -eq 0 ]]

prompt_input 'OSを再起動して' | bash "$HOOK" --record-approval
assert_allowed 'sudo -n systemctl reboot --no-block'
assert_denied 'sudo -n systemctl reboot --no-block'

prompt_input 'OSを再起動して' | bash "$HOOK" --record-approval
hook_input 'sudo -n systemctl reboot --no-block' | bash "$HOOK" >"$STATE_DIR/parallel-1" &
pid1=$!
hook_input 'sudo -n systemctl reboot --no-block' | bash "$HOOK" >"$STATE_DIR/parallel-2" &
pid2=$!
wait "$pid1"
wait "$pid2"
allowed=0
denied=0
for output in "$STATE_DIR/parallel-1" "$STATE_DIR/parallel-2"; do
  if [[ ! -s "$output" ]]; then
    allowed=$((allowed + 1))
  elif jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$output" >/dev/null; then
    denied=$((denied + 1))
  fi
done
[[ "$allowed" -eq 1 && "$denied" -eq 1 ]]

prompt_input 'OSを再起動して' | bash "$HOOK" --record-approval
prompt_input '作業を続けて' | bash "$HOOK" --record-approval
assert_denied 'sudo -n systemctl reboot --no-block'

prompt_input '再起動後も設定が残るか確認して' | bash "$HOOK" --record-approval
assert_denied 'sudo -n systemctl reboot --no-block'

prompt_input '再起動するな' | bash "$HOOK" --record-approval
assert_denied 'sudo -n systemctl reboot --no-block'

assert_allowed 'git status --short'

echo 'reboot-guard tests passed'
