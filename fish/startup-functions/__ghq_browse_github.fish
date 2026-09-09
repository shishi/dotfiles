function __ghq_browse_github -d "Browse remote repository on github"
    ghq list | fzf | read -l repo_path
    set -l repo_name (string split -m1 "/" $repo_path)[2]
    # hub browse $repo_name
    open https://github.com/$repo_name
end
