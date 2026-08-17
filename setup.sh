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

if [ "$REMOTE_CONTAINERS" != true ]; then
  link_config_dir "${DOTDIR}/wezterm" "${XDG_CONFIG_HOME}/wezterm"

  # symlink でないときだけ clone する。既にリンク済みなら repo は取得済み。
  if [ ! -L ~/.emacs.d ]; then
    git -C $(dirname ${DOTDIR}) clone git@github.com:shishi/emacs.git
  fi
  link_config_dir "$(dirname ${DOTDIR})/emacs" ~/.emacs.d
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

# realpath/readlink -f は実装によって dangling link にも非空を返すため、存在確認を
# 先に行う。directory と regular file のどちらを指す valid link も物理解決できる。
resolve_existing_path() {
  local path="$1"

  [ -e "$path" ] || return 1
  realpath "$path" 2>/dev/null
}

# agent-memory (個人永続記憶, private repo) を Claude/Codex 双方から参照させる。
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
    memory_real="$(resolve_existing_path "${AGENT_MEMORY_DIR}")"
    memory_blocked=false
    memory_targets=("${DOTDIR}/claude/memory" "${DOTDIR}/codex/memory")
    memory_states=(missing missing)
    memory_literals=("" "")
    memory_temps=("" "")
    memory_backups=("" "")
    memory_prepared=(false false)
    memory_changed=(false false)
    memory_detached=(false false)

    # 片方を変更してからもう片方の衝突に気付くと split brain になるため、2 target
    # とも先に調べる。dangling は実体を持たないので、報告したうえで修復可能とする。
    for i in 0 1; do
      memory_target="${memory_targets[$i]}"
      if [ -L "$memory_target" ]; then
        if [ ! -e "$memory_target" ]; then
          memory_states[$i]=dangling
          memory_literals[$i]="$(readlink "$memory_target")"
          echo "setup.sh: ${memory_target} was a dangling link to $(readlink "$memory_target")"
        else
          target_real="$(resolve_existing_path "$memory_target")"
          if [ -z "$target_real" ]; then
            echo "setup.sh: could not resolve ${memory_target}; memory targets unchanged"
            memory_blocked=true
          elif [ "$target_real" != "$memory_real" ]; then
            echo "setup.sh: ${memory_target} resolves elsewhere (${target_real}); memory targets unchanged"
            memory_blocked=true
          else
            memory_states[$i]=canonical
          fi
        fi
      elif [ -e "$memory_target" ]; then
        echo "setup.sh: ${memory_target} exists as a real path; memory targets unchanged"
        memory_blocked=true
      fi
    done

    if [ "$memory_blocked" = true ]; then
      echo "setup.sh: skip both memory links (manual setup required)"
    else
      # 両方の symlink を本番 target と別名で先に作る。1 本でも作成・検証に失敗
      # したら、本番 target には触れず、自分が作成した temp だけを片付ける。
      memory_prepare_ok=true
      memory_failure=""
      for i in 0 1; do
        [ "${memory_states[$i]}" = canonical ] && continue
        memory_target="${memory_targets[$i]}"
        memory_temps[$i]="${memory_target}.setup-$$.new"
        memory_backups[$i]="${memory_target}.setup-$$.back"
        memory_temp="${memory_temps[$i]}"
        memory_backup="${memory_backups[$i]}"

        if [ -e "$memory_temp" ] || [ -L "$memory_temp" ] \
          || [ -e "$memory_backup" ] || [ -L "$memory_backup" ]; then
          memory_prepare_ok=false
          memory_failure="temporary path already exists for ${memory_target}"
          break
        fi
        if ! ln -s "${AGENT_MEMORY_DIR}" "$memory_temp"; then
          memory_prepare_ok=false
          memory_failure="could not prepare ${memory_target}"
          break
        fi
        memory_prepared[$i]=true
        target_real="$(resolve_existing_path "$memory_temp")"
        if [ ! -L "$memory_temp" ] || [ "$target_real" != "$memory_real" ]; then
          memory_prepare_ok=false
          memory_failure="prepared path is not a canonical symlink for ${memory_target}"
          break
        fi
      done

      # preparation 中に別プロセスが target を変更していないことも、switch 前に
      # 2 本まとめて再確認する。
      if [ "$memory_prepare_ok" = true ]; then
        for i in 0 1; do
          memory_target="${memory_targets[$i]}"
          case "${memory_states[$i]}" in
            canonical)
              target_real="$(resolve_existing_path "$memory_target")"
              if [ ! -L "$memory_target" ] || [ "$target_real" != "$memory_real" ]; then
                memory_prepare_ok=false
              fi
              ;;
            dangling)
              if [ ! -L "$memory_target" ] || [ -e "$memory_target" ] \
                || [ "$(readlink "$memory_target")" != "${memory_literals[$i]}" ]; then
                memory_prepare_ok=false
              fi
              ;;
            missing)
              if [ -e "$memory_target" ] || [ -L "$memory_target" ]; then
                memory_prepare_ok=false
              fi
              ;;
          esac
          if [ "$memory_prepare_ok" != true ]; then
            memory_failure="memory target changed during preparation: ${memory_target}"
            break
          fi
        done
      fi

      if [ "$memory_prepare_ok" != true ]; then
        for i in 0 1; do
          memory_temp="${memory_temps[$i]}"
          if [ "${memory_prepared[$i]}" = true ] \
            && { [ -e "$memory_temp" ] || [ -L "$memory_temp" ]; }; then
            rm -fr "$memory_temp" \
              || echo "setup.sh: could not clean temporary memory link ${memory_temp}"
          fi
        done
        echo "setup.sh: could not prepare both memory links; targets unchanged (${memory_failure})"
      else
        # 全 temp の検証後だけ本番 target を切り替える。dangling link は literal を
        # 保ったまま backup へ移し、途中失敗時に同じ link 自体を戻せるようにする。
        memory_switch_ok=true
        for i in 0 1; do
          [ "${memory_states[$i]}" = canonical ] && continue
          memory_target="${memory_targets[$i]}"
          memory_temp="${memory_temps[$i]}"
          memory_backup="${memory_backups[$i]}"

          if [ "${memory_states[$i]}" = dangling ]; then
            if mv "$memory_target" "$memory_backup"; then
              memory_detached[$i]=true
            else
              memory_switch_ok=false
              memory_failure="could not preserve dangling link ${memory_target}"
              break
            fi
          fi
          if mv "$memory_temp" "$memory_target"; then
            memory_prepared[$i]=false
            memory_changed[$i]=true
          else
            memory_switch_ok=false
            memory_failure="could not switch ${memory_target}"
            break
          fi
        done

        # switch 後も両方が本物の symlink かつ同じ物理解決先でなければ失敗扱い。
        if [ "$memory_switch_ok" = true ]; then
          for i in 0 1; do
            memory_target="${memory_targets[$i]}"
            target_real="$(resolve_existing_path "$memory_target")"
            if [ ! -L "$memory_target" ] || [ "$target_real" != "$memory_real" ]; then
              memory_switch_ok=false
              memory_failure="memory link postcondition failed for ${memory_target}"
              break
            fi
          done
        fi

        # 成功時だけ旧 dangling backup を捨てる。失敗した removal も rollback の
        # 対象にし、既に消した backup は保存した literal から best-effort で戻す。
        if [ "$memory_switch_ok" = true ]; then
          for i in 0 1; do
            memory_backup="${memory_backups[$i]}"
            [ -n "$memory_backup" ] || continue
            if [ -L "$memory_backup" ]; then
              if ! rm -f "$memory_backup"; then
                memory_switch_ok=false
                memory_failure="could not clean memory backup ${memory_backup}"
                break
              fi
            elif [ -e "$memory_backup" ]; then
              memory_switch_ok=false
              memory_failure="memory backup changed unexpectedly: ${memory_backup}"
              break
            fi
          done
        fi

        if [ "$memory_switch_ok" != true ]; then
          memory_rollback_ok=true
          for i in 1 0; do
            memory_target="${memory_targets[$i]}"
            memory_backup="${memory_backups[$i]}"

            if [ "${memory_changed[$i]}" = true ]; then
              if [ -L "$memory_target" ]; then
                rm -f "$memory_target" || memory_rollback_ok=false
              elif [ -e "$memory_target" ]; then
                # 予期しない実パスは削除しない。
                memory_rollback_ok=false
              fi
            fi
            if [ "${memory_states[$i]}" = dangling ] \
              && [ "${memory_detached[$i]}" = true ] \
              && [ ! -e "$memory_target" ] && [ ! -L "$memory_target" ]; then
              if [ -L "$memory_backup" ]; then
                mv "$memory_backup" "$memory_target" || memory_rollback_ok=false
              else
                ln -s "${memory_literals[$i]}" "$memory_target" \
                  || memory_rollback_ok=false
              fi
            fi
          done

          for i in 0 1; do
            memory_temp="${memory_temps[$i]}"
            if [ "${memory_prepared[$i]}" = true ] \
              && { [ -e "$memory_temp" ] || [ -L "$memory_temp" ]; }; then
              rm -fr "$memory_temp" || memory_rollback_ok=false
            fi
          done
          for i in 0 1; do
            memory_backup="${memory_backups[$i]}"
            if [ -n "$memory_backup" ] \
              && { [ -e "$memory_backup" ] || [ -L "$memory_backup" ]; }; then
              echo "setup.sh: rollback left memory backup at ${memory_backup}"
              memory_rollback_ok=false
            fi
          done
          if [ "$memory_rollback_ok" = true ]; then
            echo "setup.sh: memory link switch failed; rolled back both targets (${memory_failure})"
          else
            echo "setup.sh: memory link switch failed; rollback incomplete (${memory_failure})"
          fi
        fi
      fi
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
