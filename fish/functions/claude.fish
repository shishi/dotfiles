# Claude Code は autoMode を repo 内の .claude/settings.json・settings.local.json から読まない。
# repo 固有の autoMode は Git 管理外の .claude/automode.local.json に置き、--settings で渡す。
# worktree からも main checkout の同じファイルを使うため、git の共通ディレクトリから探す。
function claude --description 'Claude Code に repo の .claude/automode.local.json を渡して起動する'
    set -l settings_args
    set -l common (command git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if test -n "$common"
        set -l file (path dirname -- $common)/.claude/automode.local.json
        if test -f $file
            set settings_args --settings $file
        end
    end
    if not isatty stdin; or not isatty stdout; or test (uname -s) != Linux
        command claude $settings_args $argv
        return
    end
    switch "$argv[1]"
        case agents attach auth auto-mode doctor gateway import install logs mcp plugin plugins purge respawn rm setup-token stop kill ultrareview update upgrade help
            command claude $settings_args $argv
            return
    end
    for arg in $argv
        switch $arg
            case --
                break
            case -p --print -h --help -v --version --bare --safe-mode --bg --background
                command claude $settings_args $argv
                return
        end
    end
    bash "$HOME/.agent-shared/bin/kata-claude.sh" $settings_args $argv
end
