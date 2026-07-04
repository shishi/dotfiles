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