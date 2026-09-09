#!/usr/bin/env bash
# Re-sourcing config must preserve the running shell's environment.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/fish-reload.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/home"
cp -R "$REPO/fish" "$fixture_dir/fish"
printf '\nset -g reload_count (math $reload_count + 1)\n' >>"$fixture_dir/fish/config.fish"
HOME="$fixture_dir/home" XDG_CONFIG_HOME="$fixture_dir/home/.config" \
  FISH_RELOAD_CONFIG="$fixture_dir/fish/config.fish" fish --no-config --interactive -c 'source /dev/stdin' <<'FISH'
# Keep optional integrations deterministic and prevent startup filesystem writes.
function type
    switch $argv[-1]
        case nix cargo git-wt direnv ghq fzf
            return 0
        case '*'
            return 1
    end
end
function git
    echo 'set -g git_init_count (math $git_init_count + 1)'
end
function direnv
    echo 'set -g direnv_init_count (math $direnv_init_count + 1)'
end
function ruby
    echo 3.3.0
end
function ghq
    printf '%s\n' "$HOME"
end
function fzf
    cat
end
set -e GUAKE_TAB_UUID
set -g git_init_count 0
set -g direnv_init_count 0
set -g reload_count 0
source $FISH_RELOAD_CONFIG
ghc; or exit 1
if test "$PWD" != "$HOME"
    echo 'FAIL: ghc did not enter the selected repository' >&2
    exit 1
end
set -l initial_path (string join : -- $PATH)
source $FISH_RELOAD_CONFIG
if test "$initial_path" != (string join : -- $PATH)
    echo 'FAIL: reload changed PATH' >&2
    exit 1
end
if test $git_init_count -ne 1; or test $direnv_init_count -ne 1
    echo 'FAIL: integrations initialized more than once' >&2
    exit 1
end
set -gx PATH /chosen/ruby/bin $PATH
set -gx EDITOR chosen-editor
set -gx LESS chosen-less-options
set -l chosen_path (string join : -- $PATH)
abbr --erase g
source $FISH_RELOAD_CONFIG
if test "$chosen_path" != (string join : -- $PATH); or test "$EDITOR" != chosen-editor; or test "$LESS" != chosen-less-options
    echo 'FAIL: reload overwrote the selected environment' >&2
    exit 1
end
abbr --query g; or begin
    echo 'FAIL: reload skipped abbreviations' >&2
    exit 1
end
printf 'PASS: stable PATH, preserved environment, one-time integrations, reloaded abbreviations\n'

set -l previous_count $reload_count
emit fish_prompt
test $reload_count -eq $previous_count; or exit 1
printf '\nabbr --add autoreload_probe updated\n' >>$FISH_RELOAD_CONFIG
emit fish_prompt
if not abbr --query autoreload_probe; or test $reload_count -ne (math $previous_count + 1)
    echo 'FAIL: config change was not reloaded once at the prompt' >&2
    exit 1
end
printf '\nfunction autoreload_function_probe; echo updated; end\n' >> (path dirname $FISH_RELOAD_CONFIG)/startup-functions/__ghq_cd_repository.fish
emit fish_prompt
functions -q autoreload_function_probe; or begin
    echo 'FAIL: startup function change was not reloaded' >&2
    exit 1
end
if test "$chosen_path" != (string join : -- $PATH); or test "$EDITOR" != chosen-editor; or test $direnv_init_count -ne 1; or test $git_init_count -ne 1
    echo 'FAIL: automatic reload changed the running environment' >&2
    exit 1
end
set -l previous_count $reload_count
cp $FISH_RELOAD_CONFIG $FISH_RELOAD_CONFIG.valid
printf '\nif\n' >>$FISH_RELOAD_CONFIG
emit fish_prompt 2>/dev/null
test $reload_count -eq $previous_count; or exit 1
mv $FISH_RELOAD_CONFIG.valid $FISH_RELOAD_CONFIG
emit fish_prompt
test $reload_count -eq (math $previous_count + 1); or exit 1
printf 'PASS: prompt reloads changed config and functions, skips unchanged/invalid config, recovers after correction\n'
FISH
