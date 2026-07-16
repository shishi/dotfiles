#!/usr/bin/env bash
# agent-memory (個人永続記憶) の配置先を解決し、stdout に絶対パスを 1 行だけ出力する。
# ghq.root がある環境では <root>/github.com/shishi/agent-memory を使い、なければ
# 既定 root ~/dev/src 配下を返す。配置先の「解決」だけを行い、実体の移動はしない。
# 旧 claude-memory からの移行は spec の手順で手動実施する
# (docs/superpowers/specs/2026-07-11-agent-memory-design.md)。
#
# 入力はすべて環境変数:
#   AGENT_MEMORY_DIR  明示 override (最優先)
#   GHQ_ROOT          ghq root (gitconfig の ghq.root より優先)
#   HOME / git global config
# exit contract: パスを決定できたら exit 0 + stdout 1 行。決定不能は非 0。警告は stderr。
set -u

REPO_PATH="github.com/shishi/agent-memory"
# ghq.root を決定できないときのフォールバック root。
# origin/master のハードコード既定 ~/dev/src/github.com/shishi/agent-memory と一致させる。
DEFAULT_ROOT="$HOME/dev/src"

warn() { echo "resolve-memory-dir: $*" >&2; }

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
  # 末尾スラッシュを除去 (例: GHQ_ROOT=~/dev/src/ → .../src//github.com/... を防ぐ)
  # ただし bare "/" は空にしない
  [ -n "${p%/}" ] && p="${p%/}"
  # 改行を含むパスは stdout 1 行契約を破るため即拒否 (展開後に検証)
  case "$p" in
    *"
"*)
      warn "path contains a newline; refusing"
      return 1
      ;;
  esac
  printf '%s\n' "$p"
}

# 1. 明示 override: 絶対化して返すだけ。
if [ -n "${AGENT_MEMORY_DIR:-}" ]; then
  absolutize "$AGENT_MEMORY_DIR"
  exit $?
fi

# 2. ghq root: GHQ_ROOT env → gitconfig ghq.root の先頭値 (ghq の primary root 仕様)。
#    --global 必須: 素の git config は cwd の repo-local config も読むため、
#    setup.sh の実行ディレクトリ次第で想定外の root を拾ってしまう。
ghq_root="${GHQ_ROOT:-}"
if [ -z "$ghq_root" ]; then
  ghq_root="$(git config --global --type=path --get-all ghq.root 2>/dev/null | head -n1 || true)"
fi

# 3. ghq root なし → 既定 root
if [ -z "$ghq_root" ]; then
  ghq_root="$DEFAULT_ROOT"
fi

ghq_root="$(absolutize "$ghq_root")" || exit 1
printf '%s\n' "$ghq_root/$REPO_PATH"
exit 0
