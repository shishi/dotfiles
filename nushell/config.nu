# config.nu
#
# Installed by:
# version = "0.105.1"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu
#
# See `help config nu` for more options
#
# You can remove these comments if you want or leave
# them for future reference.

################################

$env.config.show_banner = false

def ll [...args] {
    if ($args | is-empty) {
        ls -la
    } else {
        ls -la ...$args
    }
}

# weztermとの相性で勝手にスクロールするのをとめる
# NOTE: $env.config 丸ごと再代入だと直前の show_banner 等が消えるので部分代入にする
$env.config.shell_integration = {
    osc133: false  # これが重要
    osc7: true
    osc8: true
    osc9_9: false
    osc633: true
}

$env.CLAUDE_CODE_GIT_BASH_PATH = 'C:\Users\shishi\scoop\shims\git-bash.exe'

alias sudo = gsudo

# git
#########################################
# fish の abbr 相当（nushell に abbr は無いので alias で代替）
alias g = git
alias gs = git status -sb
alias gco = git checkout
alias gci = git commit -m
alias gcia = git commit --amend
alias gl = git log --graph --decorate --name-status
alias gg = git grep
alias gd = git diff
alias ga = git add
alias gb = git branch
alias gP = git push
alias gPf = git push --force-with-lease
alias gPF = git push --force
alias gp = git pull
alias gr = git rebase
alias grc = git rebase --continue
alias gra = git rebase --abort
alias gm = git merge
alias gmc = git merge --continue
alias gma = git merge --abort
alias gcl = git clean --force

# Fuzzy-find and checkout a branch
def gbf [] {
    let branch = (
        git branch --all
        | lines
        | where {|b| ($b !~ 'HEAD') and ($b !~ '\+') }
        | each {|b| $b | str replace -r '^\*' '' | str trim }
        | where {|b| $b | is-not-empty }
        | to text
        | fzf
        | str trim
    )
    if ($branch | is-not-empty) {
        git checkout $branch
    }
}

# git batch delete merged branches (safe)
def gbd [] {
    git branch --merged
    | lines
    | where {|b| ($b !~ '^\*') and ($b !~ 'main') and ($b !~ 'master') }
    | each {|b| git branch -d ($b | str trim) }
}

# git batch delete merged branches (force)
def gbD [] {
    git branch --merged
    | lines
    | where {|b| ($b !~ '^\*') and ($b !~ 'main') and ($b !~ 'master') }
    | each {|b| git branch -D ($b | str trim) }
}

# git worktree list with fzf then cd
def --env gw [] {
    let line = (git-wt | fzf --header-lines=1 | str trim)
    if ($line | is-empty) { return }
    let cols = ($line | split row -r '\s+')
    let dir = (if ($cols.0 == '*') { $cols.1 } else { $cols.0 })
    cd $dir
}

# Create a new git worktree
def --env gwt [branch: string] {
    let base = ($env.PWD | path basename)
    let worktree_path = $"../($base)-($branch)"
    git worktree add -b $branch $worktree_path
    cd $worktree_path
}

# Remove git worktree
def --env gwtd [] {
    let root = (
        git worktree list
        | lines
        | where {|l| $l =~ ($env.PWD | str replace -a '\\' '/') }
        | each {|l| $l | split row -r '\s+' | get 0 }
        | first
    )
    if ($root | is-empty) {
        print "Not in a git worktree"
        return
    }
    let name = ($root | path basename)
    if ($name =~ '--') {
        let branch = ($name | str replace -r '.*--' '')
        print $"Removing worktree: ($root)"
        cd ..
        git worktree remove $root
        git branch -D $branch
    } else {
        print "Cannot remove main worktree"
    }
}