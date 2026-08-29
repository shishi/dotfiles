$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $repoRoot 'agents/bin/invoke-git-bash-hook.ps1'

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Expected,

        [Parameter(Mandatory)]
        $Actual,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Expected -cne $Actual) {
        throw "$Message`nExpected: <$Expected>`nActual:   <$Actual>"
    }
}

function Invoke-Launcher {
    param(
        [Parameter(Mandatory)]
        [string] $Command,

        [string] $StandardInput = '',

        [hashtable] $Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [Environment]::ProcessPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-NonInteractive')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($launcher)
    $startInfo.ArgumentList.Add($Command)
    foreach ($name in $Environment.Keys) {
        $startInfo.Environment[$name] = [string] $Environment[$name]
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw 'Failed to start fresh pwsh process'
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($StandardInput)
        $process.StandardInput.Close()
        $process.WaitForExit()

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdoutTask.GetAwaiter().GetResult()
            Stderr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Launcher is missing: $launcher"
}

$payload = '{"hook":"probe"}'
$forwardResult = Invoke-Launcher -Command 'IFS= read -r payload; printf %s "$payload"' -StandardInput $payload
Assert-Equal -Expected 0 -Actual $forwardResult.ExitCode -Message 'stdin forwarding command should succeed'
Assert-Equal -Expected $payload -Actual $forwardResult.Stdout -Message 'stdin should be forwarded to Bash stdout exactly'
Assert-Equal -Expected '' -Actual $forwardResult.Stderr -Message 'successful invocation should not write stderr'

$tildeFixtureName = ".invoke-git-bash-hook-$([guid]::NewGuid().ToString('N'))"
$tildeFixtureRoot = Join-Path $HOME $tildeFixtureName
$tildeProbe = Join-Path $tildeFixtureRoot 'probe.sh'
try {
    New-Item -ItemType Directory -Path $tildeFixtureRoot | Out-Null
    [IO.File]::WriteAllText(
        $tildeProbe,
        "#!/usr/bin/env bash`nprintf %s tilde-path-probe`n",
        [Text.UTF8Encoding]::new($false)
    )

    $tildeResult = Invoke-Launcher -Command "~/$tildeFixtureName/probe.sh"
    Assert-Equal -Expected 0 -Actual $tildeResult.ExitCode -Message 'tilde-prefixed path command should succeed'
    Assert-Equal -Expected 'tilde-path-probe' -Actual $tildeResult.Stdout -Message 'Bash should expand the tilde-prefixed command path'
    Assert-Equal -Expected '' -Actual $tildeResult.Stderr -Message 'tilde-prefixed path command should not write stderr'
}
finally {
    if (Test-Path -LiteralPath $tildeFixtureRoot) {
        Remove-Item -LiteralPath $tildeFixtureRoot -Recurse -Force
    }
}

$stderrMarker = 'invoke-git-bash-hook-stderr-probe'
$stderrResult = Invoke-Launcher -Command "printf '%s\n' '$stderrMarker' >&2"
Assert-Equal -Expected 0 -Actual $stderrResult.ExitCode -Message 'stderr forwarding command should succeed'
Assert-Equal -Expected '' -Actual $stderrResult.Stdout -Message 'stderr forwarding should not write stdout'
Assert-Equal -Expected "$stderrMarker`n" -Actual $stderrResult.Stderr -Message 'Bash stderr should be forwarded exactly with its LF newline'

$exitResult = Invoke-Launcher -Command 'exit 23'
Assert-Equal -Expected 23 -Actual $exitResult.ExitCode -Message 'Bash exit status should be propagated'

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "invoke-git-bash-hook-$([guid]::NewGuid().ToString('N'))"
$fixtureBin = Join-Path $fixtureRoot 'bin'
try {
    $actualGitCore = Get-Item -LiteralPath ((& git --exec-path).Trim())
    $actualGitRoot = $actualGitCore.Parent.Parent.Parent
    $fixtureGitCore = Join-Path $fixtureRoot 'clangarm64/libexec/git-core'
    New-Item -ItemType Directory -Path $fixtureGitCore | Out-Null
    New-Item -ItemType Junction -Path $fixtureBin -Target (Join-Path $actualGitRoot.FullName 'bin') | Out-Null

    $arm64Result = Invoke-Launcher -Command 'exit 0' -Environment @{ GIT_EXEC_PATH = $fixtureGitCore }
    Assert-Equal -Expected 0 -Actual $arm64Result.ExitCode -Message 'Git for Windows architecture directory name should not be fixed to mingw64'
    Assert-Equal -Expected '' -Actual $arm64Result.Stdout -Message 'ARM64 layout probe should not write stdout'
    Assert-Equal -Expected '' -Actual $arm64Result.Stderr -Message 'ARM64 layout probe should not write stderr'
}
finally {
    if (Test-Path -LiteralPath $fixtureBin) {
        Remove-Item -LiteralPath $fixtureBin -Force
    }
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

$resolutionError = 'invoke-git-bash-hook: could not resolve Git for Windows bash.exe; ensure Git for Windows is installed and git is on PATH.'
$failureResult = Invoke-Launcher -Command 'exit 0' -Environment @{ PATH = '' }
Assert-Equal -Expected 127 -Actual $failureResult.ExitCode -Message 'Git resolution failure should exit 127'
Assert-Equal -Expected '' -Actual $failureResult.Stdout -Message 'Git resolution failure should not write stdout'
Assert-Equal -Expected "$resolutionError$([Environment]::NewLine)" -Actual $failureResult.Stderr -Message 'Git resolution failure should write exactly one actionable stderr line'

$nonblankStderrLines = @(
    ($failureResult.Stderr -split '\r?\n') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
Assert-Equal -Expected 1 -Actual $nonblankStderrLines.Count -Message 'Git resolution failure should write one nonblank stderr line'
Assert-Equal -Expected $true -Actual $nonblankStderrLines[0].StartsWith('invoke-git-bash-hook:', [StringComparison]::Ordinal) -Message 'Git resolution error should have the launcher prefix'
Assert-Equal -Expected $true -Actual $nonblankStderrLines[0].Contains('Git for Windows', [StringComparison]::Ordinal) -Message 'Git resolution error should identify the missing dependency'
Assert-Equal -Expected $true -Actual $nonblankStderrLines[0].Contains('PATH', [StringComparison]::Ordinal) -Message 'Git resolution error should include actionable PATH guidance'

Write-Output 'invoke-git-bash-hook tests passed'
