$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot '..\hooks.json'
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$failures = @()
$registered = @()

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
