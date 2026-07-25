$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot '..\hooks.json'
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$failures = @()

foreach ($event in $config.hooks.PSObject.Properties) {
    foreach ($group in $event.Value) {
        foreach ($handler in $group.hooks) {
            $label = "$($event.Name): $($handler.command)"
            if (-not $handler.commandWindows) {
                $failures += "$label has no commandWindows override"
                continue
            }
            if ($handler.commandWindows -notmatch 'scoop[/\\]apps[/\\]git[/\\]current[/\\]bin[/\\]bash\.exe') {
                $failures += "$label does not select Git Bash on Windows"
            }
            if ($handler.commandWindows -notmatch '(?:^|\s)-lc(?:\s|$)') {
                $failures += "$label does not start a login shell"
            }
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'ok: every Codex hook uses Git Bash login shell on Windows'
