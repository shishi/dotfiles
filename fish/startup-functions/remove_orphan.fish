function remove_orphan
    if type yay &>/dev/null
        yay -Yc
    else
        pacman -Rns (pacman -Qtdq)
    end
end
