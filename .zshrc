alias grep='grep --color'
alias lv='lv -c'

alias g='git'
alias gs='git status -sb'
alias gl='git log'
alias gg='git grep'
alias gd='git diff'
alias ga='git add'

alias be='bundle exec'
alias rs='bundle exec rails server'
alias rc='bundle exec rails console'
alias bgs='bundle exec guard start'
alias rdm='bundle exec rake db:migrate && RAILS_ENV=test bundle exec rake db:migrate'
alias rdms='bundle exec rake db:migrate && RAILS_ENV=test bundle exec rake db:migrate && bundle exec rake db:seed'
alias rdmr='bundle exec rake db:migrate:reset && RAILS_ENV=test bundle exec rake db:migrate:reset'
alias rdmrs='bundle exec rake db:migrate:reset && RAILS_ENV=test bundle exec rake db:migrate:reset && bundle exec rake db:seed'

alias brew_cask_upgrade='for c in `brew cask list`; do ! brew cask info $c | grep -qF "Not installed" || brew cask install $c; done'

export PATH=~/bin:/usr/local/sbin:/usr/local/bin:$PATH
export PATH=/usr/local/opt/findutils/libexec/gnubin:/usr/local/opt/coreutils/libexec/gnubin:$PATH

#export HOMEBREW_CASK_OPTS="--appdir=/Applications --caskroom=/usr/local/Caskroom"
export CODECLIMATE_REPO_TOKEN="81eb5c871ceafdf53bb05f2311220c146d7ffdb7d0e1854583902ed979fc8620"
export RIOT_GAMES_API_KEY="59034238-2ca4-4b27-9662-87fb1bbef12a"

fpath=(~/.zsh /usr/local/share/zsh/site-functions $fpath)
if [ -f /usr/local/share/zsh/site-functions/_aws ]; then
    autoload -Uz compinit
    compinit
    source /usr/local/share/zsh/site-functions/_aws #なぜかfpathだけだと読まれない
fi

if [ `uname` = Darwin ]; then
    #    if which emacs >/dev/null; then
    #        #alias emacs="/usr/local/Cellar/emacs/23.4/Emacs.app/Contents/MacOS/Emacs -nw"
    #    fi
    if which gls > /dev/null; then
        PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
        MANPATH="/usr/local/opt/coreutils/libexec/gnuman:$MANPATH"
        alias ll='gls -la --color'
    else
        alias ll='ls -laG'
    fi
else
    alias ll='ls -la --color'
fi

#if [ -f $(brew --prefix)/Library/Contributions/brew_zsh_completion.zsh ]; then
#    if [ ! -f ~/.zsh/_brew ]; then
#        ln -s "$(brew --prefix)/Library/Contributions/brew_zsh_completion.zsh" ~/.zsh/_brew
#    fi
#fi

if [ -d ~/.zsh/zsh-notify ]; then
    autoload add-zsh-hook
    source ~/.zsh/zsh-notify/notify.plugin.zsh
    # terminal-notifier install from homebrew
    export SYS_NOTIFIER="/usr/local/bin/terminal-notifier"
    export NOTIFY_COMMAND_COMPLETE_TIMEOUT=20
fi

if which emacsclient > /dev/null; then
    export EDITOR='emacsclient -n --alternate-editor vim'
else
    export EDITOR='vim'
fi

if which lv > /dev/null; then
    export PAGER='lv -c'
fi

# direnv
if which direnv > /dev/null; then
    # eval "$(direnv hook $0)"
    eval "$(direnv hook $SHELL)"
fi

# anyenv
if [ -d ~/.anyenv ]; then
    export PATH="$HOME/.anyenv/bin:$PATH"
    eval "$(anyenv init -)"
fi

# docker
#if which docker-machine > /dev/null; then
#    docker-machine start default
#    eval "$(docker-machine env default)"
#fi

# macvim-kaoriya
if [ -f /Applications/MacVim.app/Contents/MacOS/Vim ]; then
    PATH="/Applications/MacVim.app/Contents/MacOS:$PATH"
    alias vi='env LANG=ja_JP.UTF-8 /Applications/MacVim.app/Contents/MacOS/Vim "$@"'
    alias vim='env LANG=ja_JP.UTF-8 /Applications/MacVim.app/Contents/MacOS/Vim "$@"'
fi

# zsh option
#########################################
export LANG=ja_JP.UTF-8
HISTFILE=$HOME/.zsh-history
HISTSIZE=100000
SAVEHIST=100000

setopt prompt_subst
autoload -U colors; colors
# colors

# display git branch
autoload -Uz vcs_info
zstyle ':vcs_info:*' formats ':(%s)%b'
zstyle ':vcs_info:*' actionformats ':(%s)%b|%a'
precmd () {
    psvar=()
    LANG=en_US.UTF-8 vcs_info
    [[ -n "$vcs_info_msg_0_" ]] && psvar[1]="$vcs_info_msg_0_"
}

if [ `whoami` = root ];
then
    PROMPT="[%{${fg[red]}%}%B%n@%m%b]%#%{${reset_color}%} "
else
    PROMPT="[%{${fg[green]}%}%B%n@%m%b]%#%{${reset_color}%} "
fi
SPROMPT="%{${fg[red]}%}Maybe you want to type this command? %{${reset_color}%}> '%r' [%BY%bes %BN%bo %BA%bbort %BE%bdit] "
RPROMPT="["%1(v|%F{green}%1v%f|)"] [%{${fg[yellow]}%}%B%T%b%{${reset_color}%}] [%{${fg[cyan]}%}%B%/%b%{${reset_color}%}]"

# 右プロンプトを良い感じに消す
setopt transient_rprompt

export LSCOLORS=gxfxcxdxbxegedabagacad
export LS_COLORS='di=36:ln=35:so=32:pi=33:ex=31:bd=46;34:cd=43;34:su=41;30:sg=46;30:tw=42;30:ow=43;30'
#export LSCOLORS=gxfxxxxxcxxxxxxxxxgxgx

# Set up the prompt theme
autoload -Uz promptinit
promptinit
#prompt adam1

# ビープを鳴らさない
setopt nobeep

# emacs キーバインド
bindkey -e

# コアダンプサイズを制限
limit coredumpsize 102400

# 出力の文字列末尾に改行コードが無い場合でも表示
unsetopt promptcr

# 内部コマンド jobs の出力をデフォルトで jobs -l にする
setopt long_list_jobs

# 出力時8ビットを通す
setopt print_eight_bit

# サスペンド中のプロセスと同じコマンド名を実行した場合はリジューム
setopt auto_resume

# コマンド補正
setopt correct

# 補完機能の強化
autoload -U compinit
compinit

# 補完候補一覧でファイルの種別をマーク表示
setopt list_types

# 補完候補を一覧表示
setopt auto_list

# 検索に一致するものを補完
autoload history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey "^P" history-beginning-search-backward-end
bindkey "^N" history-beginning-search-forward-end

# 補完候補の色づけ
zstyle ':completion:*' list-colors 'di=36' 'ln=35' 'so=32' 'ex=31' 'bd=46;34' 'cd=43;34'

# zsh recommend
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
#eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# 補完を良い感じに中断できる
zstyle ':completion:*:default' menu select=1

# カッコの対応などを自動的に補完
setopt auto_param_keys

# ディレクトリ名の補完で末尾の / を自動的に付加し、次の補完に備える
setopt auto_param_slash

# TAB で順に補完候補を切り替える
setopt auto_menu

# --prefix=/usr などの = 以降も補完
setopt magic_equal_subst

# =command を command のパス名に展開する
setopt equals

# ファイル名で #, ~, ^ の 3 文字を正規表現として扱う
setopt extended_glob

# ヒストリを共有
setopt share_history

# 直前と同じコマンドをヒストリに追加しない
#setopt hist_ignore_dups

# すべての同じコマンドをヒストリを追加しない
setopt histignorealldups

# zsh の開始, 終了時刻をヒストリファイルに書き込む
setopt extended_history

# ヒストリを呼び出してから実行する間に一旦編集
setopt hist_verify

# ファイル名の展開で辞書順ではなく数値的にソート
setopt numeric_glob_sort

# ディレクトリ名だけで cd
setopt auto_cd
# ディレクトリ名をpush
setopt auto_pushd
# 同じディレクトリを pushd しない
setopt pushd_ignore_dups
