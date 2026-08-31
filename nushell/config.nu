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

# Keep the tracked Herdr plugin lock in sync after successful mutations.
def --wrapped herdr [...args] {
    ^herdr ...$args
    let herdr_status = $env.LAST_EXIT_CODE

    if (
        $herdr_status == 0 and
        ($args | length) >= 2 and
        $args.0 == 'plugin' and
        $args.1 in ['install' 'uninstall']
    ) {
        let recorder = 'bash ~/.agent-shared/bin/herdr-plugins.sh record'
        let windows_runner = ($nu.home-path | path join '.agent-shared/bin/invoke-git-bash-hook.ps1')
        if ((which powershell.exe | is-not-empty) and ($windows_runner | path exists)) {
            ^powershell.exe -NoProfile -ExecutionPolicy Bypass -File $windows_runner $recorder
        } else {
            ^bash ~/.agent-shared/bin/herdr-plugins.sh record
        }
    }
}

# scoop は 1 件の失敗で abort（= exit）して残り全部を巻き添えにするので、
# アプリごとに子プロセスへ分けて更新する。nu から呼ぶ分には pwsh 自身も同じ
# ループで更新できる（pwsh セッションが動いていないため）。pwsh から呼ぶと
# pwsh だけスキップされる。理由の詳細は PowerShell/scoop-update-all.ps1 のコメント。
#
# NOTE: rest パラメータ（...args）にすると nu が `-Skip` を自分のフラグとして
# 食うため、`-- -Skip makemkv` と書かされる。nu 側のフラグとして受けて詰め替える。
def scoop-update-all [
    --skip: string = ""   # カンマ区切りで除外するアプリ
] {
    let ps1 = 'C:\Users\shishi\dev\src\github.com\shishi\dotfiles\PowerShell\scoop-update-all.ps1'
    mut args = ['-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' $ps1]
    if ($skip | is-not-empty) { $args = ($args | append ['-Skip' $skip]) }
    ^powershell.exe ...$args
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
