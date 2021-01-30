#!/bin/sh

DOTDIR=$(realpath $(dirname "$0"))
#$EMACSDIR=~/dev/src/github.com/shishi/emacs

mkdir -p ~/.config/fish
if [ -L ~/.config/fish ]; then
    rm ~/.config/fish
    ln -sf $DOTDIR/fish ~/.config/fish
elif [ -d ~/.config/fish ]; then
    rm -fr ~/.config/fish
    ln -sf $DOTDIR/fish ~/.config/fish
else
    ln -sf $DOTDIR/fish ~/.config/fish
fi

if [ -L ~/.emacs.d ]; then
    rm ~/.emacs.d
    ln -sf $(dirname $DOTDIR)/emacs ~/.emacs.d
elif [ -d ~/.emacs.d ]; then
    git -C $(dirname $DOTDIR) clone git@github.com:shishi/emacs.git
    rm -fr ~/.emacs.d
    ln -sf $(dirname $DOTDIR)/emacs ~/.emacs.d
else
    git -C $(dirname $DOTDIR) clone git@github.com:shishi/emacs.git
    ln -sf $(dirname $DOTDIR)/emacs ~/.emacs.d
fi

ln -sf $DOTDIR/.gitignore ~/.gitignore

ln -sf $DOTDIR/.vimrc ~/.vimrc
ln -sf $DOTDIR/.gvimrc ~/.gvimrc
#ln -sf $DOTDIR/.vim ~/.vim

ln -sf $DOTDIR/.gemrc ~/.gemrc
ln -sf $DOTDIR/.rspec ~/.rspec
ln -sf $DOTDIR/.pryrc ~/.pryrc

# ln -s $DOTDIR/.zsh ~/.zsh
# ln -s $DOTDIR/.zshenv ~/.zshenv
# ln -s $DOTDIR/.zshrc ~/.zshrc

if [ `uname` = Darwin ]; then
    ln -sf $DOTDIR/.gitconfig.mac ~/.gitconfig
    ln -sf $DOTDIR/Brewfile ~/Brewfile
elif [ `uname` = Linux ]; then
    ln -sf $DOTDIR/.gitconfig.linux ~/.gitconfig
#    ln -sf $DOTDIR/terminator ~/.config/terminator
#    ln -sf $DOTDIR/.xprofile ~/.xprofile
#    ln -sf $DOTDIR/.xbindkeysrc ~/.xbindkeysrc
#    ln -sf $DOTDIR/.imwheelrc ~/.imwheelrc
#    ln -sf $DOTDIR/imwheel.desktop ~/.config/autostart/imwheel.desktop
#    ln -sf $DOTDIR/fonts.conf ~/.config/fontconfig/fonts.conf
#    fc-cache -fv
elif [ `uname` = MINGW64_NT-10.0 ]; then
    ln -sf $DOTDIR/.gitconfig.win ~/.gitconfig
fi

echo "please reload shell"
