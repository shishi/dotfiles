#!/usr/bin/env bash
# skill の由来の一覧 (agent-shared/skill-sources.tsv) が、実際の skill と管理の仕組みに合っていることを確かめる。
# 由来の一覧に無い skill や、種類と Git 管理が食い違う skill があると、編集してよいファイルを取り違える。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LEDGER="$REPO/agent-shared/skill-sources.tsv"
MANAGED="$REPO/agent-shared/managed-skills.tsv"
OVERLAYS="$REPO/agent-shared/skill-overlays"
TAB=$'\t'
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }

if [ ! -f "$LEDGER" ]; then
  echo "NG: $LEDGER is missing"
  exit 1
fi

rows() { grep -v -e '^[[:space:]]*$' -e '^#' "$1"; }
kind_of() { rows "$LEDGER" | awk -F "$TAB" -v name="$1" '$1 == name { print $2; exit }'; }
tracked() { # $1=agent, $2=name
  git -C "$REPO" ls-files --error-unmatch -- "$1/skills/$2/SKILL.md" >/dev/null 2>&1
}
managed_repo() { rows "$MANAGED" | awk -F "$TAB" -v name="$1" '$1 == name { print $2; exit }'; }
licensed() { # $1=出所の URL: 著作権表示のファイルが Source 行に挙げている
  grep -h '^Source:' "$REPO"/claude/skills/*.LICENSE 2>/dev/null |
    grep -oE 'https?://[^ ,)]+' | grep -qxF -- "$1"
}

# 一覧の各行は、種類に応じた Git 管理と管理の仕組みに合っている。
seen=
while IFS="$TAB" read -r name kind source extra; do
  if [ -z "$name" ] || [ -z "$kind" ] || [ -z "$source" ] || [ -n "$extra" ]; then
    ng "$name (a row needs exactly: name, kind, source)"
    continue
  fi
  case "$TAB$seen$TAB" in *"$TAB$name$TAB"*) ng "$name (listed twice)"; continue ;; esac
  seen="$seen$TAB$name"

  case "$kind" in
    own | adapted | entry)
      if ! tracked claude "$name" && ! tracked codex "$name"; then
        ng "$name ($kind, but SKILL.md is not tracked by Git)"
        continue
      fi
      if [ "$kind" != own ] && [ "$source" = - ]; then
        ng "$name ($kind needs its upstream in the source column)"
        continue
      fi
      if [ "$kind" = adapted ]; then
        unlicensed=
        while IFS= read -r url; do
          [ -z "$url" ] || licensed "$url" || unlicensed="$url"
        done <<<"${source//,/$'\n'}"
        if [ -n "$unlicensed" ]; then
          ng "$name (adapted from $unlicensed, but no claude/skills/*.LICENSE names it as Source)"
          continue
        fi
      fi
      ;;
    managed)
      if tracked claude "$name" || tracked codex "$name"; then
        ng "$name (managed, but SKILL.md is tracked by Git)"
        continue
      fi
      if [ -z "$(managed_repo "$name")" ]; then
        ng "$name (managed, but not in managed-skills.tsv)"
        continue
      fi
      if [ "$source" != "https://github.com/$(managed_repo "$name")" ]; then
        ng "$name (managed, but the source differs from managed-skills.tsv)"
        continue
      fi
      ;;
    generated)
      if tracked claude "$name" || tracked codex "$name"; then
        ng "$name (generated, but SKILL.md is tracked by Git)"
        continue
      fi
      if [ ! -f "$OVERLAYS/$name.md" ]; then
        ng "$name (generated, but agent-shared/skill-overlays/$name.md is missing)"
        continue
      fi
      ;;
    *)
      ng "$name (unknown kind: $kind)"
      continue
      ;;
  esac
  ok
done < <(rows "$LEDGER")

# Git が追跡する skill と、作業ツリーにある skill は、すべて由来の一覧に載っている。
# ツール自身が置く symlink は、この repo が管理する skill ではないので数えない。
names=$(
  {
    git -C "$REPO" ls-files -- 'claude/skills/*/SKILL.md' 'codex/skills/*/SKILL.md' | cut -d/ -f3
    for dir in "$REPO"/claude/skills/*/ "$REPO"/codex/skills/*/; do
      [ -d "$dir" ] && [ ! -L "${dir%/}" ] && basename "$dir"
    done
  } | LC_ALL=C sort -u
)
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ -n "$(kind_of "$name")" ]; then ok; else ng "$name (not in skill-sources.tsv)"; fi
done <<<"$names"

# 生成する skill は、生成前の clone 直後でも overlay から分かる。
for overlay in "$OVERLAYS"/*.md; do
  [ -f "$overlay" ] || continue
  name=$(basename "$overlay" .md)
  if [ "$(kind_of "$name")" = generated ]; then ok; else ng "$name (has an overlay, but is not generated in skill-sources.tsv)"; fi
done

# managed-skills.sh が取得する skill は、由来の一覧でも managed になっている。
while IFS="$TAB" read -r name _; do
  [ -n "$name" ] || continue
  if [ "$(kind_of "$name")" = managed ]; then ok; else ng "$name (in managed-skills.tsv, but not managed in skill-sources.tsv)"; fi
done < <(rows "$MANAGED")

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
