$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$profile = Join-Path $repoRoot 'PowerShell/Microsoft.PowerShell_profile.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "powershell-profile-$([guid]::NewGuid().ToString('N'))"
$moduleRoot = Join-Path $fixtureRoot 'Microsoft.WinGet.CommandNotFound'
$modulePath = Join-Path $moduleRoot 'Microsoft.WinGet.CommandNotFound.psm1'

try {
    New-Item -ItemType Directory -Path $moduleRoot | Out-Null
    [IO.File]::WriteAllText(
        $modulePath,
        '$global:CommandNotFoundProbeImported = $true',
        [Text.UTF8Encoding]::new($false)
    )

    $profileLiteral = $profile.Replace("'", "''")
    $fixtureLiteral = $fixtureRoot.Replace("'", "''")
    $childScript = @"
`$env:PSModulePath = '$fixtureLiteral' + [IO.Path]::PathSeparator + `$env:PSModulePath
`$global:CommandNotFoundProbeImported = `$false
. '$profileLiteral'
if (`$global:CommandNotFoundProbeImported) { exit 23 }
exit 0
"@

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [Environment]::ProcessPath
    $startInfo.UseShellExecute = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-NonInteractive')
    $startInfo.ArgumentList.Add('-Command')
    $startInfo.ArgumentList.Add($childScript)

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'Failed to start the non-interactive PowerShell probe'
        }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Non-interactive profile load imported the interactive-only CommandNotFound module (exit=$($process.ExitCode))"
        }
    }
    finally {
        $process.Dispose()
    }
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Output 'PowerShell profile tests passed'
