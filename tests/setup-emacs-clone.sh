#!/usr/bin/env bash
# A failed clone must not replace an existing ~/.emacs.d.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/setup-emacs.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

DOTFILES="$TMP/dotfiles"
HOME_DIR="$TMP/home"
CONFIG_DIR="$TMP/config"
mkdir -p \
  "$DOTFILES/agent-shared/bin" "$DOTFILES/agent-shared/hooks" \
  "$DOTFILES/claude" "$DOTFILES/codex/skills" \
  "$DOTFILES/wezterm" "$DOTFILES/fish" "$DOTFILES/nvim" "$DOTFILES/helix" \
  "$DOTFILES/nushell" "$DOTFILES/herdr" \
  "$HOME_DIR/.emacs.d" "$CONFIG_DIR"
cp "$REPO/setup.sh" "$DOTFILES/setup.sh"
printf 'user config\n' >"$HOME_DIR/.emacs.d/init.el"
printf '' >"$DOTFILES/nushell/config.nu"
printf '' >"$DOTFILES/nushell/env.nu"
printf '' >"$DOTFILES/herdr/config.unix.toml"
printf '#!/usr/bin/env bash\nexit 1\n' >"$DOTFILES/agent-shared/bin/resolve-memory-dir.sh"

HOME="$HOME_DIR" XDG_CONFIG_HOME="$CONFIG_DIR" REMOTE_CONTAINERS=false \
  GIT_SSH_COMMAND=false bash "$DOTFILES/setup.sh" >/dev/null 2>&1

if [ -f "$HOME_DIR/.emacs.d/init.el" ] && [ ! -L "$HOME_DIR/.emacs.d" ]; then
  echo "PASS=1 FAIL=0"
else
  echo "PASS=0 FAIL=1"
  exit 1
fi
