$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot '..\hooks.json'
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$failures = @()
$registered = @()
$launcherPrefix = "& (Join-Path `$HOME '.agents/bin/invoke-git-bash-hook.ps1') '"
$launcherPath = Join-Path $PSScriptRoot '..\..\agents\bin\invoke-git-bash-hook.ps1'
$herdrCommand = 'bash ~/.codex/herdr-agent-state.sh session'
$herdrWindowsCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path `$HOME '.codex/herdr-agent-state.ps1') session"

if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    $failures += 'portable Git Bash launcher is missing'
}

$preToolUse = @($config.hooks.PreToolUse)
if ($preToolUse.Count -ne 1 -or $preToolUse[0].matcher -ne 'Bash') {
    $failures += 'existing PreToolUse Bash hook is not preserved'
} elseif ($preToolUse[0].hooks[0].command -ne 'bash ~/.agents/hooks/git-push-guard.sh') {
    $failures += 'PreToolUse must invoke the shared git push guard'
} elseif ($preToolUse[0].hooks[0].commandWindows -ne "${launcherPrefix}~/.agents/hooks/git-push-guard.sh'") {
    $failures += 'PreToolUse Windows command must invoke the shared git push guard'
}

$userPromptSubmit = @($config.hooks.UserPromptSubmit)
if ($userPromptSubmit.Count -ne 1 -or $userPromptSubmit[0].hooks[0].command -ne 'bash ~/.agents/hooks/git-push-guard.sh --record-approval') {
    $failures += 'UserPromptSubmit must record explicit push authorization with the shared guard'
} elseif ($userPromptSubmit[0].hooks[0].commandWindows -ne "${launcherPrefix}~/.agents/hooks/git-push-guard.sh --record-approval'") {
    $failures += 'UserPromptSubmit Windows command must record authorization with the shared guard'
}

$memorySessionStart = @($config.hooks.SessionStart | Where-Object {
    $_.matcher -eq 'startup|resume|clear|compact'
})
if ($memorySessionStart.Count -ne 1) {
    $failures += 'SessionStart must have exactly one memory hook group'
} else {
    $sessionStartGroup = $memorySessionStart[0]
    $sources = @($sessionStartGroup.matcher -split '\|')
    $expectedSources = @('startup', 'resume', 'clear', 'compact')
    if ((Compare-Object $expectedSources $sources).Count -ne 0) {
        $failures += 'SessionStart matcher must cover startup, resume, clear, and compact exactly'
    }

    $sessionHandlers = @($sessionStartGroup.hooks)
    if ($sessionHandlers.Count -ne 1) {
        $failures += 'SessionStart must have exactly one command handler'
    } else {
        $sessionHandler = $sessionHandlers[0]
        if ($sessionHandler.command -ne 'bash ~/.agents/hooks/inject-memory.sh ~/.codex/memory') {
            $failures += 'SessionStart must use the shared memory injector with ~/.codex/memory'
        }
        if ($sessionHandler.commandWindows -ne "${launcherPrefix}~/.agents/hooks/inject-memory.sh ~/.codex/memory'") {
            $failures += 'SessionStart Windows command must invoke the shared injector through explicit Git Bash'
        }
        $contextLimit = $sessionHandler.additionalContextLimit
        if ($null -eq $contextLimit -or $contextLimit -le 0 -or $contextLimit % 1 -ne 0) {
            $failures += 'SessionStart must set a positive integer additionalContextLimit'
        }
        # additionalContextLimit is an approximate token threshold, not a
        # character count. 10,000 keeps a positive cap above the 2,500 default;
        # the consolidation workflow separately audits the effective payload.
        if ($contextLimit -ne 10000) {
            $failures += 'SessionStart additionalContextLimit must be exactly 10000'
        }
    }
}

foreach ($event in $config.hooks.PSObject.Properties) {
    foreach ($group in $event.Value) {
        foreach ($handler in $group.hooks) {
            $label = "$($event.Name): $($handler.command)"
            if (-not $handler.commandWindows) {
                $failures += "$label has no commandWindows override"
                continue
            }
            if ($handler.command -eq $herdrCommand -and $handler.commandWindows -ne $herdrWindowsCommand) {
                $failures += "$label does not use the generated Windows Herdr adapter"
            } elseif ($handler.command -ne $herdrCommand -and -not $handler.commandWindows.StartsWith($launcherPrefix, [StringComparison]::Ordinal)) {
                $failures += "$label does not use the portable Git Bash launcher"
            }
            if ($handler.commandWindows -match '(?i)C:/Users/|C:\\Users\\|/Users/|/home/') {
                $failures += "$label contains an absolute home path"
            }
            # 参照先が実在すること。ハンドラとスクリプトは別ファイルなので、
            # 片方だけ消しても Codex が起動して hook を撃つまで判らない。
            foreach ($ref in [regex]::Matches($handler.command, '~/\.codex/hooks/([A-Za-z0-9._-]+)')) {
                $script = Join-Path $PSScriptRoot $ref.Groups[1].Value
                if (-not (Test-Path -LiteralPath $script)) {
                    $failures += "$label references a script that is not in this directory"
                }
                $registered += $ref.Groups[1].Value
            }
        }
    }
}

# 逆向き: hooks.json から到達できない実装が残っていないこと。テストは除く。
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File) {
    if ($file.Name -like '*.test.*') { continue }
    if ($registered -notcontains $file.Name) {
        $failures += "$($file.Name) is not registered in hooks.json"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'ok: Codex hooks use their platform adapter, and hooks.json and hooks/ agree on what exists'
