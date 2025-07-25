set fish_color_command white

# environment variables
#########################################

#set -x LANG ja_JP.UTF-8
#set uname (uname -a)
#if [ (echo $uname | grep -c "microsoft") -gt 0 ] && ! test -f /.dockerenv
#    set dev /mnt/c/Users/shishi/dev
#else
#    set dev ~/dev
#end
set -x PATH ~/.local/bin ~/dev/bin /usr/local/sbin /usr/local/bin $PATH
# set -x PATH ~/.local/bin ~/dev/bin /usr/local/sbin /usr/local/bin /home/linuxbrew/.linuxbrew/bin $PATH
set -x GPG_TTY (tty)

if [ "$TERM_PROGRAM" = vscode ]
    set -x EDITOR code --wait
    set -x VISUAL code --wait
else if type nvim &>/dev/null
    set -x EDITOR nvim
    set -x VISUAL nvim
else
    set -x EDITOR vim
    set -x VISUAL vim
end

# if type emacsclient > /dev/null 2>&1
#     set -x EDITOR 'emacsclient -n --alternate-editor vim'
#     set -x VISUAL 'emacsclient -n --alternate-editor vim'
# else
#     set -x EDITOR vim
#     set -x VISUAL vim
# end

set -x GO111MODULE on
set -x GOBIN ~/.local/bin
set -x GOPATH ~/dev/

#set -x GHQ_ROOT $dev/src
#set -x HOMEBREW_CASK_OPTS="--appdir=/Applications --caskroom=/usr/local/Caskroom"
#set -x CODECLIMATE_REPO_TOKEN=""
#set -x RIOT_GAMES_API_KEY=""

# if [ (uname -r | sed -n 's/.*\( *Microsoft *\).*/\1/ip') ]
#   set -x BROWSER "/home/shishi/dev/src/github.com/shishi/dotfiles/wsl_browser.sh"
# end

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
    if type -d '/run/current-system/sw/bin/' &>/dev/null
        set -x PATH '/run/current-system/sw/bin/' $PATH
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

if type less &>/dev/null
    set -x LESS -R
end

set -x LESS '-q --ignore-case --no-init --long-prompt --raw-control-chars'
# set -x LESS '-q -N --ignore-case --no-init --long-prompt --raw-control-chars'
if type lv &>/dev/null
    set -x PAGER 'lv -c'
    # else
    #   set -x PAGER 'less -N --ignore-case -no-init --long-prompt --raw-control-chars'
end

# # mise
# if type mise &>/dev/null
#     if status is-interactive
#         mise activate fish | source
#     else
#         mise activate fish --shims | source
#     end
# # rbenv
# else if type ~/.rbenv/bin/rbenv &>/dev/null
#     set -x PATH ~/.rbenv/bin $PATH
#     status --is-interactive; and rbenv init - --no-rehash fish | source
# end

# # ruby
# if test -d ~/.gem/
#   set -x PATH (eval "ruby -e 'print Gem.user_dir'")/bin $PATH
# end

# tfenv
if test -f ~/.tfenv/bin/tfenv
    set -x PATH ~/.tfenv/bin $PATH
end

# cask
if test -f ~/.cask/bin/cask
    set -x PATH ~/.cask/bin $PATH
end

# aqua
# if type aqua &>/dev/nul1l
#     set -x AQUA_GLOBAL_CONFIG $AQUA_GLOBAL_CONFIG":"(test -n "$XDG_CONFIG_HOME"; and echo $XDG_CONFIG_HOME; or echo $HOME"/.config")"/aquaproj-aqua/aqua.yaml"
#     set -x PATH (test -n "$AQUA_ROOT_DIR"; and echo $AQUA_ROOT_DIR; or echo (test -n "$XDG_DATA_HOME"; and echo $XDG_DATA_HOME; or echo $HOME"/.local/share")"/aquaproj-aqua")"/bin" $PATH
# end

# rust tools
if type cargo &>/dev/null
    set -x PATH ~/.cargo/bin $PATH
    set -x CARGO_NET_GIT_FETCH_WITH_CLI true
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

# # vagrant in wsl
# if type vagrant &> /dev/null
#   if string match -q -- '*microsoft*' (uname -a)
#     # set -x PATH "$PATH:/mnt/c/Program Files/Oracle/VirtualBox"
#     set -x VAGRANT_WSL_ENABLE_WINDOWS_ACCESS "1"
#     # set -x VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH "/mnt/c/Users/shishi/"
#     # set -x VAGRANT_HOME "/mnt/c/Users/shishi/.vagrant.d"
#     # set -x VAGRANT_WSL_DISABLE_VAGRANT_HOME "true"
#   end
# end

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

# settings
#########################################

set fish_greeting

# cmorrell theme
set default_user shishi

# direnv
if type direnv &>/dev/null
    eval (direnv hook fish)
end

# alias
#########################################

switch (uname -a)
    case "*MINGW64*"
        alias ghq 'ghq.exe'
        alias fzf 'fzf.exe'
        alias docker 'docker.exe'
        alias docker-compose 'docker-compose.exe'
        alias docker-machine 'docker-machine.exe'
    case "*Darwin*"
        # alias brew_cask_upgrade 'for c in `brew cask list`; do ! brew cask info $c | grep -qF "Not installed"; or brew cask install $c; done'

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
        if test -f /opt/homebrew/bin/brew
            eval (/opt/homebrew/bin/brew shellenv)
        end

    case "*Linux*"
        alias ll 'ls -la --color'
        # alias open 'xdg-open'
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

# if type bat &>/dev/null
#     alias bat 'bat --color always'
# end
#
# if type fzf &>/dev/null
#     alias fzf "fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
# end

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

# abbr
#########################################

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
abbr --add gcl 'git clean --force'

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

# function
#########################################

switch (uname -a)
    case "*MINGW64*"
    case "*Linux*" "Darwin*"
        function su
            /bin/su --shell=/usr/bin/fish $argv
        end

        function ibus_restart
            ibus-daemon -drx
        end

        # ghq
        if type ghq &>/dev/null
            function __ghq_cd_repository -d "Change local repository directory"
                ghq list --full-path | fzf | read -l repo_path
                cd $repo_path
            end
            alias ghc __ghq_cd_github

            function __ghq_browse_github -d "Browse remote repository on github"
                ghq list | fzf | read -l repo_path
                set -l repo_name (string split -m1 "/" $repo_path)[2]
                # hub browse $repo_name
                open https://github.com/$repo_name
            end
            alias ghb __ghq_browse_github
        end

        # fzf
        if type fzf &>/dev/null
            function gb -d "Fuzzy-find and checkout a branch"
                git branch --all | grep -v HEAD | string trim | fzf | xargs git checkout
            end
        end

        function ln_setup
            bash ~/dev/src/github.com/shishi/dotfiles/setup.sh
        end

        function docker_run_with_current_user_and_dir
            docker run -it --rm -v /etc/group:/etc/group:ro -v /etc/passwd:/etc/passwd:ro -u (id -u $USER):(id -g $USER) -v (pwd):/src -w /src -e HOME=/src $argv
        end
end

# Arch
if [ -f /etc/arch-release ]
    function remove_orphan
        if type yay &>/dev/null
            yay -Yc
        else
            pacman -Rns (pacman -Qtdq)
        end
    end
end

# WSL
if [ (uname -r | sed -n 's/.*\( *Microsoft *\).*/\1/ip') ]
    function cdw
        cd /mnt/c/Users/shishi
    end
end

# ruby (mainly for nix now)
if not type mise >/dev/null 2>&1; and not type ~/.rbenv/bin/rbenv >/dev/null 2>&1
    function add_current_gem_path
        set -x PATH $HOME/.local/share/gem/ruby/(ruby -e "print Gem.ruby_api_version")/bin $PATH
    end
    add_current_gem_path

    function ruby_switch
        if test (count $argv) -eq 0
            echo "Usage: ruby-switch <version>"
            return 1
        end

        if test -d $HOME/.nix-profile-ruby-$argv[1]/bin
            set -x PATH $HOME/.nix-profile-ruby-$argv[1]/bin $PATH
            add_current_gem_path
            echo "switched to ruby $argv[1]"
        else
            echo "you do not have version $argv[1]"
        end
    end
end

#function fci -d "Fuzzy-find and checkout a commit"
#  git log --pretty=oneline --abbrev-commit --reverse | fzf --tac +s -e | awk '{print $1;}' | xargs git checkout
#end
#
#function fssh -d "Fuzzy-find ssh host and ssh into it"
#  ag '^host [^*]' ~/.ssh/config | cut -d ' ' -f 2 | fzf | xargs -o ssh
#end
#
#function fpass -d "Fuzzy-find a Lastpass entry and copy the password"
#  if not lpass status -q
#    lpass login $EMAIL
#  end
#
#  if not lpass status -q
#    exit
#  end
#
#  lpass ls | fzf | string replace -r -a '.+\[id: (\d+)\]' '$1' | xargs lpass show -c --password
#end

# source other file
#########################################

# source ~/.config/fish/functions/github_copilot_cli.fish


