#!/usr/bin/env bash
# kata-entry.sh の上流の新しい版の通知を、ローカルの bare repo を上流に見立てて確かめる。
# 使い方: bash agent-shared/hooks/kata-entry.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
hook=${KATA_ENTRY_HOOK:-$here/kata-entry.sh}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kata-entry-test.XXXXXX") || exit 1
tmp=$(cd -P "$tmp" && pwd) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # name expected-substring-or-! output
  local name=$1 want=$2 out=$3
  if [ "${want#!}" != "$want" ]; then
    case $out in *"${want#!}"*) echo "FAIL $name: '${want#!}' が出た"; fail=1 ;; *) echo "ok   $name" ;; esac
  else
    case $out in *"$want"*) echo "ok   $name" ;; *) echo "FAIL $name: '$want' が出ない"; fail=1 ;; esac
  fi
}

mkdir -p "$tmp/agent-shared/hooks" "$tmp/state"
cp "$hook" "$tmp/agent-shared/hooks/kata-entry.sh"
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
run() { KATA_UPSTREAM_URL=$tmp/upstream.git KATA_UPSTREAM_STATE_DIR=$tmp/state KATA_IMPORT_CMD=$tmp/import-stub bash "$tmp/agent-shared/hooks/kata-entry.sh"; sleep 0.3; }

tag v7.0.1; tag v7.0.2
out=$(run)
check "入口の案内を出す" "<kata-entry>" "$out"
check "同じ版なら通知しない" "!<superpowers-import>" "$out"
out=$(AGENT_DELEGATED_SESSION=1 run)
check "委譲された子には工程 1 から始める入口を出さない" "!工程 1 の kata-design" "$out"
check "委譲された子には依頼の範囲で進めることを伝える" "委譲された担当" "$out"

tag v7.0.10
out=$(run)
check "確認から 30 日以内は通信せず前回の結果を使う" "!<superpowers-import>" "$out"

echo "0 7.0.2" > "$tmp/state/superpowers-upstream"
out=$(run)
check "30 日を過ぎたら確認し、新しい版を通知する" "新しい版 7.0.10" "$out"
check "取り込み済みの版を示す" "取り込み済みは 7.0.2" "$out"

check "新しい版の取り込みを無人で始める" "7.0.10" "$(cat "$tmp/import-calls" 2>/dev/null)"
check "取り込み中であることを伝える" "無人の取り込みを進めている" "$(run)"
check "同じ版の取り込みは一度だけ起動する" "1" "$(wc -l < "$tmp/import-calls" | tr -d ' ')"

echo "failed 0" > "$tmp/state/import-7.0.10/status"
check "失敗したら記録の場所を伝える" "失敗または停止した (記録: $tmp/state/import-7.0.10)" "$(run)"
sleep 300 & dead_pid=$!; kill $dead_pid; wait $dead_pid 2>/dev/null
echo "running 0 $dead_pid" > "$tmp/state/import-7.0.10/status"
check "記録が running のままプロセスが無ければ停止として伝える" "失敗または停止した" "$(run)"
echo "running 0 $$" > "$tmp/state/import-7.0.10/status"
check "プロセスが生きていれば取り込み中として伝える" "無人の取り込みを進めている" "$(run)"
echo "done 0" > "$tmp/state/import-7.0.10/status"
out=$(run)
check "終わったら報告と作業場所を伝える" "作業場所: $tmp/state/import-7.0.10/repo" "$out"
check "取り込み手順の文書の場所を示す" "$tmp/docs/agents.md" "$out"

out=$(AGENT_DELEGATED_SESSION=1 run)
check "委譲の子セッションには通知しない" "!<superpowers-import>" "$out"

rm -rf "$tmp/upstream.git"
out=$(run)
check "通知は次の確認まで続く" "新しい版 7.0.10" "$out"

echo "0 7.0.2" > "$tmp/state/superpowers-upstream"
out=$(run)
check "通信できなくても入口の案内は出す" "<kata-entry>" "$out"
check "通信できなければ時刻を更新しない" "0 7.0.2" "$(cat "$tmp/state/superpowers-upstream")"

exit $fail
