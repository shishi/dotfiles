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

# gitconfig は agent-memory 処理より前に張る。ヘルパーが git config の
# ghq.root を参照するため、後だと fresh 環境の初回実行だけ既定 root へ
# clone される二段階挙動になってしまう。
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

# agent-memory (個人永続記憶, private repo) を ~/.claude/memory として参照させる。
# 配置先は resolve-memory-dir.sh が解決する (ghq.root 対応。解決のみで実体は
# 移動しない — 旧 claude-memory からの移行は spec 手順で手動)。
# symlink は dotfiles の .gitignore により追跡されない。
AGENT_MEMORY_DIR="$(bash "${DOTDIR}/resolve-memory-dir.sh")"
resolve_status=$?
# setup.sh には set -e がないため、ヘルパーの失敗や壊れた出力 (空・複数行・
# 相対パス) をここで検証しないと後続の clone/symlink が変な場所に走る。
case "$AGENT_MEMORY_DIR" in
  "") resolve_status=1 ;;
  *"
"*) resolve_status=1 ;;
  /*) ;;
  *) resolve_status=1 ;;
esac
if [ "$resolve_status" -ne 0 ]; then
  echo "setup.sh: could not resolve agent-memory location; skip memory setup"
else
  if [ ! -d "${AGENT_MEMORY_DIR}" ]; then
    # ghq root 配下の中間ディレクトリ (github.com/shishi) は fresh 環境に
    # 存在せず、git clone は親を作らない。
    mkdir -p "$(dirname "${AGENT_MEMORY_DIR}")"
    # private repo なので認証必須。ssh 鍵 → gh の順に試し、両方だめなら
    # メッセージだけ出して続行する (setup.sh 全体を止めない)。
    git clone git@github.com:shishi/agent-memory.git "${AGENT_MEMORY_DIR}" 2>/dev/null \
      || gh repo clone shishi/agent-memory "${AGENT_MEMORY_DIR}" 2>/dev/null \
      || echo "setup.sh: could not clone agent-memory (ssh key / gh auth missing?); clone manually: git clone git@github.com:shishi/agent-memory.git ${AGENT_MEMORY_DIR}"
  fi
  if [ -d "${AGENT_MEMORY_DIR}" ]; then
    if [ ! -e "${DOTDIR}/claude/memory" ] || [ -L "${DOTDIR}/claude/memory" ]; then
      ln -sfn "${AGENT_MEMORY_DIR}" "${DOTDIR}/claude/memory"
    else
      echo "setup.sh: ${DOTDIR}/claude/memory exists as a directory; skip (manual setup required)"
    fi
  else
    echo "setup.sh: ${AGENT_MEMORY_DIR} not available; skip memory symlink"
  fi
fi

# Codex CLI は CODEX_HOME (既定 ~/.codex) をディレクトリ単位で読むため、~/.claude と
# 同じくホームごと symlink で差し込む。~/.agents/skills は同じ実体の skills/ を指す
# (personal skills の参照先)。
#
# 実ディレクトリだった場合は auth.json / sessions が入っているため壊さない。symlink
# 化するときは Codex を終了させたうえで自分で退避する。退避先が既にあると mv は
# その中へ入れ子で移動してしまうので、名前を衝突させない (bash / zsh 用。<dotfiles>
# はこの setup.sh があるディレクトリに読み替える):
#   mv ~/.codex ~/.codex.bak.$(date +%s) && bash <dotfiles>/setup.sh
# 退避先から <dotfiles>/codex/ へ移すのは .gitignore が既定拒否する runtime だけに
# する (auth.json、sessions/、plugins/、sqlite/、browser/ など)。AGENTS.md、
# config.toml、agents/、rules/、skills/ (.system/ 以外)、hooks/、hooks.json は
# 再包含された tracked ファイルで repo 側が正本。上書きすると未 commit の変更として
# 現れ、マシン固有の内容が commit に混ざる。
#
# 判定は「解決できた実パス」で行う。文字列比較だけだと cd の失敗 (空文字) を
# 「別の場所を指している」と取り違える。
link_codex_path() {
  local source_path="$1" target_path="$2" foreign_remedy="$3"
  local source_real target_real

  # 空の source_real で比較を続けると、target も解決できないときに「空 = 空」で
  # 一致してしまい、両方壊れているのに黙って何もしない。ここで打ち切る。
  source_real="$(cd "$source_path" 2>/dev/null && pwd -P)"
  if [ -z "$source_real" ]; then
    echo "setup.sh: missing link source ${source_path}; skip"
    return 0
  fi
  if [ ! -L "$target_path" ] && [ -e "$target_path" ]; then
    echo "setup.sh: ${target_path} exists as a real path; skip (move it aside to link ${source_path})"
    return 0
  fi
  if [ -L "$target_path" ]; then
    target_real="$(cd "$target_path" 2>/dev/null && pwd -P)"
    # 既に正しいリンク。張り替えないので、symlink を作れない環境で再実行しても
    # 動いているリンクを失わない。
    if [ "$target_real" = "$source_real" ]; then
      return 0
    fi
    if [ -n "$target_real" ]; then
      # 別 checkout / worktree を指している。張り替えると Codex はサインアウト状態に
      # なり、以後の auth.json や sessions は旧 checkout ではなくこちら側へ書かれる。
      echo "setup.sh: ${target_path} links to ${target_real}; skip (${foreign_remedy})"
      return 0
    fi
    # 解決できないリンク。dangling と区別せずに張り替えると、中身を確かめられな
    # かったリンク先を捨てることになる。
    if [ -e "$target_path" ]; then
      echo "setup.sh: ${target_path} links to a path that could not be resolved (not a directory, or no traversal permission); skip"
      return 0
    fi
    # ここだけが dangling link。リンク先を失うので、捨てた値を残す。
    echo "setup.sh: ${target_path} was a dangling link to $(readlink "$target_path"); relinking to ${source_path}"
  fi
  # ln -sf は既存の dir symlink を辿って中に張ってしまうので -n が必須。
  # 失敗しても setup.sh 全体は続くため、原因が分かる 1 行を残す。
  ln -sfn "$source_path" "$target_path" \
    || echo "setup.sh: could not link ${target_path} (Windows: enable Developer Mode or run elevated)"
}

# remedy は target ごとに違う。skills 側に runtime の移設を書くと、資格情報を
# tracked な codex/skills/ へ入れる手順になってしまう。
link_codex_path "${DOTDIR}/codex" "$HOME/.codex" \
  "stop Codex, merge its runtime -- auth.json sessions/ plugins/ sqlite/ browser/ -- into ${DOTDIR}/codex without overwriting what is already there (moving onto an existing directory nests inside it), then remove the link and re-run"
if mkdir -p ~/.agents; then
  link_codex_path "${DOTDIR}/codex/skills" "$HOME/.agents/skills" \
    "remove the link and re-run; the only runtime here is skills/.system/"
else
  echo "setup.sh: could not create ~/.agents; skip the skills link"
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

# Codex の plugin は Claude Code と違いアカウント側に保存され、サインインすれば
# マシンをまたいで復元される。ここで収束させる必要はない。

echo "please reload shell"
