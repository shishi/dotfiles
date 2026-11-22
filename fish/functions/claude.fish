# Claude Code は autoMode を repo 内の .claude/settings.json・settings.local.json から読まない。
# repo 固有の autoMode は Git 管理外の .claude/automode.local.json に置き、--settings で渡す。
# worktree からも main checkout の同じファイルを使うため、git の共通ディレクトリから探す。
function claude --description 'Claude Code に repo の .claude/automode.local.json を渡して起動する'
    set -l common (command git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if test -n "$common"
        set -l file (path dirname -- $common)/.claude/automode.local.json
        if test -f $file
            command claude --settings $file $argv
            return
        end
    end
    command claude $argv
end
