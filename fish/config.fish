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

set -x GOPATH ~/dev
#set -x GHQ_ROOT $dev/src

set -x EDITOR vim
set -x VISUAL vim
set -x GPG_TTY (tty)

set -x LESS '--no-init --shift 4 --LONG-PROMPT'

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
  if type gls >/dev/null 2>&1
    set -x PATH /usr/local/opt/coreutils/libexec/gnubin $PATH
    set -x MANPATH /usr/local/opt/coreutils/libexec/gnuman $MANPATH
  end

  if type gfind >/dev/null 2>&1
    set -x PATH /usr/local/opt/findutils/libexec/gnubin $PATH
    set -x MANPATH /usr/local/opt/findutils/libexec/gnuman $MANPATH
  end

  if test -f ~/Applications/MacVim.app/Contents/MacOS/Vim
    set -x PATH ~/Applications/MacVim.app/Contents/MacOS $PATH
  end
end

if type less >/dev/null 2>&1
  set -x LESS '-R'
end

if type lv >/dev/null 2>&1
  set -x PAGER 'lv -c'
end

# rbenv
if test -d ~/.rbenv/bin
  set -x PATH ~/.rbenv/bin $PATH
end

# # ruby
# if test -d ~/.gem/
#   set -x PATH (eval "ruby -e 'print Gem.user_dir'")/bin $PATH
# end

# cask
if test -f ~/.cask/bin/cask >/dev/null 2>&1
  set -x PATH ~/.cask/bin $PATH
end

# vagrant in wsl
if type vagrant > /dev/null 2>&1
    if string match -q -- '*microsoft*' (uname -a)
        # set -x PATH "$PATH:/mnt/c/Program Files/Oracle/VirtualBox"
        set -x VAGRANT_WSL_ENABLE_WINDOWS_ACCESS "1"
        # set -x VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH "/mnt/c/Users/shishi/"
        # set -x VAGRANT_HOME "/mnt/c/Users/shishi/.vagrant.d"
        # set -x VAGRANT_WSL_DISABLE_VAGRANT_HOME "true"
    end
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
if type direnv >/dev/null 2>&1
  eval (direnv hook fish)
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
alias dc 'docker-compose'
alias dcr 'docker-compose run --rm'
alias dce 'docker-compose exec'

switch (uname -a)
<<<<<<< HEAD
  case "*MINGW64*"
    alias ghq 'ghq.exe'
    alias fzf 'fzf.exe'
    alias docker 'docker.exe'
    alias docker-compose 'docker-compose.exe'
    alias docker-machine 'docker-machine.exe'
  case "*Darwin*"
    # alias brew_cask_upgrade 'for c in `brew cask list`; do ! brew cask info $c | grep -qF "Not installed"; or brew cask install $c; done'

    # ll
    if type gls >/dev/null 2>&1
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
    if string match -q -- '*Microsoft*' (uname -a)
      alias docker 'docker.exe'
      alias docker-compose 'docker-compose.exe'
      alias docker-machine 'docker-machine.exe'
    end

    alias ll 'ls -la --color'
    # alias open 'xdg-open'
=======
    case "*MINGW64*"
        alias ghq 'ghq.exe'
        alias fzf 'fzf.exe'
        alias docker 'docker.exe'
        alias docker-compose 'docker-compose.exe'
        alias docker-machine 'docker-machine.exe'
    case "*Darwin*"
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
    case "*Linux*"
        if string match -q -- '*microsoft*' (uname -a)
            alias docker 'docker.exe'
            alias docker-compose 'docker-compose.exe'
            alias docker-machine 'docker-machine.exe'
        end

        alias ll 'ls -la --color'
        # alias open 'xdg-open'
>>>>>>> bece6781f4bfbc42c3c895130697b5dbd2be9daa
end

# function
#########################################

function su
  /bin/su --shell=/usr/bin/fish $argv
end

function __ghq_cd_repository -d "Change local repository directory"
  ghq list --full-path | fzf | read -l repo_path
  cd $repo_path
end
alias ghc __ghq_cd_github

function __ghq_browse_github -d "Browse remote repository on github"
  ghq list | fzf | read -l repo_path
  set -l repo_name (string split -m1 "/" $repo_path)[2]
  hub browse $repo_name
end

alias ghb __ghq_browse_github

function remove_orphan
  if type yay >/dev/null 2>&1
    yay -Yc
  else
    pacman -Rns (pacman -Qtdq)
  end
end

function ln_setup
  bash ~/dev/src/github.com/shishi/dotfiles/ln_setup.sh
end

# WSL

function cdw
  cd /mnt/c/Users/shishi
end

# fzf

function fbr -d "Fuzzy-find and checkout a branch"
    git branch --all | grep -v HEAD | string trim | fzf | xargs git checkout
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

# etc
#########################################

if test -f ~/.config/fish/functions/pepabo.fish >/dev/null 2>&1
  source ~/.config/fish/functions/pepabo.fish
end



