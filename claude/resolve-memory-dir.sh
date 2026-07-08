#!/usr/bin/env bash
# claude-memory (個人永続記憶) の配置先を解決し、stdout に絶対パスを 1 行だけ出力する。
# ghq.root がある環境では <root>/github.com/shishi/claude-memory を使う。
# 旧デフォルト ~/dev/claude-memory からの自動移行 (mv) もここで行う。
# spec: docs/superpowers/specs/2026-07-07-claude-memory-ghq-design.md
#
# 入力はすべて環境変数:
#   CLAUDE_MEMORY_DIR  明示 override (最優先。移行はしない)
#   GHQ_ROOT           ghq root (gitconfig の ghq.root より優先)
#   DOTDIR             dotfiles リポジトリのパス (空なら移行しない = fail closed)
#   HOME / git global config
# exit contract: パスを決定できたら exit 0 + stdout 1 行。決定不能は非 0。警告は stderr。
set -u

REPO_PATH="github.com/shishi/claude-memory"

warn() { echo "resolve-memory-dir: $*" >&2; }

# 物理パスへ正規化 (symlink 比較用)。存在しないパスは空を返す。
canon() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

# 先頭 ~/ を $HOME へ展開し、相対パスを絶対化する。
# Git Bash では C:/... のような drive-letter 形式が来るため、cygpath が
# あればそれで POSIX 形式 (/c/...) へ変換する (setup.sh 側の「/ 始まり」
# 検証を単純に保つため)。
absolutize() {
  local p="$1"
  # 改行を含むパスは stdout 1 行契約を破るため即拒否
  case "$p" in
    *"
"*)
      warn "path contains a newline; refusing"
      return 1
      ;;
  esac
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in
    /*) ;;
    *)
      if command -v cygpath >/dev/null 2>&1; then
        p="$(cygpath -u -a -- "$p")" || return 1
      else
        p="$(pwd -P)/$p"
      fi
      ;;
  esac
  # 末尾スラッシュを除去 (例: GHQ_ROOT=~/dev/src/ → .../src//github.com/... を防ぐ)
  # ただし bare "/" は空にしない
  [ -n "${p%/}" ] && p="${p%/}"
  printf '%s\n' "$p"
}

# 1. 明示 override: 絶対化して返すだけ。移行はしない (devcontainer/CI の
#    一時パスへ記憶 repo を mv してしまう事故を防ぐ)。
if [ -n "${CLAUDE_MEMORY_DIR:-}" ]; then
  absolutize "$CLAUDE_MEMORY_DIR"
  exit $?
fi

# fallback も正規化する (Git Bash で HOME=C:/Users/... の場合に備え、
# stdout の「/ 始まり」契約を全経路で守る)
old="$(absolutize "$HOME/dev/claude-memory")" || exit 1

# 2. ghq root: GHQ_ROOT env → gitconfig ghq.root の先頭値 (ghq の primary root 仕様)。
#    --global 必須: 素の git config は cwd の repo-local config も読むため、
#    setup.sh の実行ディレクトリ次第で想定外の root を拾ってしまう。
ghq_root="${GHQ_ROOT:-}"
if [ -z "$ghq_root" ]; then
  ghq_root="$(git config --global --type=path --get-all ghq.root 2>/dev/null | head -n1 || true)"
fi

# 3. ghq root なし → 従来デフォルト
if [ -z "$ghq_root" ]; then
  printf '%s\n' "$old"
  exit 0
fi

ghq_root="$(absolutize "$ghq_root")" || exit 1
new="$ghq_root/$REPO_PATH"

if [ "$new" = "$old" ]; then
  printf '%s\n' "$new"
  exit 0
fi

# --- 旧デフォルトからの移行判定 ---
# 削除・上書きは一切しない。迷ったら「動いている旧パスを返す」に倒す。
link="${DOTDIR:+${DOTDIR}/claude/memory}"

# 旧パスが本物の claude-memory clone か (anchored 完全一致。緩い部分一致だと
# notshishi/claude-memory 等の near-match を誤って mv してしまう)
is_claude_memory_clone() {
  local dir="$1" url
  [ -d "$dir/.git" ] || return 1
  url="$(git -C "$dir" remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    "git@github.com:shishi/claude-memory" | "git@github.com:shishi/claude-memory.git" | \
    "ssh://git@github.com/shishi/claude-memory" | "ssh://git@github.com/shishi/claude-memory.git" | \
    "https://github.com/shishi/claude-memory" | "https://github.com/shishi/claude-memory.git")
      return 0 ;;
  esac
  return 1
}

if [ -d "$new" ]; then
  if [ -d "$old" ] && [ ! -L "$old" ]; then
    # 両方存在: 現に使われている側を維持する。symlink で判定できなければ
    # 旧を維持 (新が古い clone だと未 push の記憶が orphan になるため)。
    warn "both $old and $new exist; not touching either. resolve manually."
    if [ -n "$link" ] && [ -L "$link" ]; then
      cur="$(canon "$link")"
      if [ -n "$cur" ] && [ "$cur" = "$(canon "$new")" ]; then
        printf '%s\n' "$new"; exit 0
      fi
      if [ -n "$cur" ] && [ "$cur" = "$(canon "$old")" ]; then
        printf '%s\n' "$old"; exit 0
      fi
    fi
    printf '%s\n' "$old"
    exit 0
  fi
  printf '%s\n' "$new"
  exit 0
fi

# 新パス未存在・旧パスに実体なし → fresh clone 先として新パス
if [ ! -d "$old" ] || [ -L "$old" ]; then
  printf '%s\n' "$new"
  exit 0
fi

# 新パスが「ディレクトリ以外の何か」(regular file / broken symlink) の場合は
# mv の挙動が未定義に壊れる (上書き・symlink 先への移動等) ため移行しない
if [ -e "$new" ] || [ -L "$new" ]; then
  warn "$new exists but is not a usable directory; skip migration. fix manually."
  printf '%s\n' "$old"
  exit 0
fi

# 旧パスあり・新パス未存在: 安全条件をすべて満たす場合のみ mv 移行
if [ -z "${DOTDIR:-}" ]; then
  warn "DOTDIR not set; cannot verify claude/memory symlink. skip migration."
  printf '%s\n' "$old"
  exit 0
fi
if [ -e "$link" ] && [ ! -L "$link" ]; then
  warn "$link is a real directory (not a symlink); skip migration. fix manually."
  printf '%s\n' "$old"
  exit 0
fi
if ! is_claude_memory_clone "$old"; then
  warn "$old is not a clone of $REPO_PATH; skip migration."
  printf '%s\n' "$old"
  exit 0
fi
if ! mkdir -p "$(dirname "$new")"; then
  warn "cannot create $(dirname "$new"); skip migration."
  printf '%s\n' "$old"
  exit 0
fi
if mv "$old" "$new" 2>/dev/null && [ -d "$new/.git" ]; then
  warn "migrated $old -> $new"
  printf '%s\n' "$new"
  exit 0
fi
warn "migration $old -> $new failed"
if [ -d "$old" ]; then
  printf '%s\n' "$old"
  exit 0
fi
# 旧も新も使える状態でない → パス決定不能
exit 1
