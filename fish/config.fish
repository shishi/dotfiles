# Environment and tool initialization run once per shell.
# Reloading keeps runtime overrides, including the Ruby selected in this shell.
if not set -q __dotfiles_fish_initialized
    # Environment and tool paths

    set -x PATH ~/.local/bin ~/dev/bin ~/.bun/bin /usr/local/sbin /usr/local/bin $PATH

    set -x GPG_TTY (tty)

    set -x EDITOR nvim
    set -x VISUAL nvim

    # nh(nix-config)の対象 flake。引数なし `nh home switch` など用。非 nix マシンでは無害
    set -x NH_FLAKE ~/dev/src/github.com/shishi/nix-config

    set -x GO111MODULE on
    set -x GOBIN ~/.local/bin
    set -x GOPATH ~/dev/

    if [ (uname) = Darwin ]
        if type gls &>/dev/null
            set -x PATH /usr/local/opt/coreutils/libexec/gnubin $PATH
            set -x MANPATH /usr/local/opt/coreutils/libexec/gnuman $MANPATH
        end

        if type gfind &>/dev/null
            set -x PATH /usr/local/opt/findutils/libexec/gnubin $PATH
            set -x MANPATH /usr/local/opt/findutils/libexec/gnuman $MANPATH
        end

        if test -f ~/Applications/MacVim.app/Contents/MacOS/Vim
            set -x PATH ~/Applications/MacVim.app/Contents/MacOS $PATH
        end

        # nix-darwin
        if type -d /run/current-system/sw/bin/ &>/dev/null
            set -x PATH /run/current-system/sw/bin/ $PATH
        end

        # jetbrains toolbox
        if type -d "~/Library/Application Support/JetBrains/Toolbox/scripts" &>/dev/null
            set -x PATH "~/Library/Application Support/JetBrains/Toolbox/scripts" $PATH
        end

        # orbstack
        if type orb &>/dev/null
            set -x PATH ~/.orbstack/bin $PATH
            # Added by OrbStack: command-line tools and integration
            # This won't be added again if you remove it.
            source ~/.orbstack/shell/init2.fish 2>/dev/null || :
        end
    end

    set -x LESS '-q --ignore-case --no-init --long-prompt --raw-control-chars'
    if type lv &>/dev/null
        set -x PAGER 'lv -c'
    end

    # rust tools / PATH 契約(nix > cargo > システム既定)
    # conf.d(nix.fish → rustup.fish)が cargo > nix の逆順で前方挿入してくるため、
    # 最後に無条件で並べ直す。存在しないディレクトリは無害(非 nix / 非 rust マシン)
    if type cargo &>/dev/null
        set -x PATH ~/.cargo/bin $PATH
        set -x CARGO_NET_GIT_FETCH_WITH_CLI true
    end

    # tfenv
    if test -f ~/.tfenv/bin/tfenv
        set -x PATH ~/.tfenv/bin $PATH
    end

    # cask
    if test -f ~/.cask/bin/cask
        set -x PATH ~/.cask/bin $PATH
    end

    if type bat &>/dev/null
        set -x BAT_THEME zenburn
        set -x BAT_STYLE auto
    end

    if type batcat &>/dev/null
        ln -fs (which batcat) ~/.local/bin/bat
    end

    if type fdfind &>/dev/null
        if test -d ~/.local/bin
            ln -fs (which fdfind) ~/.local/bin/fd
        else
            sudo ln -fs (which fdfind) /usr/local/bin/fd
        end
    end

    # use buildkit
    if type docker &>/dev/null
        set -x DOCKER_BUILDKIT 1
    end

    # flyio
    if test -d ~/.fly &>/dev/null
        set -x FLYCTL_INSTALL ~/.fly
        set -x PATH $FLYCTL_INSTALL/bin $PATH
    end

    # console-ninja
    if test -d ~/.console-ninja &>/dev/null
        set -x PATH ~/.console-ninja/.bin $PATH
    end

    # claude code
    if test -f ~/.claude/local/claude &>/dev/null
        set -x PATH ~/.claude/local $PATH
    end

    # git-wt
    if type git-wt &>/dev/null
        git wt --init fish | source
    end

end

# Interactive appearance and integrations

set fish_color_command white
set fish_greeting

# cmorrell theme
set default_user shishi

# direnv
if not set -q __dotfiles_fish_initialized; and type direnv &>/dev/null
    eval (direnv hook fish)
end

# Command aliases

switch (uname -a)
    case "*MINGW64*"
        alias ghq 'ghq.exe'
        alias fzf 'fzf.exe'
        alias docker 'docker.exe'
        alias docker-compose 'docker-compose.exe'
        alias docker-machine 'docker-machine.exe'
    case "*Darwin*"

        # ll
        if type gls &>/dev/null
            alias ll 'gls -la --color'
        else
            alias ll 'ls -laG'
        end

        # macvim-kaoriya
        if test -f ~/Applications/MacVim.app/Contents/MacOS/Vim
            alias vi 'env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOS/Vim "$@"'
            alias vim 'env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOpS/Vim "$@"'
        end

        # homebrew
        if not set -q __dotfiles_fish_initialized; and test -f /opt/homebrew/bin/brew
            eval (/opt/homebrew/bin/brew shellenv)
        end

    case "*Linux*"
        alias ll 'ls -la --color'
end

# WSL
if test -f '/mnt/c/Users/shishi/AppData/Local/Programs/Microsoft VS Code/bin/code'
    alias code '/mnt/c/Users/shishi/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code'
end

# rust tools
if type eza &>/dev/null
    alias ls eza
    alias ll 'eza -lahg --git --icons --time-style=long-iso'
    alias lt 'eza -T --icons --git-ignore'
end

# Windows

# windows explorer
if test -e /mnt/c/Windows/explorer.exe &>/dev/null
    alias explorer /mnt/c/Windows/explorer.exe
    alias open /mnt/c/Windows/explorer.exe
end

# wezterm in windows
if test -e /mnt/c/Users/shishi/scoop/shims/wezterm.exe &>/dev/null
    alias wezterm /mnt/c/Users/shishi/scoop/shims/wezterm.exe
    alias wez /mnt/c/Users/shishi/scoop/shims/wezterm.exe
end

# neovide in windows
if test -e /mnt/c/Users/shishi/scoop/apps/neovide/current/neovide.exe &>/dev/null
    alias neovide '/mnt/c/Users/shishi/scoop/apps/neovide/current/neovide.exe --multigrid --wsl'
end

# Command abbreviations

abbr --add n nvim

# git
abbr --add g git
abbr --add gs 'git status -sb'
abbr --add gco 'git checkout'
abbr --add gci 'git commit -m'
abbr --add gcia 'git commit --amend'
abbr --add gl 'git log --graph --decorate --name-status'
abbr --add gg 'git grep'
abbr --add gd 'git diff'
abbr --add ga 'git add'
abbr --add gb 'git branch'
abbr --add gP 'git push'
abbr --add gPf 'git push --force-with-lease'
abbr --add gPF 'git push --force'
abbr --add gp 'git pull'
abbr --add gr 'git rebase'
abbr --add grc 'git rebase --continue'
abbr --add gra 'git rebase --abort'
abbr --add gm 'git merge'
abbr --add gmc 'git merge --continue'
abbr --add gma 'git merge --abort'
abbr --add gcl 'git clean --force'

# git worktree (git-wt)
# 関数ではなく abbr にすることで、展開後のコマンド行が `git wt ...` になり
# git-wt が提供する補完 (ブランチ名 / worktree 名) がそのまま効く。
if type git-wt &>/dev/null
    abbr --add gwt 'git wt'
    abbr --add gwtd 'git wt -d'
    abbr --add gwtD 'git wt -D'
end

# rails
abbr --add be 'bundle exec'
abbr --add rs 'bundle exec rails server'
abbr --add rc 'bundle exec rails console'
abbr --add rdm 'bundle exec rails db:migrate; and RAILS_ENV=test bundle exec rails db:migrate'
abbr --add rdms 'bundle exec rails db:migrate; and bundle exec rails db:seed'
abbr --add rdmr 'bundle exec rails db:migrate:reset'
abbr --add rdmrs 'bundle exec rails db:migrate:reset; and bundle exec rails db:seed'

# docker
if type docker-compose &>/dev/null
    abbr --add dc docker-compose
    abbr --add dcr 'docker-compose run --rm'
    abbr --add dce 'docker-compose exec'
else
    abbr --add dc 'docker compose'
    abbr --add dcr 'docker compose run --rm'
    abbr --add dce 'docker compose exec'
    abbr --add docker-compose "docker compose"
end

# Conditional functions and startup actions
# Unconditional functions are autoloaded from functions/.

# vime skkeleton
if not set -q __dotfiles_fish_initialized; and test -n "$GUAKE_TAB_UUID"
    then
    nvim -c startinsert /tmp/tmp_input
    cat /tmp/tmp_input | xsel --clipboard --input
    rm /tmp/tmp_input
    exit 0
end

# ghq
if type ghq &>/dev/null
    source (status dirname)/startup-functions/__ghq_cd_repository.fish
    alias ghc __ghq_cd_repository

    source (status dirname)/startup-functions/__ghq_browse_github.fish
    alias ghb __ghq_browse_github
end

# fzf git branch
if type fzf &>/dev/null
    source (status dirname)/startup-functions/gbf.fish
end

# git worktree: 一覧から fzf で選んで cd (作成・削除は abbr の gwt / gwtd)
if type git-wt &>/dev/null; and type fzf &>/dev/null; and type jq &>/dev/null
    source (status dirname)/startup-functions/gw.fish
end

# Arch
if [ -f /etc/arch-release ]
    source (status dirname)/startup-functions/remove_orphan.fish
end

# WSL
if [ (uname -r | sed -n 's/.*\( *Microsoft *\).*/\1/ip') ]
    source (status dirname)/startup-functions/cdw.fish
end

# nix
## ruby (mainly for nix now)
if not type mise >/dev/null 2>&1; and not type ~/.rbenv/bin/rbenv >/dev/null 2>&1
    source (status dirname)/startup-functions/add_current_gem_path.fish
    if not set -q __dotfiles_fish_initialized
        add_current_gem_path
    end

    # ruby_switch <version>: 現在のシェルの ruby を nixpkgs の任意バージョンへ切り替える
    # 例: ruby_switch 3.3 / ruby_switch 3_4 / ruby_switch ruby_3_3
    source (status dirname)/startup-functions/ruby_switch.fish
end

# Final PATH priority: Nix before Cargo and inherited paths
if not set -q __dotfiles_fish_initialized; and type nix &>/dev/null
    set -x PATH /nix/var/nix/profiles/default/bin ~/.nix-profile/bin $PATH
end

# Global, not exported: a newly started fish must initialize independently.
set -gu __dotfiles_fish_initialized 1
