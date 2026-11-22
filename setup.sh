#!/bin/bash

link_config_dir() {
  local source_path="$1" target_path="$2"

  if [ ! -L "$target_path" ] && [ -d "$target_path" ]; then
    rm -rf "$target_path"
  fi
  ln -sfn "$source_path" "$target_path"
}

# Agent homes contain credentials and history. Preserve an existing target in
# .back before linking the tracked home.
link_agent_home() {
  local source_path="$1" target_path="$2" source_real target_real backup n

  source_real="$(cd "$source_path" 2>/dev/null && pwd -P)" || {
    echo "setup.sh: missing $source_path; skip"
    return
  }
  if [ -L "$target_path" ]; then
    target_real="$(cd "$target_path" 2>/dev/null && pwd -P)"
    [ "$target_real" = "$source_real" ] && return
  fi
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    backup="${target_path}.back"
    n=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      backup="${target_path}.back.${n}"
      n=$((n + 1))
    done
    mv "$target_path" "$backup" || {
      echo "setup.sh: could not move $target_path; skip"
      return
    }
    echo "setup.sh: moved $target_path to $backup"
  fi
  ln -sfn "$source_path" "$target_path" ||
    echo "setup.sh: could not link $target_path"
}

configure_codex_config_filter() {
  if ! git -C "$DOTDIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "setup.sh: $DOTDIR is not a Git checkout; skip Codex config filter"
    return
  fi

  git -C "$DOTDIR" config --local filter.codex-config.clean \
    "bash agent-shared/bin/clean-codex-config.sh" &&
    # smudge のスクリプトが無い古い commit を checkout しても止まらないよう、無ければそのまま出す。
    git -C "$DOTDIR" config --local filter.codex-config.smudge \
      "[ -f agent-shared/bin/smudge-codex-config.sh ] && exec bash agent-shared/bin/smudge-codex-config.sh || exec cat" &&
    git -C "$DOTDIR" config --local filter.codex-config.required true ||
    echo "setup.sh: could not configure Codex config filter"
}

# Environment
case "$(uname -s)" in
MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

if [ -d /.jbdevcontainer ]; then
  XDG_CONFIG_HOME=/.jbdevcontainer/config
elif [ -z "${XDG_CONFIG_HOME:-}" ]; then
  XDG_CONFIG_HOME="$HOME/.config"
fi
mkdir -p "$XDG_CONFIG_HOME"

DOTDIR="$(cd "$(dirname "$0")" && pwd -P)"
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o StrictHostKeyChecking=accept-new}"

# Shells
link_config_dir "$DOTDIR/fish" "$XDG_CONFIG_HOME/fish"

if [ -L "$XDG_CONFIG_HOME/nushell" ]; then
  rm "$XDG_CONFIG_HOME/nushell"
fi
mkdir -p "$XDG_CONFIG_HOME/nushell"
ln -sfn "$DOTDIR/nushell/config.nu" "$XDG_CONFIG_HOME/nushell/config.nu"
ln -sfn "$DOTDIR/nushell/env.nu" "$XDG_CONFIG_HOME/nushell/env.nu"

# Editors
for dir in nvim helix; do
  link_config_dir "$DOTDIR/$dir" "$XDG_CONFIG_HOME/$dir"
done

for file in .ideavimrc .vimrc .gvimrc; do
  ln -sfn "$DOTDIR/$file" "$HOME/$file"
done

if [ "${REMOTE_CONTAINERS:-}" != true ]; then
  emacs_dir="$(dirname "$DOTDIR")/emacs"
  if ! git -C "$emacs_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$(dirname "$DOTDIR")" clone git@github.com:shishi/emacs.git ||
      echo "setup.sh: could not clone emacs; rerun setup.sh"
  fi
  if git -C "$emacs_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    link_config_dir "$emacs_dir" "$HOME/.emacs.d"
  fi
fi

# Terminals
if [ "${REMOTE_CONTAINERS:-}" != true ]; then
  link_config_dir "$DOTDIR/wezterm" "$XDG_CONFIG_HOME/wezterm"
  case "$(uname -s)" in
  Darwin | Linux) link_config_dir "$DOTDIR/ghostty" "$XDG_CONFIG_HOME/ghostty" ;;
  MINGW* | MSYS*)
    noctty_config_dir="$(cygpath -u "$LOCALAPPDATA")/noctty"
    [ ! -L "$noctty_config_dir" ] || rm "$noctty_config_dir"
    mkdir -p "$noctty_config_dir"
    ln -sfn "$DOTDIR/ghostty/config.windows.ghostty" "$noctty_config_dir/config.ghostty"
    ln -sfn "$DOTDIR/ghostty/config.shared.ghostty" "$noctty_config_dir/config.shared.ghostty"
    ;;
  esac
fi

# herdr-core reads %APPDATA% on Windows and $XDG_CONFIG_HOME elsewhere.
case "$(uname -s)" in
MINGW* | MSYS*)
  herdr_config_root="$(cygpath -u "$APPDATA")"
  herdr_config_os=windows
  ;;
*)
  herdr_config_root="$XDG_CONFIG_HOME"
  herdr_config_os=unix
  ;;
esac
mkdir -p "$herdr_config_root/herdr-core"
ln -sfn "$DOTDIR/herdr-core/config.$herdr_config_os.toml" "$herdr_config_root/herdr-core/config.toml"

# On Linux the core runs as a transient user unit named hc-serve-<id>; systemd
# applies a drop-in for that name prefix to each of them.
if [ "$(uname -s)" = Linux ] && command -v systemctl >/dev/null 2>&1; then
  herdr_serve_dropin="$XDG_CONFIG_HOME/systemd/user/hc-serve-.service.d"
  mkdir -p "$herdr_serve_dropin"
  ln -sfn "$DOTDIR/herdr-core/hc-serve.herdr-env.conf" "$herdr_serve_dropin/herdr-env.conf"
  systemctl --user daemon-reload ||
    echo "setup.sh: systemd user manager not reloaded; the Herdr Core drop-in applies after the next login"
fi

# Herdr app keeps its own state in the same folder, so link only the keymap.
# Each OS starts from the app's own defaults (Cmd-based on macOS); the Ctrl+;
# chords for navigating panes, tabs, spaces and agents are the same on every OS.
# Package managers may move the app home with HERDR_APP_HOME (Scoop does).
case "$(uname -s)" in
Darwin) herdr_app_keys="$DOTDIR/herdr-app/keys.macos.json" ;;
Linux) herdr_app_keys="$DOTDIR/herdr-app/keys.linux.json" ;;
*) herdr_app_keys="$DOTDIR/herdr-app/keys.json" ;;
esac
if [ -n "${HERDR_APP_HOME:-}" ]; then
  case "$(uname -s)" in
  MINGW* | MSYS*) herdr_app_home="$(cygpath -u "$HERDR_APP_HOME")" ;;
  *) herdr_app_home="$HERDR_APP_HOME" ;;
  esac
else
  herdr_app_home="$XDG_CONFIG_HOME/herdr-app"
fi
mkdir -p "$herdr_app_home"
ln -sfn "$herdr_app_keys" "$herdr_app_home/keys.json"

# Herdr's terminal takes Ctrl+J before macSKK sees it, so the skk-kana mod
# selects the hiragana mode instead (docs/herdr-app.md). Herdr writes its own
# files into the mod folder, so link the sources one by one.
if [ "$(uname -s)" = Darwin ]; then
  herdr_skk_kana_src="$DOTDIR/herdr-app/mods/skk-kana"
  herdr_skk_kana="$herdr_app_home/mods/skk-kana"
  mkdir -p "$herdr_skk_kana"
  ln -sfn "$herdr_skk_kana_src/main.js" "$herdr_skk_kana/main.js"
  ln -sfn "$herdr_skk_kana_src/mod.json" "$herdr_skk_kana/mod.json"
  if [ ! -x "$herdr_skk_kana/select-input-source" ] ||
    [ "$herdr_skk_kana_src/select-input-source.swift" -nt "$herdr_skk_kana/select-input-source" ]; then
    if command -v swiftc >/dev/null 2>&1; then
      swiftc -O -o "$herdr_skk_kana/select-input-source" "$herdr_skk_kana_src/select-input-source.swift" ||
        echo "setup.sh: skk-kana helper build failed"
    else
      echo "setup.sh: swiftc not found, skk-kana helper not built"
    fi
  fi
fi

mkdir -p "$XDG_CONFIG_HOME/hunk"
ln -sfn "$DOTDIR/hunk/config.toml" "$XDG_CONFIG_HOME/hunk/config.toml"

# Git and package tools
case "$(uname -s)" in
Darwin)
  ln -sfn "$DOTDIR/.gitconfig.mac" "$HOME/.gitconfig"
  ln -sfn "$DOTDIR/Brewfile" "$HOME/Brewfile"
  ;;
Linux) ln -sfn "$DOTDIR/.gitconfig.linux" "$HOME/.gitconfig" ;;
MINGW* | MSYS*) ln -sfn "$DOTDIR/.gitconfig.win" "$HOME/.gitconfig" ;;
esac

ln -sfn "$DOTDIR/.gitignore.global" "$HOME/.gitignore"

for file in .gemrc .rspec .pryrc .npmrc; do
  ln -sfn "$DOTDIR/$file" "$HOME/$file"
done

# Agent homes and shared memory
# A devcontainer may provide ~/.claude as a mount rather than a link.
if [ ! -L "$HOME/.claude" ] &&
  { mountpoint -q "$HOME/.claude" 2>/dev/null ||
    grep -qE "[[:space:]]$HOME/\.claude[[:space:]]" /proc/mounts 2>/dev/null; }; then
  echo "setup.sh: ~/.claude is a mount point; skip"
else
  link_agent_home "$DOTDIR/claude" "$HOME/.claude"
fi

memory_dir="$(bash "$DOTDIR/agent-shared/bin/resolve-memory-dir.sh")" || memory_dir=
if [ -n "$memory_dir" ]; then
  if [ ! -d "$memory_dir" ]; then
    mkdir -p "$(dirname "$memory_dir")"
    git clone git@github.com:shishi/agent-memory.git "$memory_dir" 2>/dev/null ||
      gh repo clone shishi/agent-memory "$memory_dir" 2>/dev/null ||
      echo "setup.sh: could not clone agent-memory"
  fi
  if git -C "$memory_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    for target in "$DOTDIR/claude/memory" "$DOTDIR/codex/memory"; do
      if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "setup.sh: $target is a real path; skip"
      else
        ln -sfn "$memory_dir" "$target"
      fi
    done
  else
    echo "setup.sh: agent-memory is unavailable; skip memory links"
  fi
fi

configure_codex_config_filter
if git -C "$DOTDIR" rev-parse --git-dir >/dev/null 2>&1; then
  (cd "$DOTDIR" && bash agent-shared/bin/install-dotfiles-hooks.sh) || {
    echo "setup.sh: dotfiles commit hook installation failed" >&2
    exit 1
  }
fi
link_agent_home "$DOTDIR/codex" "$HOME/.codex"
mkdir -p "$HOME/.agent-shared"
link_agent_home "$DOTDIR/codex/skills" "$HOME/.agent-shared/skills"
link_agent_home "$DOTDIR/agent-shared/bin" "$HOME/.agent-shared/bin"
link_agent_home "$DOTDIR/agent-shared/hooks" "$HOME/.agent-shared/hooks"

# 旧名 ~/.agents(実ディレクトリ + 個別 link)は互換 symlink に置き換える。
# pull 済みで setup 未実行のセッションが旧 path の hook 参照で壊れないようにする
if [ -d "$HOME/.agents" ] && [ ! -L "$HOME/.agents" ]; then
  rm -f "$HOME/.agents/bin" "$HOME/.agents/hooks" "$HOME/.agents/skills"
  rmdir "$HOME/.agents" 2>/dev/null || echo "setup.sh: ~/.agents is not empty; skip compat link"
fi
[ -e "$HOME/.agents" ] || ln -sfn "$HOME/.agent-shared" "$HOME/.agents"

bash "$DOTDIR/agent-shared/bin/managed-skills.sh" sync ||
  echo "setup.sh: managed skill sync failed"
bash "$DOTDIR/agent-shared/bin/herdr-skills.sh" sync ||
  echo "setup.sh: Herdr skill generation failed"

# Plugins and integrations (after agent homes and shared skills)
if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  bash "$DOTDIR/claude/install-plugins.sh" ||
    echo "setup.sh: Claude plugin install failed"
fi

echo "please reload shell"
