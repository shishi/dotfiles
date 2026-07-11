#!/usr/bin/env bash
# SessionStart hook: 個人永続記憶(グローバル索引 + プロジェクト記憶)を注入する。
# どんな失敗でも exit 0 でセッション起動を阻害しない(異常は警告テキストで伝える)。
# usage: inject-memory.sh [MEMORY_DIR]   省略時: ~/.claude/memory
set -u

MEMORY_DIR="${1:-${HOME}/.claude/memory}"

# 壊れた link: ディレクトリエントリ自体は存在するのに先が解決できない。
# POSIX symlink は -L で判定できるが、Windows junction は git-bash の -L で
# 拾えない場合があるため、「親ディレクトリにエントリが在るのに -e が偽」も
# 壊れ link とみなす。「記憶が静かに消えたまま動き続ける」事故の検知が目的。
if [ ! -e "$MEMORY_DIR" ]; then
  if [ -L "$MEMORY_DIR" ] \
    || ls -A "$(dirname "$MEMORY_DIR")" 2>/dev/null | grep -qxF "$(basename "$MEMORY_DIR")"; then
    echo "<personal-memory-warning>記憶ディレクトリの link が壊れています: ${MEMORY_DIR}(リンク先が存在しない)</personal-memory-warning>"
  fi
  exit 0
fi

# --- git-state aware 読み取りの準備 ---
# 記憶ディレクトリが git repo(root)のときは、MEMORY.md の存在確認より先に
# 健全性を検査する(編集途中で MEMORY.md が消えている dirty repo を無言スキップに
# 落とさない)。健全なら commit を固定し、以降は snapshot から読む。
# repo でない場合(テスト環境など)は従来どおりファイルを直接読む。
snapshot=""
ahead_warn=""
if [ -e "${MEMORY_DIR}/.git" ]; then
  branch=$(git -C "$MEMORY_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\r')
  gitdir=$(git -C "$MEMORY_DIR" rev-parse --absolute-git-dir 2>/dev/null | tr -d '\r')
  porcelain=$(git -C "$MEMORY_DIR" status --porcelain 2>/dev/null)
  unhealthy=""
  if [ "$branch" != "main" ]; then
    unhealthy="ブランチが main ではない (${branch})"
  elif [ -n "$gitdir" ] && { [ -e "$gitdir/rebase-merge" ] || [ -e "$gitdir/rebase-apply" ] || [ -e "$gitdir/MERGE_HEAD" ]; }; then
    unhealthy="rebase/merge が進行中"
  elif [ -n "$gitdir" ] && [ -d "$gitdir/memory-write.lock" ]; then
    unhealthy="write lock あり(他エージェントが書き込み中)"
  elif [ -n "$porcelain" ]; then
    unhealthy="worktree が dirty(編集途中の可能性)"
  fi
  if [ -n "$unhealthy" ]; then
    echo "<personal-memory-warning>記憶 repo が不健全なため注入をスキップ: ${unhealthy}(${MEMORY_DIR})</personal-memory-warning>"
    exit 0
  fi
  # チェック後に commit を固定(直後に書き込みが始まっても編集途中の worktree を
  # 読まない。注入は常に committed 内容のみ)
  snapshot=$(git -C "$MEMORY_DIR" rev-parse HEAD 2>/dev/null | tr -d '\r')
  # 未 push commit はローカルに実在する確定済み記憶なので注入するが、警告を添える
  ahead=$(git -C "$MEMORY_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null | tr -d '\r')
  case "$ahead" in
    ''|0|*[!0-9]*) : ;;
    *) ahead_warn="⚠ 未 push の記憶 commit が ${ahead} 件あります(前回 push 失敗の可能性。次の書き込み前に解消すること)" ;;
  esac
fi

emit_file() { # $1=repo 相対パス
  if [ -n "$snapshot" ]; then
    git -C "$MEMORY_DIR" show "${snapshot}:$1" 2>/dev/null
  else
    cat "${MEMORY_DIR}/$1" 2>/dev/null
  fi
}
has_file() { # $1=repo 相対パス
  if [ -n "$snapshot" ]; then
    git -C "$MEMORY_DIR" cat-file -e "${snapshot}:$1" 2>/dev/null
  else
    [ -f "${MEMORY_DIR}/$1" ]
  fi
}

# 記憶未導入(索引なし)は正常系として無言スキップ
has_file "MEMORY.md" || exit 0

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
echo "個人永続記憶。詳細は ${MEMORY_DIR}/ 配下を必要時に Read で開くこと。"
echo "現在のプロジェクト slug: ${slug}(プロジェクト記憶: projects/${slug}.md)"
[ -n "$ahead_warn" ] && echo "$ahead_warn"
echo ""
emit_file "MEMORY.md"
if has_file "projects/${slug}.md"; then
  echo ""
  echo "## プロジェクト記憶 (${slug})"
  emit_file "projects/${slug}.md"
fi
echo "</personal-memory>"
exit 0
