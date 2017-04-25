# environment variables
#########################################

#set -x LANG ja_JP.UTF-8

set -x PATH /usr/local/sbin /usr/local/bin $PATH

#set -x HOMEBREW_CASK_OPTS="--appdir=/Applications --caskroom=/usr/local/Caskroom"
#set -x CODECLIMATE_REPO_TOKEN=""
#set -x RIOT_GAMES_API_KEY=""

if [ (uname) = Darwin ]
    if type gls > /dev/null 2>&1
        set -x PATH /usr/local/opt/coreutils/libexec/gnubin $PATH
        set -x MANPATH /usr/local/opt/coreutils/libexec/gnuman $MANPATH
    end

    if type gfind > /dev/null 2>&1
        set -x PATH /usr/local/opt/findutils/libexec/gnubin $PATH
        set -x MANPATH /usr/local/opt/findutils/libexec/gnuman $MANPATH
    end

    if test -f ~/Applications/MacVim.app/Contents/MacOS/Vim
        set -x PATH ~/Applications/MacVim.app/Contents/MacOS $PATH
    end
end

if type emacsclient > /dev/null 2>&1
    set -x EDITOR 'emacsclient -n --alternate-editor vim'
    set -x VISUAL 'emacsclient -n --alternate-editor vim'
else
    set -x EDITOR vim
    set -x VISUAL vim
end

if type lv > /dev/null 2>&1
    set -x PAGER 'lv -c'
end

# rbenv
if test -d ~/.rbenv
    set -x PATH ~/.rbenv/bin $PATH
end

# alias
#########################################

alias grep 'grep --color'
alias lv 'lv -c'

alias g 'git'
alias gs 'git status -sb'
alias gl 'git log --graph --oneline --decorate=full'
alias gg 'git grep'
alias gd 'git diff'
alias ga 'git add'

alias be 'bundle exec'
alias rs 'bundle exec rails server'
alias rc 'bundle exec rails console'
alias rdm 'bundle exec rake db:migrate'
alias rdms 'bundle exec rake db:migrate; and bundle exec rake db:seed'
alias rdmr 'bundle exec rake db:migrate:reset'
alias rdmrs 'bundle exec rake db:migrate:reset; and bundle exec rake db:seed'

alias dcr 'docker-compose run'
alias dce 'docker-compose exec'

if [ (uname) = Darwin ]
    alias brew_cask_upgrade 'for c in `brew cask list`; do ! brew cask info $c | grep -qF "Not installed"; or brew cask install $c; done'

    # ll
    if type gls > /dev/null 2>&1
        alias ll 'gls -la --color'
    else
        alias ll 'ls -laG'
    end

    # macvim-kaoriya
    if test -f ~/Applications/MacVim.app/Contents/MacOS/Vim
        alias vi 'env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOS/Vim "$@"'
        alias vim 'env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOpS/Vim "$@"'
    end
else
    alias ll 'ls -la --color'
end

# other setting
#########################################

# cmorrell theme
set default_user shishi

# rbenv
status --is-interactive; and source (rbenv init -|psub)

# direnv
if type direnv > /dev/null 2>&1
    eval (direnv hook fish)
end
