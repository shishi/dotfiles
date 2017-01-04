# zsh option
#########################################
export LANG=ja_JP.UTF-8

# colors
autoload -Uz colors
colors

eval $(dircolors ~/.zsh/dircolors.256dark)

if [ -n "$LS_COLORS" ]; then
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
fi

# ビープを鳴らさない
setopt nobeep

# emacs キーバインド
bindkey -e

# サスペンド中のプロセスと同じコマンド名を実行した場合はリジューム
setopt auto_resume

# Ctrl+Dでzshを終了しない
setopt ignore_eof

# display

# autoload -Uz promptinit
# promptinit
# #prompt adam1

setopt prompt_subst

# 右プロンプトを良い感じに消す
setopt transient_rprompt

# 出力の文字列末尾に改行コードが無い場合でも表示
unsetopt promptcr

# 内部コマンド jobs の出力をデフォルトで jobs -l にする
setopt long_list_jobs

# マルチバイト文字表示
setopt print_eight_bit

# ファイル名で #, ~, ^ の 3 文字を正規表現として扱う
setopt extended_glob

# ファイル名の展開で辞書順ではなく数値的にソート
setopt numeric_glob_sort

# history

HISTFILE=$HOME/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

# history search
autoload -U history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey "^[p" history-beginning-search-backward-end
bindkey "^[n" history-beginning-search-forward-end

# ヒストリを共有
setopt share_history

# コマンドが入力されるとすぐに追加
setopt inc_append_history

# zsh の開始, 終了時刻をヒストリファイルに書き込む
setopt extended_history

# 補完時に履歴を自動的に展開
setopt hist_expand

# 入力したコマンドが直前のものと同一なら古いコマンドのほうを削除する
setopt hist_save_no_dups

# ラインエディタでヒストリ検索し、ヒットした場合でも重複したものとみなさない
setopt hist_find_no_dups

# 入力したコマンドを履歴に登録する時、同一がすでに存在した場合登録しない
setopt hist_ignore_all_dups

# 関数定義のためのコマンドは履歴から削除する
setopt hist_no_functions

# 履歴参照のコマンドは履歴に登録しない
setopt hist_no_store

# コマンド中の余分な空白を削除する
setopt hist_reduce_blanks

# ヒストリを呼び出してから実行する間に一旦編集
setopt hist_verify

# ディレクトリ名だけでcd
setopt auto_cd

# ディレクトリ名をpush
setopt auto_pushd

# 同じディレクトリをpushしない
setopt pushd_ignore_dups

# auto complete
LISTMAX=1000

autoload -Uz compinit
compinit -u

# 補完候補一覧でファイルの種別をマーク表示
setopt list_types

# 候補を詰めて表示
setopt list_packed

# 補完候補が複数ある時、一回目のTABで一覧表示
setopt auto_list

# 補完候補のカーソル選択を有効に
zstyle ':completion:*:default' menu select=1

# TAB で順に補完候補を切り替える
setopt auto_menu

# --prefix=/usr などの = 以降も補完
setopt magic_equal_subst

# =command を command のパス名に展開する
setopt equals

# コマンド補正
setopt correct

# 大文字小文字無視
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

if [ `whoami` = root ];
then
    PROMPT="[%{${fg[red]}%}%B%n@%m%b]%#%{${reset_color}%} "
else
    PROMPT="[%{${fg[green]}%}%B%n@%m%b]%#%{${reset_color}%} "
fi

# display git branch
autoload -Uz vcs_info
# zstyle ':vcs_info:git:*' check-for-changes true
# zstyle ':vcs_info:git:*' stagedstr "+"
# zstyle ':vcs_info:git:*' unstagedstr "-"
# zstyle ':vcs_info:*' formats '(%s)%c%u%b'
# zstyle ':vcs_info:*' actionformats '(%s)%c%u%b|%a'
zstyle ':vcs_info:*' formats '(%s)%b'
zstyle ':vcs_info:*' actionformats '(%s)%b|%a'

precmd () {
    psvar=()
    LANG=en_US.UTF-8 vcs_info
    [[ -n "$vcs_info_msg_0_" ]] && psvar[1]="$vcs_info_msg_0_"
}

RPROMPT="["%1(v|%F{green}%1v%f|)"] [%{${fg[yellow]}%}%B%T%b%{${reset_color}%}] [%{${fg[cyan]}%}%B%/%b%{${reset_color}%}]"

SPROMPT="%{${fg[red]}%}Maybe you want to type this command? %{${reset_color}%}> '%r' [%BY%bes %BN%bo %BA%bbort %BE%bdit] "

# alias
#########################################

alias grep='grep --color'
alias lv='lv -c'

alias g='git'
alias gs='git status -sb'
alias gl='git log --graph --oneline --decorate=full'
alias gg='git grep'
alias gd='git diff'
alias ga='git add'

alias be='bundle exec'
alias rs='bundle exec rails server'
alias rc='bundle exec rails console'
alias rdm='bundle exec rake db:migrate'
alias rdms='bundle exec rake db:migrate && bundle exec rake db:seed'
alias rdmr='bundle exec rake db:migrate:reset'
alias rdmrs='bundle exec rake db:migrate:reset && bundle exec rake db:seed'

alias brew_cask_upgrade='for c in `brew cask list`; do ! brew cask info $c | grep -qF "Not installed" || brew cask install $c; done'

if [ `uname` = Darwin ]; then
    if which gls > /dev/null; then
        alias ll='gls -la --color'
    else
        alias ll='ls -laG'
    fi

    # macvim-kaoriya
    if [ -f ~/Applications/MacVim.app/Contents/MacOS/Vim ]; then
        alias vi='env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOS/Vim "$@"'
        alias vim='env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOS/Vim "$@"'
    fi
else
    alias ll='ls -la --color'
fi

# other setting
#########################################

fpath=(~/.zsh /usr/local/share/zsh-completions /usr/local/share/zsh/site-functions $fpath)

if [ -f /usr/local/share/zsh/site-functions/_aws ]; then
    source /usr/local/share/zsh/site-functions/_aws #なぜかfpathだけだと読まれない
fi

if [ -d ~/.zsh/zsh-notify ]; then
    source ~/.zsh/zsh-notify/notify.plugin.zsh
fi

# if [ `uname` = Darwin ]; then
#     # iterm shell integration
#     test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"
# fi

# direnv
if which direnv > /dev/null; then
    # eval "$(direnv hook $0)"
    eval "$(direnv hook $SHELL)"
fi

# anyenv
if [ -d ~/.anyenv ]; then
    # export PATH="$HOME/.anyenv/bin:$PATH"
    eval "$(anyenv init -)"
fi
