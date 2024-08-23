#!/bin/bash

if [ -d /.jbdevcontainer ]; then
    XDG_CONFIG_HOME=/.jbdevcontainer/config
elif [ -z $XDG_CONFIG_HOME ]; then
    XDG_CONFIG_HOME=$HOME/.config
    mkdir -p ~/.config
fi

DOTDIR=$(realpath $(dirname "$0"))
#$EMACSDIR=~/dev/src/github.com/shishi/emacs

if [ "$REMOTE_CONTAINERS" != true ]; then
    if [ -L ${XDG_CONFIG_HOME}/wezterm ]; then
        rm ${XDG_CONFIG_HOME}/wezterm
        ln -sf ${DOTDIR}/wezterm ${XDG_CONFIG_HOME}/wezterm
    elif [ -d ${XDG_CONFIG_HOME}/wezterm ]; then
        rm -fr ${XDG_CONFIG_HOME}/wezterm
        ln -sf ${DOTDIR}/wezterm ${XDG_CONFIG_HOME}/wezterm
    else
        ln -sf ${DOTDIR}/wezterm ${XDG_CONFIG_HOME}/wezterm
    fi

    if [ -L ~/.emacs.d ]; then
        rm ~/.emacs.d
        ln -sf $(dirname ${DOTDIR})/emacs ~/.emacs.d
    elif [ -d ~/.emacs.d ]; then
        git -C $(dirname ${DOTDIR}) clone git@github.com:shishi/emacs.git
        rm -fr ~/.emacs.d
        ln -sf $(dirname ${DOTDIR})/emacs ~/.emacs.d
    else
        git -C $(dirname ${DOTDIR}) clone git@github.com:shishi/emacs.git
        ln -sf $(dirname ${DOTDIR})/emacs ~/.emacs.d
    fi
fi

if [ -L ${XDG_CONFIG_HOME}/fish ]; then
    rm ${XDG_CONFIG_HOME}/fish
    ln -sf ${DOTDIR}/fish ${XDG_CONFIG_HOME}/fish
elif [ -d ${XDG_CONFIG_HOME}/fish ]; then
    rm -fr ${XDG_CONFIG_HOME}/fish
    ln -sf ${DOTDIR}/fish ${XDG_CONFIG_HOME}/fish
else
    ln -sf ${DOTDIR}/fish ${XDG_CONFIG_HOME}/fish
fi

if [ -L ${XDG_CONFIG_HOME}/nvim ]; then
    rm ${XDG_CONFIG_HOME}/nvim
    ln -sf ${DOTDIR}/nvim ${XDG_CONFIG_HOME}/nvim
elif [ -d ${XDG_CONFIG_HOME}/nvim ]; then
    rm -fr ${XDG_CONFIG_HOME}/nvim
    ln -sf ${DOTDIR}/nvim ${XDG_CONFIG_HOME}/nvim
else
    ln -sf ${DOTDIR}/nvim ${XDG_CONFIG_HOME}/nvim
fi

if [ -L ${XDG_CONFIG_HOME}/helix ]; then
    rm ${XDG_CONFIG_HOME}/helix
    ln -sf ${DOTDIR}/helix ${XDG_CONFIG_HOME}/helix
elif [ -d ${XDG_CONFIG_HOME}/helix ]; then
    rm -fr ${XDG_CONFIG_HOME}/helix
    ln -sf ${DOTDIR}/helix ${XDG_CONFIG_HOME}/helix
else
    ln -sf ${DOTDIR}/helix ${XDG_CONFIG_HOME}/helix
fi

if [ `uname` = Darwin ]; then
    ln -sf ${DOTDIR}/.gitconfig.mac ~/.gitconfig
    ln -sf ${DOTDIR}/Brewfile ~/Brewfile
elif [ `uname` = Linux ]; then
    ln -sf ${DOTDIR}/.gitconfig.linux ~/.gitconfig
    #    ln -sf ${DOTDIR}/terminator ${XDG_CONFIG_HOME}/terminator
    #    ln -sf ${DOTDIR}/.xprofile ~/.xprofile
    #    ln -sf ${DOTDIR}/.xbindkeysrc ~/.xbindkeysrc
    #    ln -sf ${DOTDIR}/.imwheelrc ~/.imwheelrc
    #    ln -sf ${DOTDIR}/imwheel.desktop ${XDG_CONFIG_HOME}/autostart/imwheel.desktop
    #    ln -sf ${DOTDIR}/fonts.conf ${XDG_CONFIG_HOME}/fontconfig/fonts.conf
    #    fc-cache -fv
elif [ `uname` = MINGW64_NT-10.0 ]; then
    ln -sf ${DOTDIR}/.gitconfig.win ~/.gitconfig
fi

ln -sf ${DOTDIR}/.gitignore.global ~/.gitignore

ln -sf ${DOTDIR}/.ideavimrc ~/.ideavimrc
ln -sf ${DOTDIR}/.vimrc ~/.vimrc
ln -sf ${DOTDIR}/.gvimrc ~/.gvimrc
#ln -sf ${DOTDIR}/.vim ~/.vim

ln -sf ${DOTDIR}/.gemrc ~/.gemrc
ln -sf ${DOTDIR}/.rspec ~/.rspec
ln -sf ${DOTDIR}/.pryrc ~/.pryrc

ln -sf ${DOTDIR}/.npmrc ~/.npmrc

ln -sf ${DOTDIR}/.bashrc ~/.bashrc

# ln -s ${DOTDIR}/.zsh ~/.zsh
# ln -s ${DOTDIR}/.zshenv ~/.zshenv
# ln -s ${DOTDIR}/.zshrc ~/.zshrc

echo "please reload shell"
