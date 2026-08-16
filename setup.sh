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

# 判定は「解決できた実パス」で行う。文字列比較だけだと cd の失敗 (空文字) を
# 「別の場所を指している」と取り違える。
link_agent_home() {
  local source_path="$1" target_path="$2" foreign_remedy="$3"
  # 実パスの remedy は target ごとに違う。既定値は置かない: 3 target はどれも
  # 戻すべき runtime を持ち、汎用の「退避して張り直せ」はそれを取り残すうえ、
  # 検出をすり抜けた bind mount には mount 元へ作用する誤手順にもなる。
  local real_remedy="$4"
  local source_real target_real

  # 空の source_real で比較を続けると、target も解決できないときに「空 = 空」で
  # 一致してしまい、両方壊れているのに黙って何もしない。ここで打ち切る。
  source_real="$(cd "$source_path" 2>/dev/null && pwd -P)"
  if [ -z "$source_real" ]; then
    echo "setup.sh: missing link source ${source_path}; skip"
    return 0
  fi
  if [ ! -L "$target_path" ] && [ -e "$target_path" ]; then
    echo "setup.sh: ${target_path} exists as a real path; skip (${real_remedy})"
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

# ~/.claude も ~/.codex と同じ構造なので同じ関数に通す。ignore が既定拒否する
# runtime をホームごと抱えており、別 checkout を指すリンクを張り替えると実体は
# 残ったまま Claude Code から参照できなくなる。
#
# remedy が挙げる名前は目印で、網羅ではない。列挙手段そのものを渡すことで「残りは
# 自分で数えろ」を実行可能にしている。-o 単体は ignored でない untracked (まだ
# commit していない新規ファイル) も出すため、ignored に限る -i --exclude-standard
# が要る。実パス側は退避先を列挙できない (git repo ではない) ので、逆に repo が持つ
# 名前 (ls-files) を除外集合として渡す。粒度は top-level 名なので、その配下にある
# repo に無いファイルは移送側に含める。memory リンクは列挙から除く:
# この実行の後段が ${DOTDIR}/claude/memory を必ず張り直すので、移す必要がない。
#
# 移送先は実行中の checkout なので、worktree から叩いたときは移してはいけない。
# worktree を消せば runtime ごと消える。remedy はそれを最初に言う。
#
# bind mount (devcontainer 等) だけは先に見る。link_agent_home は実パスを「退避して
# 張り直せ」と報告するが、bind mount 越しには既に同じ実体が見えており、退避は不要な
# うえマウント元を壊しかねない。symlink でないときだけ判定するのは、bind mount が
# 実パスとして現れるため。リンク済みのホームをこの枝へ落とさない。
# mountpoint で検出できない bind mount (Docker Desktop の virtiofs/9p 等) も
# /proc/mounts のフォールバックで拾う。ただし取りこぼしは残る (mount 元が
# ${DOTDIR}/claude と同じかは照合していない。$HOME に正規表現メタ文字を含む場合や
# mount point に空白がある場合はフォールバックが外れる) ため、実パス側の remedy に
# も bind mount の確認を求めている。
if [ ! -L ~/.claude ] \
  && { mountpoint -q ~/.claude 2>/dev/null \
    || grep -qE "[[:space:]]$HOME/\.claude[[:space:]]" /proc/mounts 2>/dev/null; }; then
  echo "setup.sh: ~/.claude is a mount point; skip claude symlink (mount source not compared -- readlink cannot see through a mount -- check the source with findmnt -no SOURCE ~/.claude where util-linux is present, or in the container definition, and confirm the path it names is the host path this checkout is mounted from; an in-container path such as ${DOTDIR}/claude cannot be compared with it directly)"
else
  link_agent_home "${DOTDIR}/claude" "$HOME/.claude" \
    "if ${DOTDIR} is a temporary worktree -- git -C ${DOTDIR} rev-parse --git-dir differs from --git-common-dir -- do nothing; state moved into a worktree goes when the worktree does. Otherwise stop Claude Code and list what Git ignores under the path above with git -C <that path> ls-files -o -i --exclude-standard --directory (.credentials.json projects/ sessions/ history.jsonl plugins/ and more). If that path is not inside a checkout, git cannot list it; treat everything there as runtime except the top-level names the repository has. The repository's top-level names are what git -C ${DOTDIR}/claude ls-files | cut -d/ -f1 | sort -u prints. Move each entry except memory if ${DOTDIR}/claude/memory is a symlink once this run finishes -- if it is not, this run could not recreate it and memory has to move too -- to the same relative path under ${DOTDIR}/claude without overwriting what is already there (the paths are printed relative to the listed directory; moving onto an existing directory nests inside it), then remove the link and re-run" \
    "if ${DOTDIR} is a temporary worktree -- git -C ${DOTDIR} rev-parse --git-dir differs from --git-common-dir -- run the adoption below from the permanent checkout instead. First confirm it is not a bind mount that the checks above missed -- moving one aside acts on the mount source. Then stop Claude Code, move it aside under a name that does not exist yet, re-run this script, and move back from there everything except memory if ${DOTDIR}/claude/memory is a symlink once the re-run finishes -- if it is not, move memory too; and if the backup's memory is a real directory it holds a clone, so check it for unpushed commits before discarding it -- and except the top-level names git -C ${DOTDIR}/claude ls-files | cut -d/ -f1 | sort -u prints, which the repository owns at those paths -- anything under them that the repository does not have is yours to move too (the rest is runtime: .credentials.json projects/ sessions/ history.jsonl plugins/ and more) without overwriting what is already there (moving onto an existing directory nests inside it, and the re-run itself creates some of these directories); skipping that last step leaves a working but signed-out home"
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
# 移動しない — 旧 claude-memory からの移行は
# docs/superpowers/specs/2026-07-11-agent-memory-design.md の「移行手順」に従い手動)。
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
      # 失敗を握ると記憶が無い状態が無言で残る。注入 hook は読み先が無ければ
      # 何も言わないので、ここが唯一の手掛かりになる。
      ln -sfn "${AGENT_MEMORY_DIR}" "${DOTDIR}/claude/memory" \
        || echo "setup.sh: could not link ${DOTDIR}/claude/memory (Windows: enable Developer Mode or run elevated)"
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
# 実ディレクトリだった場合は auth.json / sessions が入っているため壊さない。手順は
# この下の remedy 文字列が唯一の正本で、実行時に印字される。ここに二重に書くと
# 片方だけが更新されて食い違う (退避先の名前を衝突させないこと、移すのは ignore が
# 拒否している分だけであること、AGENTS.md・config.toml・agents/・rules/・skills/
# (.system/ 以外)・hooks/・hooks.json は repo 側が正本であることは、すべて remedy
# 側が持っている)。

# remedy は target ごとに違う。skills 側に runtime の移設を書くと、資格情報を
# tracked な codex/skills/ へ入れる手順になってしまう。
#
# どちらも締めが「外して再実行」で、再実行はこの checkout を指す。この分岐が出る
# 主因は worktree からの実行なので、移送も再実行も先に条件を付ける。worktree へ
# 移した runtime は worktree を消せば消え、worktree を指したリンクは残らない。
link_agent_home "${DOTDIR}/codex" "$HOME/.codex" \
  "if ${DOTDIR} is a temporary worktree -- git -C ${DOTDIR} rev-parse --git-dir differs from --git-common-dir -- do nothing; state moved into a worktree goes when the worktree does. Otherwise stop Codex, list what Git ignores under the path above with git -C <that path> ls-files -o -i --exclude-standard --directory (auth.json sessions/ plugins/ sqlite/ browser/ and more). If that path is not inside a checkout, git cannot list it; treat everything there as runtime except the top-level names the repository has. The repository's top-level names are what git -C ${DOTDIR}/codex ls-files | cut -d/ -f1 | sort -u prints. Move each entry to the same relative path under ${DOTDIR}/codex without overwriting what is already there (the paths are printed relative to the listed directory, so skills/.system/ stays under skills/; moving onto an existing directory nests inside it), then remove the link and re-run" \
  "if ${DOTDIR} is a temporary worktree -- git -C ${DOTDIR} rev-parse --git-dir differs from --git-common-dir -- run the adoption below from the permanent checkout instead. Then stop Codex, move it aside under a name that does not exist yet, re-run this script, and move back from there everything except the top-level names git -C ${DOTDIR}/codex ls-files | cut -d/ -f1 | sort -u prints, which the repository owns at those paths -- anything under them that the repository does not have is yours to move too (the rest is runtime: auth.json sessions/ plugins/ sqlite/ browser/ and more) without overwriting what is already there (moving onto an existing directory nests inside it, and the re-run itself creates some of these directories); skipping that last step leaves a working but signed-out home"
if mkdir -p ~/.agents; then
  link_agent_home "${DOTDIR}/codex/skills" "$HOME/.agents/skills" \
    "if ${DOTDIR} is a temporary worktree -- git -C ${DOTDIR} rev-parse --git-dir differs from --git-common-dir -- do nothing; otherwise move the .system/ directory under the path above -- the only runtime here -- into ${DOTDIR}/codex/skills/, then remove the link and re-run" \
    "if ${DOTDIR} is a temporary worktree -- git -C ${DOTDIR} rev-parse --git-dir differs from --git-common-dir -- run the adoption below from the permanent checkout instead. Then move it aside under a name that does not exist yet, re-run this script, and move .system/ back from there into ~/.agents/skills -- it is the only runtime here, and the rest is tracked without overwriting what is already there (moving onto an existing directory nests inside it, and the re-run itself creates some of these directories)"
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
