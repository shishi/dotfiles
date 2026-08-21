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

# リンクはすべて ln -sfn で張る。-n (--no-dereference) が無いと、既にディレクトリを
# 指す symlink が張り替えではなく「その中へ」張られる (ln -sf が L を辿って
# L/basename(T) を作る)。ファイルへのリンクでは -n は無害なので例外を作らない。
#
# エディタ設定は repo が正本で runtime を持たないため、実ディレクトリは中身ごと
# 捨てて置き換える。auth.json や session を抱える agent home (link_agent_home) とは
# 方針が違うのはここ。
link_config_dir() {
  local source_path="$1" target_path="$2"

  if [ ! -L "$target_path" ] && [ -d "$target_path" ]; then
    rm -fr "$target_path"
  fi
  ln -sfn "$source_path" "$target_path"
}

# 新規マシンの known_hosts は空なので、素の git clone は host key 確認の対話で
# 止まる。そこで止まらないよう新しいホスト鍵を受理する。環境側で設定済みなら
# そちらを尊重する。尊重するのは環境変数の値で、git config の core.sshCommand は
# 環境変数の方が優先されるため上書きする。export なので後続の gh と
# install-plugins.sh の git にも効く。
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o StrictHostKeyChecking=accept-new}"

if [ "$REMOTE_CONTAINERS" != true ]; then
  link_config_dir "${DOTDIR}/wezterm" "${XDG_CONFIG_HOME}/wezterm"

  emacs_dir="$(dirname "${DOTDIR}")/emacs"
  # 取得済みかどうかは HEAD が解決できるかで見る。~/.emacs.d が symlink かどうかで
  # 見ると、旧版が clone 失敗時に残した dangling link を「取得済み」と誤認する。
  # .git の有無で見ると、SIGKILL や電源断で .git だけ残った状態を誤認する
  # (通常の認証失敗やネットワーク断では git 自身が後始末するので残らない)。
  # HEAD の解決なら linked worktree (.git がファイル) も正しく拾える。
  emacs_ready() { git -C "${emacs_dir}" rev-parse --verify HEAD >/dev/null 2>&1; }
  if ! emacs_ready; then
    git -C "$(dirname "${DOTDIR}")" clone git@github.com:shishi/emacs.git \
      || echo "setup.sh: could not clone emacs into ${emacs_dir} (ssh key missing? interrupted?); rerun setup.sh, or remove a leftover first: rm -rf ${emacs_dir}"
  fi
  # 取得できたときだけ張る。失敗したまま張ると壊れたリンクが残り、既存の実
  # ディレクトリは link_config_dir の rm -fr で消える。
  if emacs_ready; then
    link_config_dir "${emacs_dir}" ~/.emacs.d
  fi
fi

link_config_dir "${DOTDIR}/fish" "${XDG_CONFIG_HOME}/fish"
link_config_dir "${DOTDIR}/nvim" "${XDG_CONFIG_HOME}/nvim"
link_config_dir "${DOTDIR}/helix" "${XDG_CONFIG_HOME}/helix"

# agent のホーム (~/.claude ~/.codex ~/.agents/skills) を張る。実行後は必ずこの
# checkout を指している状態にする。既に何かが在れば .back へ退避してから張る。
# 消さないのは、ignore された runtime (auth.json / sessions/ / history.jsonl /
# plugins/) がそこに同居しているため。退避先から必要な分を戻すのは手作業。
#
# 比較は解決した実パスで行う。文字列比較だと cd の失敗 (空文字) を「別の場所を
# 指している」と取り違える。
link_agent_home() {
  local source_path="$1" target_path="$2"
  local source_real target_real backup n

  source_real="$(cd "$source_path" 2>/dev/null && pwd -P)"
  if [ -z "$source_real" ]; then
    echo "setup.sh: missing ${source_path}; skip"
    return 0
  fi
  if [ -L "$target_path" ]; then
    target_real="$(cd "$target_path" 2>/dev/null && pwd -P)"
    # 既に正しい。張り替えないので、symlink を作れない環境で再実行しても失わない。
    [ "$target_real" = "$source_real" ] && return 0
    # dangling は退避するものが無い。リンク先を失うので捨てた値だけ残す。
    if [ ! -e "$target_path" ]; then
      echo "setup.sh: ${target_path} was a dangling link to $(readlink "$target_path")"
      rm -f "$target_path"
    fi
  fi
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    # 退避先は衝突させない。mv は既存ディレクトリへ向けると中へ入れ子になる。
    backup="${target_path}.back"
    n=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      backup="${target_path}.back.${n}"
      n=$((n + 1))
    done
    if mv "$target_path" "$backup"; then
      # symlink なら mv はリンク自身を動かすので、指し先の実体には触らない。
      echo "setup.sh: moved ${target_path} to ${backup} (move its runtime back from there)"
    else
      echo "setup.sh: could not move ${target_path} aside; skip"
      return 0
    fi
  fi
  ln -sfn "$source_path" "$target_path" \
    || echo "setup.sh: could not link ${target_path} (Windows: enable Developer Mode or run elevated)"
}

# bind mount (devcontainer 等) は実パスとして現れるので、実パス扱いの前に見る。
# 越しに同じ実体が見えているため退避は不要で、退避すると mount 元へ作用する。
# mountpoint で検出できない実装 (Docker Desktop の virtiofs/9p 等) は /proc/mounts で
# 拾う。mount 元が ${DOTDIR}/claude と同じかは照合していない。
if [ ! -L ~/.claude ] \
  && { mountpoint -q ~/.claude 2>/dev/null \
    || grep -qE "[[:space:]]$HOME/\.claude[[:space:]]" /proc/mounts 2>/dev/null; }; then
  echo "setup.sh: ~/.claude is a mount point; skip (check the source with findmnt -no SOURCE ~/.claude)"
else
  link_agent_home "${DOTDIR}/claude" "$HOME/.claude"
fi

# gitconfig は agent-memory 処理より前に張る。ヘルパーが git config の
# ghq.root を参照するため、後だと fresh 環境の初回実行だけ既定 root へ
# clone される二段階挙動になってしまう。
if [ $(uname) = Darwin ]; then
  ln -sfn ${DOTDIR}/.gitconfig.mac ~/.gitconfig
  ln -sfn ${DOTDIR}/Brewfile ~/Brewfile
elif [ $(uname) = Linux ]; then
  ln -sfn ${DOTDIR}/.gitconfig.linux ~/.gitconfig
  #    link_config_dir ${DOTDIR}/terminator ${XDG_CONFIG_HOME}/terminator
  #    ln -sfn ${DOTDIR}/.xprofile ~/.xprofile
  #    ln -sfn ${DOTDIR}/.xbindkeysrc ~/.xbindkeysrc
  #    ln -sfn ${DOTDIR}/.imwheelrc ~/.imwheelrc
  #    ln -sfn ${DOTDIR}/imwheel.desktop ${XDG_CONFIG_HOME}/autostart/imwheel.desktop
  #    ln -sfn ${DOTDIR}/fonts.conf ${XDG_CONFIG_HOME}/fontconfig/fonts.conf
  #    fc-cache -fv
elif [[ $(uname -s) == MINGW* ]]; then
  # uname はビルド番号付き (例: MINGW64_NT-10.0-26200) なのでパターンで判定する
  ln -sfn ${DOTDIR}/.gitconfig.win ~/.gitconfig
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

# Codex CLI は CODEX_HOME (既定 ~/.codex) をディレクトリ単位で読む。~/.agents/skills
# は同じ実体の skills/ を指す (personal skills の参照先)。
link_agent_home "${DOTDIR}/codex" "$HOME/.codex"
if mkdir -p ~/.agents; then
  link_agent_home "${DOTDIR}/codex/skills" "$HOME/.agents/skills"
else
  echo "setup.sh: could not create ~/.agents; skip the skills link"
fi

# nushell はディレクトリ単位で差し替えない。Nushell 自身が同じ場所へ history や
# plugin registry を書くため、ディレクトリは実体のまま残し、中の 2 ファイルだけを張る。
# symlink になっていたら実ディレクトリへ戻す。repo のディレクトリを直接指していると、
# Nushell の生成物が worktree の中へ落ちる。
# 宛先はファイル名まで書く。ディレクトリを宛先にすると、そこが symlink だったときに
# ディレクトリ自身が最後の 1 ファイルへのリンクに化ける。
if [ -L ${XDG_CONFIG_HOME}/nushell ]; then
  rm ${XDG_CONFIG_HOME}/nushell
fi
mkdir -p ${XDG_CONFIG_HOME}/nushell
ln -sfn ${DOTDIR}/nushell/config.nu ${XDG_CONFIG_HOME}/nushell/config.nu
ln -sfn ${DOTDIR}/nushell/env.nu ${XDG_CONFIG_HOME}/nushell/env.nu

# 単一ファイルは HOME 直下に同名で張る。ディレクトリと違い repo が唯一の実体で、
# runtime を持たないので実ファイルが在っても置き換えてよい。
for f in .ideavimrc .vimrc .gvimrc .gemrc .rspec .pryrc .npmrc; do
  ln -sfn "${DOTDIR}/${f}" "$HOME/${f}"
done

# 名前が変わるのはこれだけ。gitconfig の core.excludesFile が ~/.gitignore を見る。
ln -sfn ${DOTDIR}/.gitignore.global ~/.gitignore

# .bashrc / .zsh 系 / .vim は追跡しているが張らない。

# settings.json の enabledPlugins に従って Claude Code plugin を install する。
# claude 未導入の環境では install-plugins.sh 側で黙ってスキップする。
if command -v claude >/dev/null 2>&1; then
  bash "${DOTDIR}/claude/install-plugins.sh" \
    || echo "setup.sh: plugin install step reported issues (continuing)"
fi

# Codex の plugin は Claude Code と違いアカウント側に保存され、サインインすれば
# マシンをまたいで復元される。ここで収束させる必要はない。

echo "please reload shell"
