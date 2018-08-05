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
if type direnv > /dev/null 2>&1
    eval (direnv hook fish)
end

# environment variables
#########################################

#set -x LANG ja_JP.UTF-8

set -x PATH ~/dev/bin /usr/local/sbin /usr/local/bin $PATH
set -x GOPATH ~/dev/

set -x EDITOR vim
set -x VISUAL vim

# if type emacsclient > /dev/null 2>&1
#     set -x EDITOR 'emacsclient -n --alternate-editor vim'
#     set -x VISUAL 'emacsclient -n --alternate-editor vim'
# else
#     set -x EDITOR vim
#     set -x VISUAL vim
# end

#set -x HOMEBREW_CASK_OPTS="--appdir=/Applications --caskroom=/usr/local/Caskroom"
#set -x CODECLIMATE_REPO_TOKEN=""
#set -x RIOT_GAMES_API_KEY=""

if [ (uname) = "Darwin" ]
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

if type less > /dev/null 2>&1
    set -x LESS '-R'
end

if type lv > /dev/null 2>&1
    set -x PAGER 'lv -c'
end

# rbenv
if test -d ~/.rbenv/bin
    set -x PATH ~/.rbenv/bin $PATH
end

# ruby
# if test -d ~/.gem/
#     set -x PATH (eval "ruby -e 'print Gem.user_dir'")/bin $PATH
# end

# cask
if test -f ~/.cask/bin/cask > /dev/null 2>&1
    set -x PATH ~/.cask/bin $PATH
end

# alias
#########################################

alias grep 'grep --color'
alias lv 'lv -c'

# git
alias g 'git'
alias gs 'git status -sb'
alias gl 'git log --graph --decorate --name-status'
alias gg 'git grep'
alias gd 'git diff'
alias ga 'git add'

# rails
alias be 'bundle exec'
alias rs 'bundle exec rails server'
alias rc 'bundle exec rails console'
alias rdm 'bundle exec rake db:migrate'
alias rdms 'bundle exec rake db:migrate; and bundle exec rake db:seed'
alias rdmr 'bundle exec rake db:migrate:reset'
alias rdmrs 'bundle exec rake db:migrate:reset; and bundle exec rake db:seed'

# docker
alias dcr 'docker-compose run'
alias dce 'docker-compose exec'

if [ (uname) = "MINGW64_NT-10.0" ]
    alias ghq 'ghq.exe'
    alias fzf 'fzf.exe'
else if [ (uname) = "Darwin" ]
    # alias brew_cask_upgrade 'for c in `brew cask list`; do ! brew cask info $c | grep -qF "Not installed"; or brew cask install $c; done'

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
else if [ (uname) = "Linux" ]
    alias open 'xdg-open'
    alias ll 'ls -la --color'
end

# function
#########################################

function su
    /bin/su --shell=/usr/bin/fish $argv
end

function remove_orphan
    if type yay > /dev/null 2>&1
        yay -Yc
    else
        pacman -Rns (pacman -Qtdq)
    end
end

# fzf

function ghq_fzf
  set dir (ghq root)/(ghq list | fzf)
    if [ (uname) = "MINGW64_NT-10.0" ]
        cd (cygpath $dir)
    else
        cd $dir
    end
    exec fish
end

function ghq_fzf_godoc
  set dir (ghq root)/(ghq list | fzf)
  godoc $dir | less
end

function fbr -d "Fuzzy-find and checkout a branch"
  git branch --all | grep -v HEAD | string trim | fzf | xargs git checkout
end

function fci -d "Fuzzy-find and checkout a commit"
  git log --pretty=oneline --abbrev-commit --reverse | fzf --tac +s -e | awk '{print $1;}' | xargs git checkout
end

function fssh -d "Fuzzy-find ssh host and ssh into it"
  ag '^host [^*]' ~/.ssh/config | cut -d ' ' -f 2 | fzf | xargs -o ssh
end

function fpass -d "Fuzzy-find a Lastpass entry and copy the password"
  if not lpass status -q
    lpass login $EMAIL
  end

  if not lpass status -q
    exit
  end

  lpass ls | fzf | string replace -r -a '.+\[id: (\d+)\]' '$1' | xargs lpass show -c --password
end

