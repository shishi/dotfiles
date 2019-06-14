#!/bin/sh

DOTDIR=$(dirname "$0")
EMACSDIR=~/dev/src/github.com/shishi/emacs

if [ -L ~/.config/fish ]; then
    rm ~/.config/fish
    ln -s $DOTDIR/fish ~/.config/fish
elif [ -d ~/.config/fish ]
    rm -fr ~/.config/fish
    ln -s $DOTDIR/fish ~/.config/fish
else
    ln -s $DOTDIR/fish ~/.config/fish
fi

if [ -L ~/.emacs.d ]; then
    rm ~/.emacs.d
    ln -s $EMACSDIR ~/.emacs.d
elif [ -d ~/.emacs.d ]
    rm -fr ~/.emacs.d
    ln -s $EMACSDIR ~/.emacs.d
else
    ln -s $EMACSDIR ~/.emacs.d
fi

ln -s $DOTDIR/.gitignore ~/.gitignore

ln -s $DOTDIR/.vimrc ~/.vimrc
ln -s $DOTDIR/.gvimrc ~/.gvimrc
ln -s $DOTDIR/.vim ~/.vim

ln -s $DOTDIR/.gemrc ~/.gemrc
ln -s $DOTDIR/.rspec ~/.rspec
ln -s $DOTDIR/.pryrc ~/.pryrc

# ln -s $DOTDIR/.zsh ~/.zsh
# ln -s $DOTDIR/.zshenv ~/.zshenv
# ln -s $DOTDIR/.zshrc ~/.zshrc

if [ `uname` = Darwin ]; then
    ln -s $DOTDIR/.gitconfig.mac ~/.gitconfig
    ln -s $DOTDIR/Brewfile ~/Brewfile
elif [ `uname` = Linux ]; then
    ln -s $DOTDIR/.gitconfig.linux ~/.gitconfig
#    ln -s $DOTDIR/terminator ~/.config/terminator
#    ln -s $DOTDIR/.xprofile ~/.xprofile
#    ln -s $DOTDIR/.xbindkeysrc ~/.xbindkeysrc
#    ln -s $DOTDIR/.imwheelrc ~/.imwheelrc
#    ln -s $DOTDIR/imwheel.desktop ~/.config/autostart/imwheel.desktop
#    ln -s $DOTDIR/fonts.conf ~/.config/fontconfig/fonts.conf
#    fc-cache -fv
elif [ `uname` = MINGW64_NT-10.0 ]; then
    ln -s $DOTDIR/.gitconfig.win ~/.gitconfig
fi

echo "please reload shell"
