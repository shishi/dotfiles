$Env:Path += ";C:\Users\shishi\scoop\persist\rustup\.cargo\bin"

# Install-Module -Name posh-git -AllowPrerelease -Force
# Install-Module -Name PowerShellGet -Force
# Install-Module -Name PSReadLine

# Dracula Prompt Configuration
Import-Module posh-git
$GitPromptSettings.DefaultPromptPrefix.Text = "$([char]0x2192) " # arrow unicode symbol
$GitPromptSettings.DefaultPromptPrefix.ForegroundColor = [ConsoleColor]::Green
$GitPromptSettings.DefaultPromptPath.ForegroundColor =[ConsoleColor]::Cyan
$GitPromptSettings.DefaultPromptSuffix.Text = "$([char]0x203A) " # chevron unicode symbol
$GitPromptSettings.DefaultPromptSuffix.ForegroundColor = [ConsoleColor]::Magenta

# Dracula Git Status Configuration
$GitPromptSettings.BeforeStatus.ForegroundColor = [ConsoleColor]::Blue
$GitPromptSettings.BranchColor.ForegroundColor = [ConsoleColor]::Blue
$GitPromptSettings.AfterStatus.ForegroundColor = [ConsoleColor]::Blue

Set-PSReadlineKeyHandler -Key ctrl+d -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key Tab -Function Complete

# Dracula readline configuration. Requires version 2.0, if you have 1.2 convert to `Set-PSReadlineOption -TokenType`
Set-PSReadlineOption -Color @{
    "Command" = [ConsoleColor]::Green
    "Parameter" = [ConsoleColor]::Gray
    "Operator" = [ConsoleColor]::Magenta
    "Variable" = [ConsoleColor]::White
    "String" = [ConsoleColor]::Yellow
    "Number" = [ConsoleColor]::Blue
    "Type" = [ConsoleColor]::Cyan
    "Comment" = [ConsoleColor]::DarkCyan
}

$env:CLAUDE_CODE_GIT_BASH_PATH = "C:\Users\shishi\scoop\shims\git-bash.exe"

Set-Alias which Get-Command
Set-Alias sudo gsudo
Set-Alias g git

function ga
{
    git add $args
}
function gs
{
    git status
}

function gd
{
    git diff $args
}

# Keep the tracked Herdr plugin lock in sync after successful mutations.
function herdr
{
    & herdr.exe @args
    $herdrStatus = $LASTEXITCODE

    if (
        $herdrStatus -eq 0 -and
        $args.Count -ge 2 -and
        $args[0] -eq 'plugin' -and
        $args[1] -in @('install', 'uninstall')
    ) {
        & (Join-Path $HOME '.agent-shared/bin/invoke-git-bash-hook.ps1') `
            'bash ~/.agent-shared/bin/herdr-plugins.sh record'
        $herdrStatus = $LASTEXITCODE
    }

    $global:LASTEXITCODE = $herdrStatus
}

# One scoop app per child process, so one failure does not abort the rest.
# See PowerShell/scoop-update-all.ps1 for why.
# Launched as an external 5.1 process rather than dot-called, so the exit code
# propagates the same way it does from nushell.
function scoop-update-all
{
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\Users\shishi\dev\src\github.com\shishi\dotfiles\PowerShell\scoop-update-all.ps1" @args
}

#f45873b3-b655-43a6-b217-97c00aa0db58 PowerToys CommandNotFound module

$isNonInteractiveSession = @(
    [Environment]::GetCommandLineArgs() -match '^-NonI'
).Count -gt 0

if (
    -not $isNonInteractiveSession -and
    -not [Console]::IsInputRedirected -and
    -not [Console]::IsOutputRedirected
) {
    Import-Module -Name Microsoft.WinGet.CommandNotFound
}
#f45873b3-b655-43a6-b217-97c00aa0db58
