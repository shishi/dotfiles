#!/usr/bin/env bash
# Herdr の CLI が出す手引き (--skill) に repo の上書きを重ね、Claude Code / Codex の skill を生成する。
# 手引きは端末に入っている CLI の版に合わせて変わるため、生成物は Git で管理しない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)" || exit 1
OVERLAYS="$REPO_ROOT/agent-shared/skill-overlays"

warn() { printf 'herdr-skills: WARN %s\n' "$*" >&2; }

generate() { # $1=skill name, $2=CLI that prints the manual
  local name="$1" cli="$2" overlay="$OVERLAYS/$1.md" manual agent dir tmp
  if ! command -v "$cli" >/dev/null 2>&1; then
    printf 'herdr-skills: %s is not installed; kept %s as is\n' "$cli" "$name"
    return 0
  fi
  [ -f "$overlay" ] || { warn "$overlay is missing"; return 1; }
  manual="$(mktemp "${TMPDIR:-/tmp}/herdr-skills.XXXXXX")" || return 1
  # 失敗や空の出力で既存の skill を壊さないよう、手引きを取得できたときだけ置き換える。
  if ! "$cli" --skill >"$manual" 2>/dev/null || [ ! -s "$manual" ]; then
    rm -f "$manual"
    warn "$cli --skill did not print a manual; kept $name as is"
    return 1
  fi
  for agent in claude codex; do
    dir="$REPO_ROOT/$agent/skills/$name"
    mkdir -p "$dir" || { rm -f "$manual"; return 1; }
    tmp="$(mktemp "$dir/.SKILL.md.XXXXXX")" || { rm -f "$manual"; return 1; }
    # 生成物を直しても次の生成で消えるため、読んだエージェントが編集先を取り違えないよう本文に示す。
    if ! { cat "$overlay" && printf '\n<!-- この SKILL.md は herdr-skills.sh が生成します。直接編集せず、agent-shared/skill-overlays/%s.md を編集します。 -->\n\n' "$name" && cat "$manual"; } >"$tmp" || ! mv "$tmp" "$dir/SKILL.md"; then
      rm -f "$tmp" "$manual"
      return 1
    fi
  done
  rm -f "$manual"
}

case "${1:-}" in
  sync)
    failed=0
    generate herdr-core hc || failed=1
    generate herdr-app herdr-app || failed=1
    exit "$failed"
    ;;
  *)
    printf 'usage: herdr-skills.sh sync\n' >&2
    exit 1
    ;;
esac
