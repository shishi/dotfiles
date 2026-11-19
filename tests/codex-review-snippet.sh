#!/usr/bin/env bash
# codex-review の手順 3 のコード片を、bash と zsh の両方で実際に走らせて確かめる。
# Claude Code の Bash ツールや Codex は利用者のシェル (zsh など) でコマンドを実行するため、
# bash だけで動く書き方だと codex の終了コードが空になり、実行記録が残らない。
# codex と codex-model は偽物に差し替え、記録は一時の XDG_STATE_HOME に書かせる。
# 使い方: bash tests/codex-review-snippet.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
skill=$root/claude/skills/codex-review/SKILL.md
tmp=$(mktemp -d "${TMPDIR:-/tmp}/codex-review snippet.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0

# 「既定はこの形」の直後の bash コードブロックを取り出す。
awk '/既定はこの形/ { want = 1; next }
     want && /^ *```bash/ { inside = 1; next }
     inside && /^ *```/ { exit }
     inside { sub(/^   /, ""); print }' "$skill" > "$tmp/snippet"
[ -s "$tmp/snippet" ] || { echo "FAIL コード片を取り出せない"; exit 1; }

mkdir -p "$tmp/home/.agent-shared/bin" "$tmp/bin"
ln -s "$root/agent-shared/bin/agent-run-record.sh" "$tmp/home/.agent-shared/bin/agent-run-record.sh"
printf '#!/bin/sh\necho stub-model\n' > "$tmp/home/.agent-shared/bin/codex-model"
# 偽の codex: -o の後ろのファイルへ本文を書き、イベントを 1 行出し、STUB_RC で終わる。
cat > "$tmp/bin/codex" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  [ "$1" = -o ] && { shift; printf 'レビュー本文\n' > "$1"; }
  shift
done
cat > /dev/null
echo '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}'
exit "${STUB_RC:-0}"
STUB
chmod +x "$tmp/home/.agent-shared/bin/codex-model" "$tmp/bin/codex"

run() { # shell stub_rc [tee-fails] → 終了コードを出力し、記録の exit_code を $tmp/last、標準出力の最終行を $tmp/body に残す
  local shell=$1 rc=$2 dir=$tmp/run-$1-$2-${3:-}
  mkdir -p "$dir/state"
  # tee だけを失敗させる: events を読み取り専用で先に作る。tee は開けずに 1 で終わるが、ファイルはあるので記録は作られる
  [ -n "${3:-}" ] && { : > "$dir/events"; chmod 444 "$dir/events"; }
  printf 'prompt\n' > "$dir/input"
  REVIEW_INPUT=$dir/input REVIEW_OUTPUT=$dir/out REVIEW_EVENTS=$dir/events REVIEW_LOG=$dir/log \
    HOME=$tmp/home XDG_STATE_HOME=$dir/state PATH=$tmp/bin:$PATH STUB_RC=$rc \
    "$shell" "$tmp/snippet" > "$dir/stdout" 2>/dev/null
  echo $?
  tail -n 1 "$dir/stdout" > "$tmp/body"
  record=$(cat "$dir/out.run-record" 2>/dev/null)
  if [ -n "$record" ] && [ -f "$record" ]; then jq -r '.exit_code' "$record"; else echo none; fi > "$tmp/last"
}
check() { # name want got
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want=$2 got=$3"; fail=1; fi
}

for shell in bash zsh; do
  command -v "$shell" > /dev/null || { echo "skip $shell が無い"; continue; }
  check "$shell: codex が成功したら 0 で終わる" 0 "$(run "$shell" 0)"
  check "$shell: 成功の終了コードを記録する" 0 "$(cat "$tmp/last")"
  check "$shell: 成功したらレビュー本文を出力する" レビュー本文 "$(cat "$tmp/body")"
  check "$shell: codex が失敗したら失敗として終わる" 97 "$(run "$shell" 3)"
  check "$shell: 失敗の終了コードを記録する" 3 "$(cat "$tmp/last")"
  check "$shell: events を保存できなければ失敗として終わる" 97 "$(run "$shell" 0 tee-fails)"
  check "$shell: events を保存できなかったことを記録する" 1 "$(cat "$tmp/last")"
done

exit $fail
