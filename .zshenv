#export LANG=ja_JP.UTF-8

#zmodload zsh/zprof && zprof
export PATH=~/bin:/usr/local/sbin:/usr/local/bin:$PATH

#export HOMEBREW_CASK_OPTS="--appdir=/Applications --caskroom=/usr/local/Caskroom"
#export CODECLIMATE_REPO_TOKEN=""
#export RIOT_GAMES_API_KEY=""

if [ `uname` = Darwin ]; then
    if which gls > /dev/null; then
        PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
        MANPATH="/usr/local/opt/coreutils/libexec/gnuman:$MANPATH"
    fi

    if which gfind > /dev/null; then
        PATH="/usr/local/opt/findutils/libexec/gnubin:$PATH"
        MANPATH="/usr/local/opt/findutils/libexec/gnuman:$MANPATH"
    fi

    if [ -f ~/Applications/MacVim.app/Contents/MacOS/Vim ]; then
        PATH="~/Applications/MacVim.app/Contents/MacOS:$PATH"
    fi
fi

if which emacsclient > /dev/null; then
    export EDITOR='emacsclient -n --alternate-editor vim'
else
    export EDITOR='vim'
fi

if which lv > /dev/null; then
    export PAGER='lv -c'
fi

# anyenv
if [ -d $HOME/.anyenv ]; then
    export PATH="$HOME/.anyenv/bin:$PATH"
fi
