set fish_color_command white

# environment variables
#########################################

#set -x LANG ja_JP.UTF-8
set -x PATH ~/.local/bin ~/dev/bin ~/.bun/bin /usr/local/sbin /usr/local/bin $PATH

# set -x LIBRARY_PATH ~/.nix-profile/lib:$LIBRARY_PATH
# set -x LD_LIBRARY_PATH ~/.nix-profile/lib:$LD_LIBRARY_PATH
# set -x C_INCLUDE_PATH ~/.nix-profile/include:$C_INCLUDE_PATH
# set -x CPLUS_INCLUDE_PATH  ~/.nix-profile/include:$CPLUS_INCLUDE_PATH
# set -x PKG_CONFIG_PATH ~/.nix-profile/lib/pkgconfig:$PKG_CONFIG_PATH

set -x GPG_TTY (tty)

set -x EDITOR (status dirname)/nvim-edit
set -x VISUAL (status dirname)/nvim-edit

# if type emacsclient > /dev/null 2>&1
#     set -x EDITOR 'emacsclient -n --alternate-editor vim'
#     set -x VISUAL 'emacsclient -n --alternate-editor vim'
# else
#     set -x EDITOR vim
#     set -x VISUAL vim
# end

# nh(nix-config)の対象 flake。引数なし `nh home switch` など用。非 nix マシンでは無害
set -x NH_FLAKE ~/dev/src/github.com/shishi/nix-config

set -x GO111MODULE on
set -x GOBIN ~/.local/bin
set -x GOPATH ~/dev/

#set -x GHQ_ROOT $dev/src
#set -x HOMEBREW_CASK_OPTS="--appdir=/Applications --caskroom=/usr/local/Caskroom"
#set -x CODECLIMATE_REPO_TOKEN=""
#set -x RIOT_GAMES_API_KEY=""

# if [ (uname -r | sed -n 's/.*\( *Microsoft *\).*/\1/ip') ]
#   set -x BROWSER "/home/shishi/dev/src/github.com/shishi/dotfiles/wsl_browser.sh"
# end

if [ (uname) = Darwin ]
    if type gls &>/dev/null
        set -x PATH /usr/local/opt/coreutils/libexec/gnubin $PATH
        set -x MANPATH /usr/local/opt/coreutils/libexec/gnuman $MANPATH
    end

    if type gfind &>/dev/null
        set -x PATH /usr/local/opt/findutils/libexec/gnubin $PATH
        set -x MANPATH /usr/local/opt/findutils/libexec/gnuman $MANPATH
    end

    if test -f ~/Applications/MacVim.app/Contents/MacOS/Vim
        set -x PATH ~/Applications/MacVim.app/Contents/MacOS $PATH
    end

    # nix-darwin
    if type -d /run/current-system/sw/bin/ &>/dev/null
        set -x PATH /run/current-system/sw/bin/ $PATH
    end

    # jetbrains toolbox
    if type -d "~/Library/Application Support/JetBrains/Toolbox/scripts" &>/dev/null
        set -x PATH "~/Library/Application Support/JetBrains/Toolbox/scripts" $PATH
    end

    # orbstack
    if type orb &>/dev/null
        set -x PATH ~/.orbstack/bin $PATH
        # Added by OrbStack: command-line tools and integration
        # This won't be added again if you remove it.
        source ~/.orbstack/shell/init2.fish 2>/dev/null || :
    end
end

if type less &>/dev/null
    set -x LESS -R
end

set -x LESS '-q --ignore-case --no-init --long-prompt --raw-control-chars'
# set -x LESS '-q -N --ignore-case --no-init --long-prompt --raw-control-chars'
if type lv &>/dev/null
    set -x PAGER 'lv -c'
    # else
    #   set -x PAGER 'less -N --ignore-case -no-init --long-prompt --raw-control-chars'
end

# # mise
# if type mise &>/dev/null
#     if status is-interactive
#         mise activate fish | source
#     else
#         mise activate fish --shims | source
#     end
# # rbenv
# else if type ~/.rbenv/bin/rbenv &>/dev/null
#     set -x PATH ~/.rbenv/bin $PATH
#     status --is-interactive; and rbenv init - --no-rehash fish | source
# end

# # ruby
# if test -d ~/.gem/
#   set -x PATH (eval "ruby -e 'print Gem.user_dir'")/bin $PATH
# end

# rust tools / PATH 契約(nix > cargo > システム既定)
# conf.d(nix.fish → rustup.fish)が cargo > nix の逆順で前方挿入してくるため、
# 最後に無条件で並べ直す。存在しないディレクトリは無害(非 nix / 非 rust マシン)
if type cargo &>/dev/null
    set -x PATH ~/.cargo/bin $PATH
    set -x CARGO_NET_GIT_FETCH_WITH_CLI true
end

# tfenv
if test -f ~/.tfenv/bin/tfenv
    set -x PATH ~/.tfenv/bin $PATH
end

# cask
if test -f ~/.cask/bin/cask
    set -x PATH ~/.cask/bin $PATH
end

# aqua
# if type aqua &>/dev/nul1l
#     set -x AQUA_GLOBAL_CONFIG $AQUA_GLOBAL_CONFIG":"(test -n "$XDG_CONFIG_HOME"; and echo $XDG_CONFIG_HOME; or echo $HOME"/.config")"/aquaproj-aqua/aqua.yaml"
#     set -x PATH (test -n "$AQUA_ROOT_DIR"; and echo $AQUA_ROOT_DIR; or echo (test -n "$XDG_DATA_HOME"; and echo $XDG_DATA_HOME; or echo $HOME"/.local/share")"/aquaproj-aqua")"/bin" $PATH
# end

if type bat &>/dev/null
    set -x BAT_THEME zenburn
    set -x BAT_STYLE auto
end

if type batcat &>/dev/null
    ln -fs (which batcat) ~/.local/bin/bat
end

if type fdfind &>/dev/null
    if test -d ~/.local/bin
        ln -fs (which fdfind) ~/.local/bin/fd
    else
        sudo ln -fs (which fdfind) /usr/local/bin/fd
    end
end

# # vagrant in wsl
# if type vagrant &> /dev/null
#   if string match -q -- '*microsoft*' (uname -a)
#     # set -x PATH "$PATH:/mnt/c/Program Files/Oracle/VirtualBox"
#     set -x VAGRANT_WSL_ENABLE_WINDOWS_ACCESS "1"
#     # set -x VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH "/mnt/c/Users/shishi/"
#     # set -x VAGRANT_HOME "/mnt/c/Users/shishi/.vagrant.d"
#     # set -x VAGRANT_WSL_DISABLE_VAGRANT_HOME "true"
#   end
# end

# use buildkit
if type docker &>/dev/null
    set -x DOCKER_BUILDKIT 1
end

# flyio
if test -d ~/.fly &>/dev/null
    set -x FLYCTL_INSTALL ~/.fly
    set -x PATH $FLYCTL_INSTALL/bin $PATH
end

# console-ninja
if test -d ~/.console-ninja &>/dev/null
    set -x PATH ~/.console-ninja/.bin $PATH
end

# claude code
if test -f ~/.claude/local/claude &>/dev/null
    set -x PATH ~/.claude/local $PATH
end

# git-wt
if type git-wt &>/dev/null
    git wt --init fish | source
end

# settings
#########################################

set fish_greeting

# cmorrell theme
set default_user shishi

# direnv
if type direnv &>/dev/null
    eval (direnv hook fish)
end

# alias
#########################################

switch (uname -a)
    case "*MINGW64*"
        alias ghq 'ghq.exe'
        alias fzf 'fzf.exe'
        alias docker 'docker.exe'
        alias docker-compose 'docker-compose.exe'
        alias docker-machine 'docker-machine.exe'
    case "*Darwin*"
        # alias brew_cask_upgrade 'for c in `brew cask list`; do ! brew cask info $c | grep -qF "Not installed"; or brew cask install $c; done'

        # ll
        if type gls &>/dev/null
            alias ll 'gls -la --color'
        else
            alias ll 'ls -laG'
        end

        # macvim-kaoriya
        if test -f ~/Applications/MacVim.app/Contents/MacOS/Vim
            alias vi 'env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOS/Vim "$@"'
            alias vim 'env LANG=ja_JP.UTF-8 ~/Applications/MacVim.app/Contents/MacOpS/Vim "$@"'
        end

        # homebrew
        if test -f /opt/homebrew/bin/brew
            eval (/opt/homebrew/bin/brew shellenv)
        end

    case "*Linux*"
        alias ll 'ls -la --color'
        # alias open 'xdg-open'
end

# WSL
if test -f '/mnt/c/Users/shishi/AppData/Local/Programs/Microsoft VS Code/bin/code'
    alias code '/mnt/c/Users/shishi/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code'
end

# rust tools
if type eza &>/dev/null
    alias ls eza
    alias ll 'eza -lahg --git --icons --time-style=long-iso'
    alias lt 'eza -T --icons --git-ignore'
end

# if type bat &>/dev/null
#     alias bat 'bat --color always'
# end
#
# if type fzf &>/dev/null
#     alias fzf "fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
# end

# Windows

# windows explorer
if test -e /mnt/c/Windows/explorer.exe &>/dev/null
    alias explorer /mnt/c/Windows/explorer.exe
    alias open /mnt/c/Windows/explorer.exe
end

# wezterm in windows
if test -e /mnt/c/Users/shishi/scoop/shims/wezterm.exe &>/dev/null
    alias wezterm /mnt/c/Users/shishi/scoop/shims/wezterm.exe
    alias wez /mnt/c/Users/shishi/scoop/shims/wezterm.exe
end

# neovide in windows
if test -e /mnt/c/Users/shishi/scoop/apps/neovide/current/neovide.exe &>/dev/null
    alias neovide '/mnt/c/Users/shishi/scoop/apps/neovide/current/neovide.exe --multigrid --wsl'
end

# abbr
#########################################

abbr --add n nvim

# git
abbr --add g git
abbr --add gs 'git status -sb'
abbr --add gco 'git checkout'
abbr --add gci 'git commit -m'
abbr --add gcia 'git commit --amend'
abbr --add gl 'git log --graph --decorate --name-status'
abbr --add gg 'git grep'
abbr --add gd 'git diff'
abbr --add ga 'git add'
abbr --add gb 'git branch'
abbr --add gP 'git push'
abbr --add gPf 'git push --force-with-lease'
abbr --add gPF 'git push --force'
abbr --add gp 'git pull'
abbr --add gr 'git rebase'
abbr --add grc 'git rebase --continue'
abbr --add gra 'git rebase --abort'
abbr --add gm 'git merge'
abbr --add gmc 'git merge --continue'
abbr --add gma 'git merge --abort'
abbr --add gcl 'git clean --force'

# git worktree (git-wt)
# 関数ではなく abbr にすることで、展開後のコマンド行が `git wt ...` になり
# git-wt が提供する補完 (ブランチ名 / worktree 名) がそのまま効く。
if type git-wt &>/dev/null
    abbr --add gwt 'git wt'
    abbr --add gwtd 'git wt -d'
    abbr --add gwtD 'git wt -D'
end

# rails
abbr --add be 'bundle exec'
abbr --add rs 'bundle exec rails server'
abbr --add rc 'bundle exec rails console'
abbr --add rdm 'bundle exec rails db:migrate; and RAILS_ENV=test bundle exec rails db:migrate'
abbr --add rdms 'bundle exec rails db:migrate; and bundle exec rails db:seed'
abbr --add rdmr 'bundle exec rails db:migrate:reset'
abbr --add rdmrs 'bundle exec rails db:migrate:reset; and bundle exec rails db:seed'

# docker
if type docker-compose &>/dev/null
    abbr --add dc docker-compose
    abbr --add dcr 'docker-compose run --rm'
    abbr --add dce 'docker-compose exec'
else
    abbr --add dc 'docker compose'
    abbr --add dcr 'docker compose run --rm'
    abbr --add dce 'docker compose exec'
    abbr --add docker-compose "docker compose"
end

# function
#########################################

function ln_setup
    bash ~/dev/src/github.com/shishi/dotfiles/setup.sh
end

# Keep Codex in-process so every launch inherits its caller's environment.
function codex --wraps codex
    command codex -c 'shell_environment_policy.inherit="all"' $argv
end

# Keep the tracked Herdr plugin lock in sync after successful mutations.
function herdr --wraps herdr
    command herdr $argv
    set -l herdr_status $status

    if test $herdr_status -eq 0; and test (count $argv) -ge 2; and test "$argv[1]" = plugin; and contains -- "$argv[2]" install uninstall
        bash ~/.agent-shared/bin/herdr-plugins.sh record
        return $status
    end

    return $herdr_status
end

# vime skkeleton
if [ "$GUAKE_TAB_UUID" ]
    then
    nvim -c startinsert /tmp/tmp_input
    cat /tmp/tmp_input | xsel --clipboard --input
    rm /tmp/tmp_input
    exit 0
end

function su
    /bin/su --shell=/usr/bin/fish $argv
end

function ibus_restart
    ibus-daemon -drx
end

# ghq
if type ghq &>/dev/null
    function __ghq_cd_repository -d "Change local repository directory"
        ghq list --full-path | fzf | read -l repo_path
        cd $repo_path
    end
    alias ghc __ghq_cd_github

    function __ghq_browse_github -d "Browse remote repository on github"
        ghq list | fzf | read -l repo_path
        set -l repo_name (string split -m1 "/" $repo_path)[2]
        # hub browse $repo_name
        open https://github.com/$repo_name
    end
    alias ghb __ghq_browse_github
end

# fzf git branch
if type fzf &>/dev/null
    function gbf -d "Fuzzy-find and checkout a branch"
        git branch --all | grep -v HEAD | grep -v "+" | awk '{if ($1 == "*") print $2; else print $1}' | string trim | fzf | xargs git checkout
    end
end

# git batch delete branch
function gbd -d "git batch delete branch"
    git branch --merged | grep -vE '^\*|main|master' | xargs git branch -d
end

function gbD -d "git batch delete branch"
    git branch --merged | grep -vE '^\*|main|master' | xargs git branch -D
end

# git worktree: 一覧から fzf で選んで cd (作成・削除は abbr の gwt / gwtd)
if type git-wt &>/dev/null; and type fzf &>/dev/null; and type jq &>/dev/null
    function gw -d "Pick a git worktree with fzf and cd into it"
        # git-wt の表形式は列区切りが空白なので、連続空白を含むパスを復元できない。
        # --json なら空白で壊れない (改行を含むパスは git-wt 側が切り詰めるため非対応)
        # @tsv はパス中の \ やタブをエスケープしてしまうので生の連結で組み立て、
        # 分割回数を 2 に制限してパス側のタブを保つ
        set -l line (git-wt --json \
            | jq -r '.[] | (if .current then "*" else " " end) + "\t" + (.branch // "(detached)") + "\t" + .path' \
            | fzf --delimiter \t)
        test -n "$line"; or return
        set -l dir (string split -m2 -f3 \t -- $line)
        if test -d "$dir"
            cd $dir
        else
            echo "gw: not a directory: $dir" >&2
            return 1
        end
    end
end

function docker_run_with_current_user_and_dir
    docker run -it --rm -v /etc/group:/etc/group:ro -v /etc/passwd:/etc/passwd:ro -u (id -u $USER):(id -g $USER) -v (pwd):/src -w /src -e HOME=/src $argv
end

# Arch
if [ -f /etc/arch-release ]
    function remove_orphan
        if type yay &>/dev/null
            yay -Yc
        else
            pacman -Rns (pacman -Qtdq)
        end
    end
end

# WSL
if [ (uname -r | sed -n 's/.*\( *Microsoft *\).*/\1/ip') ]
    function cdw
        cd /mnt/c/Users/shishi
    end
end

# nix
## ruby (mainly for nix now)
if not type mise >/dev/null 2>&1; and not type ~/.rbenv/bin/rbenv >/dev/null 2>&1
    function add_current_gem_path
        set -x PATH $HOME/.local/share/gem/ruby/(ruby -e "print Gem.ruby_api_version")/bin $PATH
    end
    add_current_gem_path

    # ruby_switch <version>: 現在のシェルの ruby を nixpkgs の任意バージョンへ切り替える
    # 例: ruby_switch 3.3 / ruby_switch 3_4 / ruby_switch ruby_3_3
    function ruby_switch --description "switch ruby in current shell via nixpkgs"
        if test (count $argv) -eq 0
            echo "Usage: ruby_switch <version>  (e.g. ruby_switch 3.3)"
            return 1
        end

        if not type -q nix
            echo "ruby_switch: nix not found (this function requires nix)" >&2
            return 1
        end

        set -l attr $argv[1]
        string match -q 'ruby*' $attr; or set attr ruby_(string replace -a . _ $attr)

        set -l outs (nix build --no-link --print-out-paths nixpkgs#$attr)
        if test $status -ne 0; or test -z "$outs[1]"
            echo "ruby_switch: you do not have version $argv[1] (nixpkgs#$attr not available)" >&2
            set -l sys (uname -m | string replace arm64 aarch64)-(string lower (uname -s))
            set -l avail (nix eval --raw nixpkgs#legacyPackages.$sys --apply 'p: builtins.concatStringsSep " " (builtins.filter (n: builtins.match "ruby(_[0-9]+_[0-9]+)?" n != null) (builtins.attrNames p))' 2>/dev/null)
            test -n "$avail"; and echo "ruby_switch: available: $avail" >&2
            return 1
        end

        # 前回の切り替え分(store の ruby と対応する gem bin)を PATH から掃除して重複を防ぐ
        set -l keep
        for p in $PATH
            if string match -q '/nix/store/*-ruby-*/bin' $p
                continue
            end
            if string match -q "$HOME/.local/share/gem/ruby/*/bin" $p
                continue
            end
            set -a keep $p
        end
        set -x PATH $outs[1]/bin $keep

        functions -q add_current_gem_path; and add_current_gem_path
        echo "switched to "(ruby --version)
    end
end

# source other file
#########################################

# source ~/.config/fish/functions/github_copilot_cli.fish

# ensure
#########################################
if type nix &>/dev/null
    set -x PATH /nix/var/nix/profiles/default/bin ~/.nix-profile/bin $PATH
end
