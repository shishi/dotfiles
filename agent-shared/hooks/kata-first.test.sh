#!/usr/bin/env bash
# kata-first.sh が、利用者の入力ごとに kata を最初に開かせることを、hook へ実際の入力を流して確かめる。
# 使い方: bash agent-shared/hooks/kata-first.test.sh
set -u
hook="$(cd "$(dirname "$0")" && pwd)/kata-first.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kata-first-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export KATA_FIRST_STATE_DIR=$tmp/state
unset AGENT_DELEGATED_SESSION
fail=0

prompt() { # session
  jq -nc --arg s "$1" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:"x"}' | bash "$hook" prompt
}
# tool を呼んだときの終了コードを返す。2 なら止めた。
tool() { # session tool_name tool_input_json [agent_id]
  jq -nc --arg s "$1" --arg t "$2" --argjson i "$3" --arg a "${4:-}" \
    '{session_id:$s, hook_event_name:"PreToolUse", tool_name:$t, tool_input:$i} + (if $a == "" then {} else {agent_id:$a} end)' |
    bash "$hook" pre > /dev/null 2>&1
  echo $?
}
check() { # name want got
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want=$2 got=$3"; fail=1; fi
}

out=$(prompt s1)
case $out in *kata*) echo "ok   入力のたびに kata を最初に開く案内を出す" ;; *) echo "FAIL 入力の案内に kata が無い: $out"; fail=1 ;; esac

check "入力のあと kata を開く前の Bash を止める" 2 "$(tool s1 Bash '{"command":"ls"}')"
check "タスク表示用のツールは止めない" 0 "$(tool s1 mcp__ccd_turn__update_plan '{"items":[]}')"
check "Claude Code のタスク表示 (TodoWrite) は止めない" 0 "$(tool s1 TodoWrite '{"todos":[]}')"
check "Codex のタスク表示 (update_plan) は止めない" 0 "$(tool s1 update_plan '{"plan":[]}')"
check "子エージェントのツール呼出しは止めない" 0 "$(tool s1 Read '{"file_path":"/x"}' child1)"
check "kata 以外の skill は止める" 2 "$(tool s1 Skill '{"skill":"review-gate"}')"
check "kata を開く Skill は通す" 0 "$(tool s1 Skill '{"skill":"kata"}')"
check "kata を開いた後は他のツールも通す" 0 "$(tool s1 Bash '{"command":"ls"}')"

prompt s1 > /dev/null
check "次の入力では再び kata を求める" 2 "$(tool s1 Bash '{"command":"ls"}')"

check "入力の印が無いセッションは止めない" 0 "$(tool s2 Bash '{"command":"ls"}')"

prompt s3 > /dev/null
check "Codex で kata の SKILL.md を読むコマンドは通す" 0 "$(tool s3 Bash '{"command":"sed -n 1,200p ~/.codex/skills/kata/SKILL.md"}')"
check "Codex で kata を読んだ後は他のコマンドも通す" 0 "$(tool s3 Bash '{"command":"git status"}')"

prompt s7 > /dev/null
check "Windows のパスで kata の SKILL.md を読むコマンドも通す" 0 "$(tool s7 Bash '{"command":"Get-Content C:\\Users\\u\\.codex\\skills\\kata\\SKILL.md"}')"
prompt s8 > /dev/null
check "kata のディレクトリへ移って SKILL.md を読むコマンドも通す" 0 "$(tool s8 Bash '{"command":"cd ~/.codex/skills/kata && cat SKILL.md"}')"

prompt s4 > /dev/null
check "別のセッションの kata は印を消さない" 0 "$(tool s5 Skill '{"skill":"kata"}')"
check "印は自分のセッションに残る" 2 "$(tool s4 Bash '{"command":"ls"}')"

out=$(AGENT_DELEGATED_SESSION=1 prompt s6)
check "委譲された子には入力の案内を出さない" "" "$out"
prompt s6 > /dev/null
check "印があっても委譲された子のツールは止めない" 0 "$(AGENT_DELEGATED_SESSION=1 tool s6 Bash '{"command":"ls"}')"
check "委譲された子が通っても親の印は残る" 2 "$(tool s6 Bash '{"command":"ls"}')"

prompt s9 > /dev/null
check "Claude の Read で kata の SKILL.md を開くと通す" 0 "$(tool s9 Read '{"file_path":"/home/u/.claude/skills/kata/SKILL.md"}')"
check "Read で kata を開いた後は他のツールも通す" 0 "$(tool s9 Bash '{"command":"ls"}')"

prompt s10 > /dev/null
check "kata 以外のファイルの Read は止める" 2 "$(tool s10 Read '{"file_path":"/home/u/README.md"}')"

: > "$tmp/not-a-dir"
out=$(KATA_FIRST_STATE_DIR=$tmp/not-a-dir/state prompt s11)
case $out in *kata*) echo "ok   状態を保存できなくても入力の案内は出す" ;; *) echo "FAIL 状態を保存できないと案内が出ない: $out"; fail=1 ;; esac


echo keep > "$tmp/victim"
mkdir -p "$KATA_FIRST_STATE_DIR"
ln -s "$tmp/victim" "$KATA_FIRST_STATE_DIR/s12"
prompt s12 > /dev/null
check "印がシンボリックリンクならリンク先を書き換えない" keep "$(cat "$tmp/victim")"

ln -s "$tmp" "$tmp/linked-state"
out=$(KATA_FIRST_STATE_DIR=$tmp/linked-state prompt s13)
check "保存先がシンボリックリンクなら印を作らない" "" "$(ls "$tmp" | grep -x s13)"
case $out in *kata*) echo "ok   保存先を使えなくても案内は出す" ;; *) echo "FAIL 保存先を使えないと案内が出ない"; fail=1 ;; esac

mkdir -p "$tmp/open-state"; chmod 777 "$tmp/open-state"
KATA_FIRST_STATE_DIR=$tmp/open-state prompt s14 > /dev/null
check "他人も書き込める保存先は自分だけの権限にしてから使う" drwx------ "$(ls -ld "$tmp/open-state" | cut -c1-10)"

exit $fail
