#!/usr/bin/env bash
# kata-entry.sh の上流の新しい版の通知を、ローカルの bare repo を上流に見立てて確かめる。
# 使い方: bash agent-shared/hooks/kata-entry.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
hook=${KATA_ENTRY_HOOK:-$here/kata-entry.sh}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kata-entry-test.XXXXXX") || exit 1
tmp=$(cd -P "$tmp" && pwd) || exit 1
trap 'rm -rf "$tmp"' EXIT
unset AGENT_DELEGATED_SESSION T3CODE_THREAD_ID
# 手元の T3 Code の記録を読まないよう、T3 の保存先をテスト用の場所に向ける。
export T3CODE_HOME=$tmp/t3
# T3 が起動した Codex の本体には、この目印が付く。
export CODEX_INTERNAL_ORIGINATOR_OVERRIDE="T3 Code"
fail=0

check() { # name expected-substring-or-! output
  local name=$1 want=$2 out=$3
  if [ "${want#!}" != "$want" ]; then
    case $out in *"${want#!}"*) echo "FAIL $name: '${want#!}' が出た"; fail=1 ;; *) echo "ok   $name" ;; esac
  else
    case $out in *"$want"*) echo "ok   $name" ;; *) echo "FAIL $name: '$want' が出ない"; fail=1 ;; esac
  fi
}

mkdir -p "$tmp/agent-shared/hooks/lib" "$tmp/state"
cp "$hook" "$tmp/agent-shared/hooks/kata-entry.sh"
cp "$(dirname "$hook")/lib/delegated-session.sh" "$tmp/agent-shared/hooks/lib/"
echo 7.0.2 > "$tmp/agent-shared/superpowers-imported-version"
git init -q --bare "$tmp/upstream.git"
git init -q "$tmp/work"
git -C "$tmp/work" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
tag() { git -C "$tmp/work" tag "$1" && git -C "$tmp/work" push -q "$tmp/upstream.git" "$1"; }
# 無人の取り込みの代わりに、起動された回数を数えて作業ディレクトリだけ作る。
cat > "$tmp/import-stub" <<'STUB'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/import-calls"
mkdir -p "$2/import-$1"; echo "running 0" > "$2/import-$1/status"
STUB
chmod +x "$tmp/import-stub"
# hook の入力の session_id は変数 session で変えられる。
run() {
  printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"startup"}\n' "${session:-s1}" |
    KATA_UPSTREAM_URL=$tmp/upstream.git KATA_UPSTREAM_STATE_DIR=$tmp/state KATA_IMPORT_CMD=$tmp/import-stub bash "$tmp/agent-shared/hooks/kata-entry.sh"
  sleep 0.3
}
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
codex_child=01a1f9ea-0000-7000-8000-00000000c0de
codex_parent=01a1f9ea-0000-7000-8000-0000000000ff
t3_db "$T3CODE_HOME" \
  thread:delegated-task:command%3Amcp%3Ax%3Adelegate-task%3Az $codex_child \
  00000000-0000-4000-8000-0000000000aa $codex_parent

tag v7.0.1; tag v7.0.2
out=$(run)
check "入口の案内を出す" "<kata-entry>" "$out"
check "同じ版なら通知しない" "!<superpowers-import>" "$out"
out=$(AGENT_DELEGATED_SESSION=1 run)
check "委譲された子には利用者への応答の案内を出さない" "!利用者への最初の応答" "$out"
check "委譲された子には依頼の範囲で進めることを伝える" "委譲された担当" "$out"
# T3 Code の delegate_task が起動した子は AGENT_DELEGATED_SESSION を持たず、スレッド ID で分かる。
out=$(T3CODE_THREAD_ID=thread:delegated-task:command%3Amcp%3Ax%3Adelegate-task%3Ay run)
check "T3 の委譲の子には利用者への応答の案内を出さない" "!利用者への最初の応答" "$out"
check "T3 の委譲の子には依頼の範囲で進めることを伝える" "委譲された担当" "$out"
out=$(T3CODE_THREAD_ID=00000000-0000-4000-8000-0000000000aa run)
check "T3 の利用者と話すスレッドには入口の案内を出す" "利用者への最初の応答" "$out"
# T3 は Codex の子にスレッド ID を hook の環境で渡さないため、T3 の記録で会話の属するスレッドを引く。
out=$(session=$codex_child run)
check "T3 の記録で委譲の子と分かる Codex の会話には利用者への応答の案内を出さない" "!利用者への最初の応答" "$out"
check "T3 の記録で委譲の子と分かる Codex の会話には依頼の範囲で進めることを伝える" "委譲された担当" "$out"
out=$(session=$codex_parent run)
check "T3 の利用者と話すスレッドの Codex の会話には入口の案内を出す" "利用者への最初の応答" "$out"
mkdir -p "$tmp/t3-broken/userdata"; echo 'not a database' > "$tmp/t3-broken/userdata/statev2.sqlite"
out=$(T3CODE_HOME=$tmp/t3-broken session=$codex_child run)
check "T3 の記録を読めなければ入口の案内を出す" "利用者への最初の応答" "$out"

tag v7.0.10
out=$(run)
check "確認から 30 日以内は通信せず前回の結果を使う" "!<superpowers-import>" "$out"

echo "0 7.0.2" > "$tmp/state/superpowers-upstream"
run > /dev/null
check "30 日を過ぎたら確認し、新しい版を記録する" "7.0.10" "$(cut -d' ' -f2 "$tmp/state/superpowers-upstream")"

check "新しい版の取り込みを無人で始める" "7.0.10" "$(cat "$tmp/import-calls" 2>/dev/null)"
check "取り込み中は通知しない" "!<superpowers-import>" "$(run)"
check "同じ版の取り込みは一度だけ起動する" "1" "$(wc -l < "$tmp/import-calls" | tr -d ' ')"

echo "failed 100" > "$tmp/state/import-7.0.10/status"
out=$(run)
check "失敗したら記録の場所を伝える" "失敗または停止した (記録: $tmp/state/import-7.0.10)" "$out"
check "新しい版を示す" "新しい版 7.0.10" "$out"
check "取り込み済みの版を示す" "取り込み済みは 7.0.2" "$out"
notice=$(sed -n '/<superpowers-import>/,/<\/superpowers-import>/p' <<<"$out")
check "依頼への回答を終えた後に伝えるよう指示する" "依頼への回答を終えた後" "$notice"
check "最初の応答への割り込みを指示しない" "!最初の応答" "$notice"
check "同じ失敗は二度通知しない" "!<superpowers-import>" "$(run)"
echo "failed 150" > "$tmp/state/import-7.0.10/status"
check "やり直しが再び失敗したら改めて通知する" "失敗または停止した" "$(run)"
sleep 300 & dead_pid=$!; kill $dead_pid; wait $dead_pid 2>/dev/null
echo "running 200 $dead_pid" > "$tmp/state/import-7.0.10/status"
check "記録が running のままプロセスが無ければ停止として伝える" "失敗または停止した" "$(run)"
echo "running 300 $$" > "$tmp/state/import-7.0.10/status"
check "やり直しの取り込み中は通知しない" "!<superpowers-import>" "$(run)"
echo "done 400" > "$tmp/state/import-7.0.10/status"
out=$(T3CODE_THREAD_ID=thread:delegated-task:x run)
check "T3 の委譲の子には通知しない" "!<superpowers-import>" "$out"
out=$(AGENT_DELEGATED_SESSION=1 run)
check "委譲の子セッションには通知しない" "!<superpowers-import>" "$out"
out=$(session=$codex_child run)
check "T3 の記録で委譲の子と分かる Codex の会話には通知しない" "!<superpowers-import>" "$out"
out=$(run)
check "終わったら報告と作業場所を伝える" "作業場所: $tmp/state/import-7.0.10/repo" "$out"
check "取り込み手順の文書の場所を示す" "$tmp/docs/agents.md" "$out"
check "終わった通知は一度だけ出す" "!<superpowers-import>" "$(run)"
sed -i.bak 's/^[0-9]*/0/' "$tmp/state/superpowers-upstream"
check "上流を確かめ直しても終わった通知を繰り返さない" "!<superpowers-import>" "$(run)"

rm -rf "$tmp/upstream.git"
echo "0 7.0.2" > "$tmp/state/superpowers-upstream"
out=$(run)
check "通信できなくても入口の案内は出す" "<kata-entry>" "$out"
check "通信できなければ時刻を更新しない" "0 7.0.2" "$(cat "$tmp/state/superpowers-upstream")"

exit $fail
