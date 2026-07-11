#!/bin/bash

# Git Bash/MSYS では素の ln -s が symlink ではなく「コピー」を作るため、
# native symlink を強制する (要: Windows 開発者モード or 管理者実行)。
# export しておけば以降の ln 呼び出しすべてに効く。mac/Linux では何もしない。
case "$(uname -s)" in
  MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

if [ -d /.jbdevcontainer ]; then
  XDG_CONFIG_HOME=/.jbdevcontainer/config
elif [ -z $XDG_CONFIG_HOME ]; then
  XDG_CONFIG_HOME=$HOME/.config
  mkdir -p ~/.config
fi

DOTDIR=$(realpath $(dirname "$0"))
#$EMACSDIR=~/dev/src/github.com/shishi/emacs

if [ "$REMOTE_CONTAINERS" != true ]; then
  if [ -L ${XDG_CONFIG_HOME}/wezterm ]; then
    rm ${XDG_CONFIG_HOME}/wezterm
    ln -sf ${DOTDIR}/wezterm ${XDG_CONFIG_HOME}/wezterm
  elif [ -d ${XDG_CONFIG_HOME}/wezterm ]; then
    rm -fr ${XDG_CONFIG_HOME}/wezterm
    ln -sf ${DOTDIR}/wezterm ${XDG_CONFIG_HOME}/wezterm
  else
    ln -sf ${DOTDIR}/wezterm ${XDG_CONFIG_HOME}/wezterm
  fi

  if [ -L ~/.emacs.d ]; then
    rm ~/.emacs.d
    ln -sf $(dirname ${DOTDIR})/emacs ~/.emacs.d
  elif [ -d ~/.emacs.d ]; then
    git -C $(dirname ${DOTDIR}) clone git@github.com:shishi/emacs.git
    rm -fr ~/.emacs.d
    ln -sf $(dirname ${DOTDIR})/emacs ~/.emacs.d
  else
    git -C $(dirname ${DOTDIR}) clone git@github.com:shishi/emacs.git
    ln -sf $(dirname ${DOTDIR})/emacs ~/.emacs.d
  fi
fi

if [ -L ${XDG_CONFIG_HOME}/fish ]; then
  rm ${XDG_CONFIG_HOME}/fish
  ln -sf ${DOTDIR}/fish ${XDG_CONFIG_HOME}/fish
elif [ -d ${XDG_CONFIG_HOME}/fish ]; then
  rm -fr ${XDG_CONFIG_HOME}/fish
  ln -sf ${DOTDIR}/fish ${XDG_CONFIG_HOME}/fish
else
  ln -sf ${DOTDIR}/fish ${XDG_CONFIG_HOME}/fish
fi

if [ -L ${XDG_CONFIG_HOME}/nvim ]; then
  rm ${XDG_CONFIG_HOME}/nvim
  ln -sf ${DOTDIR}/nvim ${XDG_CONFIG_HOME}/nvim
elif [ -d ${XDG_CONFIG_HOME}/nvim ]; then
  rm -fr ${XDG_CONFIG_HOME}/nvim
  ln -sf ${DOTDIR}/nvim ${XDG_CONFIG_HOME}/nvim
else
  ln -sf ${DOTDIR}/nvim ${XDG_CONFIG_HOME}/nvim
fi

if [ -L ${XDG_CONFIG_HOME}/helix ]; then
  rm ${XDG_CONFIG_HOME}/helix
  ln -sf ${DOTDIR}/helix ${XDG_CONFIG_HOME}/helix
elif [ -d ${XDG_CONFIG_HOME}/helix ]; then
  rm -fr ${XDG_CONFIG_HOME}/helix
  ln -sf ${DOTDIR}/helix ${XDG_CONFIG_HOME}/helix
else
  ln -sf ${DOTDIR}/helix ${XDG_CONFIG_HOME}/helix
fi

if [ -L ~/.claude ]; then
  rm ~/.claude
  ln -sf ${DOTDIR}/claude ~/.claude
elif mountpoint -q ~/.claude 2>/dev/null \
  || grep -qE "[[:space:]]$HOME/\.claude[[:space:]]" /proc/mounts 2>/dev/null; then
  # ~/.claude が bind mount (devcontainer等) の場合は破壊しない。
  # mountpoint コマンドで検出できない bind mount (Docker Desktop の virtiofs/9p 等) も
  # /proc/mounts のフォールバックで拾う。
  # bind mount 越しに ${DOTDIR}/claude/ の中身は既に同じ実体を指しているので、symlink化不要。
  echo "setup.sh: ~/.claude is a mount point; skip claude symlink (functional equivalent already in place)"
elif [ -d ~/.claude ]; then
  # 実体ディレクトリのつもりだが、検出をすり抜けた bind mount の可能性もある。
  # 破壊的な rm -fr は permission denied / データ消失を引き起こす恐れがあるため行わない。
  # 本当に symlink 化したい場合は手動で:
  #   rm -fr ~/.claude && ln -sf ${DOTDIR}/claude ~/.claude
  echo "setup.sh: ~/.claude exists as a directory; skip (manual setup required if intended as symlink)"
else
  ln -sf ${DOTDIR}/claude ~/.claude
fi

# agent-memory (個人永続記憶, private repo) を ~/.claude/memory と ~/.codex/memory の
# 両方から参照させる。link は .gitignore (claude/* / codex/* デフォルト無視) により追跡されない。
# 既存マシンの旧配置 (claude-memory) からの移行は spec の手順で手動実施する:
#   docs/superpowers/specs/2026-07-11-agent-memory-design.md
AGENT_MEMORY_DIR="${AGENT_MEMORY_DIR:-$HOME/dev/src/github.com/shishi/agent-memory}"
if [ ! -d "${AGENT_MEMORY_DIR}" ]; then
  # private repo なので認証必須。ssh 鍵 → gh の順に試し、両方だめなら
  # メッセージだけ出して続行する (setup.sh 全体を止めない)。
  mkdir -p "$(dirname "${AGENT_MEMORY_DIR}")"
  git clone git@github.com:shishi/agent-memory.git "${AGENT_MEMORY_DIR}" 2>/dev/null \
    || gh repo clone shishi/agent-memory "${AGENT_MEMORY_DIR}" 2>/dev/null \
    || echo "setup.sh: could not clone agent-memory (ssh key / gh auth missing?); clone manually: git clone git@github.com:shishi/agent-memory.git ${AGENT_MEMORY_DIR}"
fi
link_memory() { # $1=link path
  # ln -sfn は先が実ディレクトリだと「中へのリンク作成」になる罠があるため、
  # 実体ディレクトリが居る場合は上書きせず報告して手動確認に回す。
  if [ -e "$1" ] && [ ! -L "$1" ]; then
    echo "setup.sh: $1 exists as a real directory; skip (inspect contents and migrate manually)"
  else
    ln -sfn "${AGENT_MEMORY_DIR}" "$1"
  fi
}
if [ -d "${AGENT_MEMORY_DIR}" ]; then
  link_memory "${DOTDIR}/claude/memory"
  link_memory "${DOTDIR}/codex/memory"
else
  echo "setup.sh: ${AGENT_MEMORY_DIR} not available; skip memory links"
fi

if [ -L ~/.codex ]; then
  rm ~/.codex
  ln -sf ${DOTDIR}/codex ~/.codex
elif mountpoint -q ~/.codex 2>/dev/null \
  || grep -qE "[[:space:]]$HOME/\.codex[[:space:]]" /proc/mounts 2>/dev/null; then
  # ~/.codex が bind mount (devcontainer等) の場合は破壊しない。
  # bind mount 越しに ${DOTDIR}/codex/ の中身は既に同じ実体を指している想定。
  echo "setup.sh: ~/.codex is a mount point; skip codex symlink (functional equivalent already in place)"
elif [ -d ~/.codex ]; then
  # auth.json / sessions / logs などを含む実体ディレクトリの可能性が高いので、
  # Claude と同じく破壊的な rm -fr は行わない。
  # 本当に symlink 化したい場合は手動で:
  #   rm -fr ~/.codex && ln -sf ${DOTDIR}/codex ~/.codex
  echo "setup.sh: ~/.codex exists as a directory; skip (manual setup required if intended as symlink)"
else
  ln -sf ${DOTDIR}/codex ~/.codex
fi

if [ -L ${XDG_CONFIG_HOME}/nushell ]; then
  rm ${XDG_CONFIG_HOME}/nushell
  ln -sf ${DOTDIR}/nushell/config.nu ${XDG_CONFIG_HOME}/nushell
  ln -sf ${DOTDIR}/nushell/env.nu ${XDG_CONFIG_HOME}/nushell
elif [ -d ${XDG_CONFIG_HOME}/nushell ]; then
  ln -sf ${DOTDIR}/nushell/config.nu ${XDG_CONFIG_HOME}/nushell
  ln -sf ${DOTDIR}/nushell/env.nu ${XDG_CONFIG_HOME}/nushell
else
  mkdir -p ${XDG_CONFIG_HOME}/nushell
  ln -sf ${DOTDIR}/nushell/config.nu ${XDG_CONFIG_HOME}/nushell
  ln -sf ${DOTDIR}/nushell/env.nu ${XDG_CONFIG_HOME}/nushell
fi

if [ $(uname) = Darwin ]; then
  ln -sf ${DOTDIR}/.gitconfig.mac ~/.gitconfig
  ln -sf ${DOTDIR}/Brewfile ~/Brewfile
elif [ $(uname) = Linux ]; then
  ln -sf ${DOTDIR}/.gitconfig.linux ~/.gitconfig
  #    ln -sf ${DOTDIR}/terminator ${XDG_CONFIG_HOME}/terminator
  #    ln -sf ${DOTDIR}/.xprofile ~/.xprofile
  #    ln -sf ${DOTDIR}/.xbindkeysrc ~/.xbindkeysrc
  #    ln -sf ${DOTDIR}/.imwheelrc ~/.imwheelrc
  #    ln -sf ${DOTDIR}/imwheel.desktop ${XDG_CONFIG_HOME}/autostart/imwheel.desktop
  #    ln -sf ${DOTDIR}/fonts.conf ${XDG_CONFIG_HOME}/fontconfig/fonts.conf
  #    fc-cache -fv
elif [[ $(uname -s) == MINGW* ]]; then
  # uname はビルド番号付き (例: MINGW64_NT-10.0-26200) なのでパターンで判定する
  ln -sf ${DOTDIR}/.gitconfig.win ~/.gitconfig
fi

ln -sf ${DOTDIR}/.gitignore.global ~/.gitignore

ln -sf ${DOTDIR}/.ideavimrc ~/.ideavimrc
ln -sf ${DOTDIR}/.vimrc ~/.vimrc
ln -sf ${DOTDIR}/.gvimrc ~/.gvimrc
#ln -sf ${DOTDIR}/.vim ~/.vim

ln -sf ${DOTDIR}/.gemrc ~/.gemrc
ln -sf ${DOTDIR}/.rspec ~/.rspec
ln -sf ${DOTDIR}/.pryrc ~/.pryrc

ln -sf ${DOTDIR}/.npmrc ~/.npmrc

# ln -sf ${DOTDIR}/.bashrc ~/.bashrc

# ln -s ${DOTDIR}/.zsh ~/.zsh
# ln -s ${DOTDIR}/.zshenv ~/.zshenv
# ln -s ${DOTDIR}/.zshrc ~/.zshrc

# settings.json の enabledPlugins に従って Claude Code plugin を install する。
# claude 未導入の環境では install-plugins.sh 側で黙ってスキップする。
if command -v claude >/dev/null 2>&1; then
  bash "${DOTDIR}/claude/install-plugins.sh" \
    || echo "setup.sh: plugin install step reported issues (continuing)"
fi

echo "please reload shell"
