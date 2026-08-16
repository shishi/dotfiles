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
            # compact 系 hook は Codex 専用の state を使う。既定のままだと
            # Claude の $HOME/.claude/compact-state を読んで状態が混線する。
            if ($handler.command -match 'compact') {
                foreach ($form in @($handler.command, $handler.commandWindows)) {
                    if ($form -notmatch 'COMPACT_STATE_DIR=\$HOME/\.codex/compact-state') {
                        $failures += "$label does not isolate COMPACT_STATE_DIR"
                    }
                }
            }
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'ok: every Codex hook invokes Git Bash non-login on Windows and isolates compact state'
