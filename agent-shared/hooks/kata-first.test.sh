#!/usr/bin/env bash
# kata-first.sh が、利用者の入力ごとに kata を最初に開かせることを、hook へ実際の入力を流して確かめる。
# 使い方: bash agent-shared/hooks/kata-first.test.sh
set -u
hook="$(cd "$(dirname "$0")" && pwd)/kata-first.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kata-first-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export KATA_FIRST_STATE_DIR=$tmp/state
unset AGENT_DELEGATED_SESSION T3CODE_THREAD_ID
# 手元の T3 Code の記録を読まないよう、T3 の保存先をテスト用の場所に向ける。
export T3CODE_HOME=$tmp/t3
# T3 が起動した Codex の本体には、この目印が付く。
export CODEX_INTERNAL_ORIGINATOR_OVERRIDE="T3 Code"
fail=0

# T3 Code の状態 DB の偽物を作る。表は T3 0.1.11 の実物と同じ定義で、Codex の会話 (nativeId) が属する
# T3 のスレッドを 1 行ずつ記録する。
t3_db() { # dir thread_id native_id [thread_id native_id ...]
  local db=$1/userdata/statev2.sqlite sql
  mkdir -p "$1/userdata"
  sql="CREATE TABLE orchestration_v2_projection_provider_threads (
      provider_thread_id TEXT PRIMARY KEY, thread_id TEXT, owner_node_id TEXT, provider TEXT NOT NULL,
      provider_session_id TEXT, status TEXT NOT NULL, first_run_ordinal INTEGER, last_run_ordinal INTEGER,
      updated_at TEXT NOT NULL, payload_json TEXT NOT NULL, driver TEXT, provider_instance_id TEXT);
    CREATE TABLE orchestration_v2_projection_threads (thread_id TEXT PRIMARY KEY, deleted_at TEXT, updated_at TEXT NOT NULL);"
  shift
  while [ $# -ge 2 ]; do
    sql="$sql INSERT INTO orchestration_v2_projection_provider_threads VALUES ('provider-thread:$1', '$1', NULL, 'codex',
      'provider-session:provider-instance:codex:shared', 'idle', 1, 1, '2026-11-20T17:06:32.711Z',
      '{\"id\":\"provider-thread:$1\",\"driver\":\"codex\",\"providerInstanceId\":\"codex\",\"appThreadId\":\"$1\",\"ownerNodeId\":null,\"nativeThreadRef\":{\"driver\":\"codex\",\"nativeId\":\"$2\",\"strength\":\"strong\"},\"status\":\"idle\"}',
      'codex', 'codex');"
    sql="$sql INSERT OR IGNORE INTO orchestration_v2_projection_threads VALUES ('$1', NULL, '2026-11-20T17:06:32.711Z');"
    shift 2
  done
  sqlite3 "$db" "$sql"
}
t3_db "$T3CODE_HOME" \
  thread:delegated-task:command%3Amcp%3Ax%3Adelegate-task%3Az 01a1f9ea-0000-7000-8000-00000000c0de \
  00000000-0000-4000-8000-0000000000aa 01a1f9ea-0000-7000-8000-0000000000ff

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

# T3 Code の delegate_task が起動した子は AGENT_DELEGATED_SESSION を持たず、スレッド ID で分かる。
t3_child=thread:delegated-task:command%3Amcp%3Ax%3Adelegate-task%3Ay
out=$(T3CODE_THREAD_ID=$t3_child prompt s15)
check "T3 の委譲の子には入力の案内を出さない" "" "$out"
prompt s15 > /dev/null
check "印があっても T3 の委譲の子のツールは止めない" 0 "$(T3CODE_THREAD_ID=$t3_child tool s15 Bash '{"command":"ls"}')"
T3CODE_THREAD_ID=00000000-0000-4000-8000-0000000000aa prompt s16 > /dev/null
check "T3 の利用者と話すスレッドは kata を開く前のツールを止める" 2 "$(T3CODE_THREAD_ID=00000000-0000-4000-8000-0000000000aa tool s16 Bash '{"command":"ls"}')"

# T3 は Codex の子にスレッド ID を hook の環境で渡さないため、T3 の記録で会話の属するスレッドを引く。
codex_child=01a1f9ea-0000-7000-8000-00000000c0de
codex_parent=01a1f9ea-0000-7000-8000-0000000000ff
out=$(prompt $codex_child)
check "T3 の記録で委譲の子と分かる Codex の会話には入力の案内を出さない" "" "$out"
check "T3 の記録で委譲の子と分かる Codex の会話はツールを止めない" 0 "$(tool $codex_child Bash '{"command":"ls"}')"
# 入力の時点で T3 の記録がまだ無く印が付いた場合も、ツールを使う時点の判定で止めない
mkdir -p "$KATA_FIRST_STATE_DIR"; : > "$KATA_FIRST_STATE_DIR/$codex_child"
check "印が残っていても T3 の記録で委譲の子と分かる Codex の会話はツールを止めない" 0 "$(tool $codex_child Bash '{"command":"ls"}')"
# T3 の外で委譲済みの会話を codex resume すると、同じ session_id でも T3 が起動した Codex ではない。
CODEX_INTERNAL_ORIGINATOR_OVERRIDE= prompt $codex_child > /dev/null
check "T3 の外で再開した Codex の会話は委譲の子とみなさない" 2 "$(CODEX_INTERNAL_ORIGINATOR_OVERRIDE= tool $codex_child Bash '{"command":"ls"}')"
# 同じ会話が通常のスレッドと委譲のスレッドの両方に対応するときは、どちらか決められないので子とみなさない。
ambiguous=01a1f9ea-0000-7000-8000-0000000000ab
t3_db "$tmp/t3-ambiguous" thread:delegated-task:command%3Amcp%3Ax%3Adelegate-task%3Aamb $ambiguous \
  00000000-0000-4000-8000-0000000000bb $ambiguous
T3CODE_HOME=$tmp/t3-ambiguous prompt $ambiguous > /dev/null
check "通常と委譲の両方に対応する Codex の会話は委譲の子とみなさない" 2 "$(T3CODE_HOME=$tmp/t3-ambiguous tool $ambiguous Bash '{"command":"ls"}')"
# 削除されたスレッドの記録は使わない。
deleted=01a1f9ea-0000-7000-8000-0000000000dd
t3_db "$tmp/t3-deleted" thread:delegated-task:command%3Amcp%3Ax%3Adelegate-task%3Adel $deleted
sqlite3 "$tmp/t3-deleted/userdata/statev2.sqlite" "UPDATE orchestration_v2_projection_threads SET deleted_at = '2026-11-20T18:00:00Z'"
T3CODE_HOME=$tmp/t3-deleted prompt $deleted > /dev/null
check "削除されたスレッドの記録では委譲の子とみなさない" 2 "$(T3CODE_HOME=$tmp/t3-deleted tool $deleted Bash '{"command":"ls"}')"
prompt $codex_parent > /dev/null
check "T3 の利用者と話すスレッドの Codex の会話は kata を開く前のツールを止める" 2 "$(tool $codex_parent Bash '{"command":"ls"}')"
mkdir -p "$tmp/t3-broken/userdata"; echo 'not a database' > "$tmp/t3-broken/userdata/statev2.sqlite"
T3CODE_HOME=$tmp/t3-broken prompt c1 > /dev/null
check "T3 の記録を読めなければ通常どおり kata を開く前のツールを止める" 2 "$(T3CODE_HOME=$tmp/t3-broken tool c1 Bash '{"command":"ls"}')"
mkdir -p "$tmp/t3-other/userdata"; sqlite3 "$tmp/t3-other/userdata/statev2.sqlite" 'CREATE TABLE x (y TEXT);'
T3CODE_HOME=$tmp/t3-other prompt c2 > /dev/null
check "T3 の記録の形が変わっていたら通常どおり kata を開く前のツールを止める" 2 "$(T3CODE_HOME=$tmp/t3-other tool c2 Bash '{"command":"ls"}')"

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
