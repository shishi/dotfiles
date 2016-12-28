export PATH=~/bin:/usr/local/sbin:/usr/local/bin:$PATH

#export HOMEBREW_CASK_OPTS="--appdir=/Applications --caskroom=/usr/local/Caskroom"
export CODECLIMATE_REPO_TOKEN="81eb5c871ceafdf53bb05f2311220c146d7ffdb7d0e1854583902ed979fc8620"
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
if [ -d ~/.anyenv ]; then
    export PATH="$HOME/.anyenv/bin:$PATH"
fi
