#!/usr/bin/env bash
# claude/skills と codex/skills の両方に存在する skill は、エージェント固有名
# (claude / codex)とホスト固有の frontmatter を除いて同一内容である契約を検証する。
# 両ホストが各自のディレクトリから skill を発見するため、配布間のドリフトを検査する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PASS=0
FAIL=0

normalize() { # $1=file
  # Codex の policy を宣言する agents/openai.yaml は同ファイル同士で比較する。
  LC_ALL=C awk '
    $0 == "---" { delimiters++ }
    !(delimiters == 1 && /^disable-model-invocation:/) { print }
  ' "$1" | LC_ALL=C sed -e 's/[Cc][Ll][Aa][Uu][Dd][Ee]/AGENT/g' -e 's/[Cc][Oo][Dd][Ee][Xx]/AGENT/g'
}

for dir in "$REPO"/codex/skills/*/; do
  name=$(basename "$dir")
  other="$REPO/claude/skills/$name"
  [ -d "$other" ] || continue

  # ファイル構成の一致
  files_codex=$(cd "$dir" && find . -type f | sort)
  files_claude=$(cd "$other" && find . -type f | sort)
  if [ "$files_codex" != "$files_claude" ]; then
    echo "NG: $name (file sets differ)"
    FAIL=$((FAIL + 1))
    continue
  fi

  drift=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f="${f#./}"
    if ! diff -u <(normalize "$dir/$f") <(normalize "$other/$f") >/dev/null; then
      echo "NG: $name ($f differs beyond agent names)"
      drift=1
    fi
  done <<<"$files_codex"

  if [ "$drift" = 0 ]; then
    PASS=$((PASS + 1))
    echo "ok: $name"
  else
    FAIL=$((FAIL + 1))
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
