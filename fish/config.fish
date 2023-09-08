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

# rbenv
if test -d ~/.rbenv/bin
    set -x PATH ~/.rbenv/bin $PATH
end

# # ruby
# if test -d ~/.gem/
#   set -x PATH (eval "ruby -e 'print Gem.user_dir'")/bin $PATH
# end

# tfenv
if test -d ~/.tfenv/bin
    set -x PATH ~/.tfenv/bin $PATH
end

# cask
if test -f ~/.cask/bin/cask
    set -x PATH ~/.cask/bin $PATH
end

# rust
if test -d ~/.cargo/bin
    set -x PATH ~/.cargo/bin $PATH
    set -x CARGO_NET_GIT_FETCH_WITH_CLI true
end

if type bat &>/dev/null
    set -x BAT_THEME zenburn
    set -x BAT_STYLE auto
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

# settings
#########################################

set fish_greeting

# cmorrell theme
set default_user shishi

# rbenv
if test -d ~/.rbenv
    status --is-interactive; and source (rbenv init -|psub)
end

# direnv
if type direnv &>/dev/null
    eval (direnv hook fish)
end

# alias
#########################################

alias n nvim
alias grep 'grep --color'
alias lv 'lv -c'

# git
alias g git
alias gs 'git status -sb'
alias gl 'git log --graph --decorate --name-status'
alias gg 'git grep'
alias gd 'git diff'
alias ga 'git add'
alias gb 'git branch'

# rails
alias be 'bundle exec'
alias rs 'bundle exec rails server'
alias rc 'bundle exec rails console'
alias rdm 'bundle exec rake db:migrate'
alias rdms 'bundle exec rake db:migrate; and bundle exec rake db:seed'
alias rdmr 'bundle exec rake db:migrate:reset'
alias rdmrs 'bundle exec rake db:migrate:reset; and bundle exec rake db:seed'

# docker
if type docker-compose &>/dev/null
    alias dc docker-compose
    alias dcr 'docker-compose run --rm'
    alias dce 'docker-compose exec'
else
    alias dc 'docker compose'
    alias dcr 'docker compose run --rm'
    alias dce 'docker compose exec'
    alias docker-compose "docker compose"
end


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

if type batcat &>/dev/null
    ln -fs (which batcat) ~/.local/bin/bat
end

if type fdfind &>/dev/null
    ln -fs (which fdfind) ~/.local/bin/fd
end

# if type bat &> /dev/null
#   alias bat 'bat --color always'
#   if type fzf &> /dev/null
#     alias fzf "fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
#   end
# end

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
