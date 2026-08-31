#!/usr/bin/env bash
# claude/skills と codex/skills の両方に存在する skill は、エージェント固有名
# (claude / codex)の差し替えを除いて同一内容である契約を検証する。
# skill はディレクトリ走査で発見され path 参照できないため複製配置が必然であり、
# この検査が複製間の意味的ドリフトを検出する唯一の機構になる。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PASS=0
FAIL=0

normalize() { # $1=file
  LC_ALL=C sed -e 's/[Cc][Ll][Aa][Uu][Dd][Ee]/AGENT/g' -e 's/[Cc][Oo][Dd][Ee][Xx]/AGENT/g' "$1"
}

# 固有名の差し替えを超えて、プラットフォーム機構の違いで本文が構造的に異なる
# ペア。除外は「意図した差」の宣言であり、追加時は理由を書く。
# - grill-me: Claude は Skill tool 呼び出し + disable-model-invocation、
#   codex は相対パスで grilling を読む指示
exempt="grill-me"

for dir in "$REPO"/codex/skills/*/; do
  name=$(basename "$dir")
  other="$REPO/claude/skills/$name"
  [ -d "$other" ] || continue
  case " $exempt " in *" $name "*) continue ;; esac

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
