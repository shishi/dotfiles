function gbf -d "Fuzzy-find and checkout a branch"
    git branch --all | grep -v HEAD | grep -v "+" | awk '{if ($1 == "*") print $2; else print $1}' | string trim | fzf | xargs git checkout
end
