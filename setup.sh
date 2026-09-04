#!/bin/bash

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
  ln -sfn "$source_path" "$target_path" \
    || echo "setup.sh: could not link $target_path"
}

configure_codex_config_filter() {
  if ! git -C "$DOTDIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "setup.sh: $DOTDIR is not a Git checkout; skip Codex config filter"
    return
  fi

  git -C "$DOTDIR" config --local filter.codex-config.clean \
    "bash agent-shared/bin/clean-codex-config.sh" \
    && git -C "$DOTDIR" config --local filter.codex-config.smudge cat \
    && git -C "$DOTDIR" config --local filter.codex-config.required true \
    || echo "setup.sh: could not configure Codex config filter"
}

if [ "${REMOTE_CONTAINERS:-}" != true ]; then
  link_config_dir "$DOTDIR/wezterm" "$XDG_CONFIG_HOME/wezterm"

  emacs_dir="$(dirname "$DOTDIR")/emacs"
  if ! git -C "$emacs_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$(dirname "$DOTDIR")" clone git@github.com:shishi/emacs.git \
      || echo "setup.sh: could not clone emacs; rerun setup.sh"
  fi
  if git -C "$emacs_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    link_config_dir "$emacs_dir" "$HOME/.emacs.d"
  fi
fi

for dir in fish nvim helix; do
  link_config_dir "$DOTDIR/$dir" "$XDG_CONFIG_HOME/$dir"
done

case "$(uname -s)" in
  MINGW* | MSYS*)
    herdr_config_dir="$(cygpath -u "$APPDATA")/herdr"
    herdr_config_source="$DOTDIR/herdr/config.windows.toml"
    ;;
  *)
    herdr_config_dir="$XDG_CONFIG_HOME/herdr"
    herdr_config_source="$DOTDIR/herdr/config.unix.toml"
    ;;
esac
mkdir -p "$herdr_config_dir"
ln -sfn "$herdr_config_source" "$herdr_config_dir/config.toml"

# A devcontainer may provide ~/.claude as a mount rather than a link.
if [ ! -L "$HOME/.claude" ] \
  && { mountpoint -q "$HOME/.claude" 2>/dev/null \
    || grep -qE "[[:space:]]$HOME/\.claude[[:space:]]" /proc/mounts 2>/dev/null; }; then
  echo "setup.sh: ~/.claude is a mount point; skip"
else
  link_agent_home "$DOTDIR/claude" "$HOME/.claude"
fi

case "$(uname -s)" in
  Darwin)
    ln -sfn "$DOTDIR/.gitconfig.mac" "$HOME/.gitconfig"
    ln -sfn "$DOTDIR/Brewfile" "$HOME/Brewfile"
    ;;
  Linux) ln -sfn "$DOTDIR/.gitconfig.linux" "$HOME/.gitconfig" ;;
  MINGW* | MSYS*) ln -sfn "$DOTDIR/.gitconfig.win" "$HOME/.gitconfig" ;;
esac

memory_dir="$(bash "$DOTDIR/agent-shared/bin/resolve-memory-dir.sh")" || memory_dir=
if [ -n "$memory_dir" ]; then
  if [ ! -d "$memory_dir" ]; then
    mkdir -p "$(dirname "$memory_dir")"
    git clone git@github.com:shishi/agent-memory.git "$memory_dir" 2>/dev/null \
      || gh repo clone shishi/agent-memory "$memory_dir" 2>/dev/null \
      || echo "setup.sh: could not clone agent-memory"
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

if [ -L "$XDG_CONFIG_HOME/nushell" ]; then
  rm "$XDG_CONFIG_HOME/nushell"
fi
mkdir -p "$XDG_CONFIG_HOME/nushell"
ln -sfn "$DOTDIR/nushell/config.nu" "$XDG_CONFIG_HOME/nushell/config.nu"
ln -sfn "$DOTDIR/nushell/env.nu" "$XDG_CONFIG_HOME/nushell/env.nu"

for file in .ideavimrc .vimrc .gvimrc .gemrc .rspec .pryrc .npmrc; do
  ln -sfn "$DOTDIR/$file" "$HOME/$file"
done
ln -sfn "$DOTDIR/.gitignore.global" "$HOME/.gitignore"

if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  bash "$DOTDIR/claude/install-plugins.sh" \
    || echo "setup.sh: Claude plugin install failed"
fi

if command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  bash "$DOTDIR/agent-shared/bin/herdr-plugins.sh" restore \
    || echo "setup.sh: Herdr plugin restore failed"
fi

if command -v herdr >/dev/null 2>&1; then
  herdr_status="$(env -u CLAUDE_CONFIG_DIR -u CODEX_HOME herdr integration status 2>/dev/null)"
  for integration in claude codex; do
    if ! printf '%s\n' "$herdr_status" | grep -q "^${integration}: current"; then
      env -u CLAUDE_CONFIG_DIR -u CODEX_HOME herdr integration install "$integration" \
        || echo "setup.sh: Herdr $integration integration install failed"
    fi
  done
fi

if command -v hunk >/dev/null 2>&1; then
  hunk_review_skill="$(hunk skill path hunk-review 2>/dev/null)" || hunk_review_skill=
  if [ -f "$hunk_review_skill" ]; then
    for skill_home in "$HOME/.claude/skills" "$HOME/.agent-shared/skills"; do
      mkdir -p "$skill_home/hunk-review"
      ln -sfn "$hunk_review_skill" "$skill_home/hunk-review/SKILL.md"
    done
  fi
fi

echo "please reload shell"
