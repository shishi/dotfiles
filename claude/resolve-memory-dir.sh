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

# (移行ロジックは Task 2 で追加。現時点では新パスをそのまま返す)
printf '%s\n' "$new"
exit 0
