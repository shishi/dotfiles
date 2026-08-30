#!/usr/bin/env bash
# setup.sh が既存の agent runtime を退避し、管理対象への link を張る契約だけを検証する。
set -u

case "$(uname -s)" in
  MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SETUP="$REPO/setup.sh"
SYSTEM_GIT="$(command -v git)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }
assert() { local description="$1"; shift; if "$@"; then ok "$description"; else ng "$description"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/setup-home-links.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

DOTFILES="$TMP/dotfiles"
HOME_DIR="$TMP/home"
CONFIG_DIR="$TMP/config"
MEMORY_DIR="$TMP/agent-memory"
mkdir -p \
  "$DOTFILES/agents/bin" "$DOTFILES/agents/hooks" \
  "$DOTFILES/claude" "$DOTFILES/codex/skills" \
  "$DOTFILES/fish" "$DOTFILES/nvim" "$DOTFILES/helix" \
  "$DOTFILES/nushell" "$DOTFILES/herdr/herdr-lazy" \
  "$HOME_DIR/.claude" "$HOME_DIR/.codex" "$HOME_DIR/.agents/skills" \
  "$CONFIG_DIR" "$TMP/appdata" "$MEMORY_DIR"

cp "$SETUP" "$DOTFILES/setup.sh"
cp "$REPO/agents/bin/resolve-memory-dir.sh" "$DOTFILES/agents/bin/resolve-memory-dir.sh"
printf 'runtime\n' >"$HOME_DIR/.claude/history.jsonl"
printf 'runtime\n' >"$HOME_DIR/.codex/history.jsonl"
printf 'runtime\n' >"$HOME_DIR/.agents/skills/local.txt"
printf '' >"$DOTFILES/nushell/config.nu"
printf '' >"$DOTFILES/nushell/env.nu"
printf '' >"$DOTFILES/herdr/config.unix.toml"
printf '' >"$DOTFILES/herdr/config.windows.toml"
printf '#!/usr/bin/env bash\nexit 0\n' >"$DOTFILES/claude/install-plugins.sh"
for file in .gitconfig.linux .gitconfig.mac .gitconfig.win .gitignore.global \
  .ideavimrc .vimrc .gvimrc .gemrc .rspec .pryrc .npmrc; do
  printf '' >"$DOTFILES/$file"
done

"$SYSTEM_GIT" -C "$MEMORY_DIR" init -q
"$SYSTEM_GIT" -C "$MEMORY_DIR" branch -M main
"$SYSTEM_GIT" -C "$MEMORY_DIR" config user.name test
"$SYSTEM_GIT" -C "$MEMORY_DIR" config user.email test@example.invalid
"$SYSTEM_GIT" -C "$MEMORY_DIR" config commit.gpgSign false
"$SYSTEM_GIT" -C "$MEMORY_DIR" remote add origin git@github.com:shishi/agent-memory.git
printf '# Memory\n' >"$MEMORY_DIR/MEMORY.md"
printf '# Conventions\n' >"$MEMORY_DIR/CONVENTIONS.md"
"$SYSTEM_GIT" -C "$MEMORY_DIR" add MEMORY.md CONVENTIONS.md
"$SYSTEM_GIT" -C "$MEMORY_DIR" commit -qm init

# 実マシンの任意 integration は fixture の対象外。
cat >"$TMP/hide-optional.sh" <<'EOF'
command() {
  if [ "${1:-}" = -v ]; then
    case "${2:-}" in claude | herdr | herdr-bootstrap | hunk) return 1 ;; esac
  fi
  builtin command "$@"
}
EOF

run_setup() {
  HOME="$HOME_DIR" XDG_CONFIG_HOME="$CONFIG_DIR" APPDATA="$TMP/appdata" \
    REMOTE_CONTAINERS=true AGENT_MEMORY_DIR="$MEMORY_DIR" \
    BASH_ENV="$TMP/hide-optional.sh" bash "$DOTFILES/setup.sh" \
    >"$TMP/setup.log" 2>&1
}

resolves_to() {
  local actual expected
  [ -L "$1" ] || return 1
  actual="$(realpath "$1")" || return 1
  expected="$(realpath "$2")" || return 1
  [ "$actual" = "$expected" ]
}

run_setup
assert "Claude home is linked" resolves_to "$HOME_DIR/.claude" "$DOTFILES/claude"
assert "Codex home is linked" resolves_to "$HOME_DIR/.codex" "$DOTFILES/codex"
assert "personal skills are linked" resolves_to "$HOME_DIR/.agents/skills" "$DOTFILES/codex/skills"
assert "Claude runtime is preserved in backup" test -f "$HOME_DIR/.claude.back/history.jsonl"
assert "Codex runtime is preserved in backup" test -f "$HOME_DIR/.codex.back/history.jsonl"
assert "personal skill runtime is preserved in backup" test -f "$HOME_DIR/.agents/skills.back/local.txt"
assert "Claude memory uses the canonical private repo" resolves_to "$DOTFILES/claude/memory" "$MEMORY_DIR"
assert "Codex memory uses the canonical private repo" resolves_to "$DOTFILES/codex/memory" "$MEMORY_DIR"

run_setup
if [ ! -e "$HOME_DIR/.claude.back.1" ] && [ ! -e "$HOME_DIR/.codex.back.1" ]; then
  ok "rerun keeps correct links without extra backups"
else
  ng "rerun keeps correct links without extra backups"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
