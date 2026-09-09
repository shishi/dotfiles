function gbD -d "git batch delete branch"
    git branch --merged | grep -vE '^\*|main|master' | xargs git branch -D
end
