# env.nu
#
# Installed by:
# version = "0.105.1"
#
# Previously, environment variables were typically configured in `env.nu`.
# In general, most configuration can and should be performed in `config.nu`
# or one of the autoload directories.
#
# This file is generated for backwards compatibility for now.
# It is loaded before config.nu and login.nu
#
# See https://www.nushell.sh/book/configuration.html
#
# Also see `help config env` for more options.
#
# You can remove these comments if you want or leave
# them for future reference.

########################################

$env.PROMPT_COMMAND = {|| 
    let git_branch = (
        do --ignore-errors { git symbolic-ref --short HEAD } 
        | complete 
        | get stdout 
        | str trim
    )
    
    # 現在のディレクトリ（相対パス表示）
    let path = match (do --ignore-errors { $env.PWD | path relative-to $nu.home-path }) {
        null => $env.PWD
        '' => '~ '
        $relative_pwd => ([~ $relative_pwd] | path join)
    }
    
    if ($git_branch == "") {
        # Gitリポジトリでない場合
        $"(ansi green_bold)($path)"
    } else {
        # Gitのステータスをチェック
        let is_dirty = (
            do --ignore-errors { git status --porcelain } 
            | complete 
            | get stdout 
            | str trim
            | is-not-empty
        )
        
        # dirtyな場合は赤、cleanな場合は黄色
        let branch_color = if $is_dirty { ansi red_bold } else { ansi yellow }
        
        $"(ansi green_bold)($path) ($branch_color)[($git_branch)](ansi reset) "
    }
}

# 右プロンプトは空にする（デフォルトの時刻表示を消す場合）
# $env.PROMPT_COMMAND_RIGHT = {|| "" }