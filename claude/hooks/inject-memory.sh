#!/usr/bin/env bash
# SessionStart hook: 個人永続記憶(グローバル索引 + プロジェクト記憶)を注入する。
# どんな失敗でも無出力・exit 0 でセッション起動を阻害しない。
set -u

MEMORY_DIR="${HOME}/.claude/memory"
[ -f "${MEMORY_DIR}/MEMORY.md" ] || exit 0

input=$(cat 2>/dev/null || true)
cwd=""
if command -v jq >/dev/null 2>&1; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
fi
[ -n "$cwd" ] || cwd="$PWD"
if command -v cygpath >/dev/null 2>&1; then
  cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
fi

slugify() { printf '%s' "$1" | tr ':/\\' '-'; }

normalize_remote() {
  # ssh/https/scp 形式を host/owner/repo へ正規化(.git / user@ / scheme を除去)
  local url="$1"
  url="${url%.git}"
  url="${url#ssh://}"
  url="${url#git+ssh://}"
  url="${url#git://}"
  url="${url#https://}"
  url="${url#http://}"
  url="${url#*@}"
  url="${url//:/\/}"
  printf '%s' "$url"
}

slug=""
origin=$(git -C "$cwd" remote get-url origin 2>/dev/null | tr -d '\r' || true)
if [ -n "$origin" ]; then
  slug=$(slugify "$(normalize_remote "$origin")")
fi

if [ -z "$slug" ]; then
  ghq_root=$({ ghq root 2>/dev/null || git config --get ghq.root 2>/dev/null; } | head -1 | tr -d '\r')
  ghq_root="${ghq_root/#\~/$HOME}"
  [ -n "$ghq_root" ] || ghq_root="$HOME/ghq"
  if command -v cygpath >/dev/null 2>&1; then
    ghq_root=$(cygpath -u "$ghq_root" 2>/dev/null || printf '%s' "$ghq_root")
  fi
  case "$cwd" in
    "$ghq_root"/*) slug=$(slugify "${cwd#"$ghq_root"/}") ;;
  esac
fi

[ -n "$slug" ] || slug=$(slugify "$cwd")

echo "<personal-memory>"
echo "個人永続記憶。詳細は ~/.claude/memory/ 配下を必要時に Read で開くこと。"
echo "現在のプロジェクト slug: ${slug}(プロジェクト記憶: projects/${slug}.md)"
echo ""
cat "${MEMORY_DIR}/MEMORY.md"
project_file="${MEMORY_DIR}/projects/${slug}.md"
if [ -f "$project_file" ]; then
  echo ""
  echo "## プロジェクト記憶 (${slug})"
  cat "$project_file"
fi
echo "</personal-memory>"
exit 0
