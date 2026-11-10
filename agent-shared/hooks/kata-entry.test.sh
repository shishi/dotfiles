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
run() { KATA_UPSTREAM_URL=$tmp/upstream.git KATA_UPSTREAM_STATE_DIR=$tmp/state bash "$tmp/agent-shared/hooks/kata-entry.sh"; }

tag v7.0.1; tag v7.0.2
out=$(run)
check "入口の案内を出す" "<kata-entry>" "$out"
check "同じ版なら通知しない" "!<superpowers-import>" "$out"

tag v7.0.10
out=$(run)
check "確認から 30 日以内は通信せず前回の結果を使う" "!<superpowers-import>" "$out"

echo "0 7.0.2" > "$tmp/state/superpowers-upstream"
out=$(run)
check "30 日を過ぎたら確認し、新しい版を通知する" "新しい版 7.0.10" "$out"
check "取り込み済みの版を示す" "取り込み済みは 7.0.2" "$out"
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
