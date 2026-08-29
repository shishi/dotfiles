$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot '..\hooks.json'
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$failures = @()
$registered = @()

$preToolUse = @($config.hooks.PreToolUse)
if ($preToolUse.Count -ne 1 -or $preToolUse[0].matcher -ne 'Bash') {
    $failures += 'existing PreToolUse Bash hook is not preserved'
} elseif ($preToolUse[0].hooks[0].command -ne 'bash ~/.agents/hooks/git-push-guard.sh') {
    $failures += 'PreToolUse must invoke the shared git push guard'
} elseif ($preToolUse[0].hooks[0].commandWindows -notmatch "-c\s+'~/.agents/hooks/git-push-guard\.sh'$" ) {
    $failures += 'PreToolUse Windows command must invoke the shared git push guard'
}

$userPromptSubmit = @($config.hooks.UserPromptSubmit)
if ($userPromptSubmit.Count -ne 1 -or $userPromptSubmit[0].hooks[0].command -ne 'bash ~/.agents/hooks/git-push-guard.sh --record-approval') {
    $failures += 'UserPromptSubmit must record explicit push authorization with the shared guard'
} elseif ($userPromptSubmit[0].hooks[0].commandWindows -notmatch "-c\s+'~/.agents/hooks/git-push-guard\.sh --record-approval'$" ) {
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
        if ($sessionHandler.commandWindows -notmatch "bash\.exe'.*-c\s+'~/.agents/hooks/inject-memory\.sh ~/.codex/memory'") {
            $failures += 'SessionStart Windows command must invoke the shared injector through explicit Git Bash'
        }
        $contextLimit = $sessionHandler.additionalContextLimit
        if ($null -eq $contextLimit -or $contextLimit -le 0 -or $contextLimit % 1 -ne 0) {
            $failures += 'SessionStart must set a positive integer additionalContextLimit'
        }
        # The measured injection is 8,563 characters. 10,000 keeps the current
        # payload in context with bounded headroom above the 2,500 default.
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
            # bash.exe を明示的に指すこと。裸の `bash` は WSL launcher
            # (System32\bash.exe) に解決され、hook が誤った環境で走る。
            # パスの由来 (scoop / Git for Windows 標準) は問わない。
            if ($handler.commandWindows -notmatch 'bash\.exe') {
                $failures += "$label does not invoke bash.exe explicitly"
            }
            if ($handler.commandWindows -match 'System32[/\\]bash\.exe') {
                $failures += "$label resolves to the WSL launcher"
            }
            if ($handler.commandWindows -notmatch '^\s*&\s+') {
                $failures += "$label does not use the PowerShell call operator"
            }
            # login shell は使わない。起動ファイル由来の出力・遅延・環境変異を
            # policy hook に持ち込まないため。依存 (jq/python3/git) は -c でも
            # PATH 上にあることを実測済み。
            if ($handler.commandWindows -match '(?:^|\s)-[A-Za-z]*l[A-Za-z]*c(?:\s|$)') {
                $failures += "$label starts a login shell"
            }
            if ($handler.commandWindows -notmatch '(?:^|\s)-c(?:\s|$)') {
                $failures += "$label does not pass -c"
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

Write-Output 'ok: every Codex hook invokes Git Bash non-login on Windows, and hooks.json and hooks/ agree on what exists'
