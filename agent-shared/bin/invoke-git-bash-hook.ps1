param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Command
)

try {
    $gitExecPathLines = @(& git --exec-path 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'git --exec-path failed'
    }

    $gitExecPathLine = $gitExecPathLines |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1

    if ($null -eq $gitExecPathLine) {
        throw 'git --exec-path returned no path'
    }

    $gitCore = Get-Item -LiteralPath $gitExecPathLine.Trim() -ErrorAction Stop
    if (
        -not $gitCore.PSIsContainer -or
        $gitCore.Name -ine 'git-core' -or
        $gitCore.Parent.Name -ine 'libexec'
    ) {
        throw 'git --exec-path did not identify Git for Windows'
    }

    $gitRoot = $gitCore.Parent.Parent.Parent
    $bash = Join-Path $gitRoot.FullName 'bin/bash.exe'
    if (-not [System.IO.File]::Exists($bash)) {
        throw 'Git for Windows bash.exe was not found'
    }
}
catch {
    [Console]::Error.WriteLine(
        'invoke-git-bash-hook: could not resolve Git for Windows bash.exe; ensure Git for Windows is installed and git is on PATH.'
    )
    exit 127
}

& $bash -c "$Command"
exit $LASTEXITCODE
