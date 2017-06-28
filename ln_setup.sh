#!/bin/sh

DOTDIR=~/Dropbox/dev/src/github.com/shishi/dotfiles
EMACSDIR=~/Dropbox/dev/src/github.com/shishi/emacs

ln -s $DOTDIR/fish ~/.config/fish
ln -s $EMACSDIR ~/.emacs.d

if [ `uname` = Darwin ]; then
    ln -s $DOTDIR/.gitconfig.mac ~/.gitconfig
    ln -s $DOTDIR/Brewfile ~/Brewfile
elif [ `uname` = Linux ]; then
    ln -s $DOTDIR/.gitconfig.linux ~/.gitconfig
fi

ln -s $DOTDIR/.gitignore ~/.gitignore

ln -s $DOTDIR/.vimrc ~/.vimrc
ln -s $DOTDIR/.gvimrc ~/.gvimrc

ln -s $DOTDIR/.gemrc ~/.gemrc
ln -s $DOTDIR/.rspec ~/.rspec
ln -s $DOTDIR/.pryrc ~/.pryrc

ln -s $DOTDIR/.zsh ~/.zsh
ln -s $DOTDIR/.zshenv ~/.zshenv
ln -s $DOTDIR/.zshrc ~/.zshrc

echo "reload shell and fisher"
