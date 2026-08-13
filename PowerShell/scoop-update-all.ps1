# Update every outdated per-user scoop app, one at a time, so a single failure
# cannot abort the rest.
#
# Why one child process per app: scoop's abort() is "write-host; exit", so a
# hash check failure or a dead download URL terminates the whole scoop process
# and every remaining app is silently skipped. Measured 2026-08-12: a plain
# `scoop update -f makemkv jq` printed "Updating 2 outdated apps", failed
# makemkv on a 525 from the vendor, and never touched jq. A child per app
# contains the damage.
#
# Note that the running-process check is a different path: it prints an error
# and moves on, so those do not take the rest down with them.
#
# Why exit codes are not trusted: that same makemkv failure returned exit code
# 0. Success is decided by diffing `scoop status` before and after instead.
#
# ASCII only on purpose: this is meant to run under Windows PowerShell 5.1,
# which reads a BOM-less file as ANSI. Staying ASCII keeps it correct with no BOM.
#
# The per-app child is always launched with 5.1, never pwsh. scoop's shims all
# prefer pwsh (`command -v pwsh.exe` / `where /q pwsh.exe`), so running scoop
# from pwsh means scoop itself holds the binary it is trying to replace.
#
# That fixes the shim side but not the caller side. scoop also skips any app
# whose binaries are currently running, and a pwsh session is exactly that:
# measured 2026-08-13, a live pwsh session is visible as
# C:\...\scoop\apps\pwsh\current\pwsh.exe, while from 5.1 the same query
# returns zero. So launching this from pwsh leaves pwsh itself un-updated.
# It does not stop the run -- that is the skip path, not abort -- everything
# else still updates. To update pwsh too, run this from nushell, cmd or 5.1.
#
# Global apps are listed but not updated. They need elevation, and doing that
# here would mean deciding how to elevate, what happens when the elevation
# helper is itself the app being updated, and how to tell a per-user app from a
# global one of the same name. Updating them by hand stays a one-liner:
# `gsudo scoop update -g <app>`.
#
# Usage:
#   scoop-update-all                  # every outdated per-user app
#   scoop-update-all -Skip makemkv    # everything except makemkv
#
# To update a single app, just use scoop directly (`scoop update <app>`):
# with one app there is nothing left for a failure to take down.

param(
    [string[]] $Skip = @()
)

$ErrorActionPreference = 'Stop'

# The whole point of this script is that a failing child must not stop the
# loop. Under pwsh, $PSNativeCommandUseErrorActionPreference turns a non-zero
# native exit into a terminating error, which would do exactly that. Both
# shipped entry points start this script with 5.1, where the variable does not
# exist and this is a no-op. It only bites if someone runs the script by hand
# with `pwsh -File`, which is exactly when it is easy to forget.
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference)
{
    $PSNativeCommandUseErrorActionPreference = $false
}

# -File passes "a,b" as a single string, so split by hand.
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$scoopPs1 = Join-Path $env:USERPROFILE 'scoop\apps\scoop\current\bin\scoop.ps1'
if (-not (Test-Path $scoopPs1)) { throw "scoop.ps1 not found: $scoopPs1" }
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# scoop prints its chatter with Write-Host, which goes to the information
# stream rather than the pipeline, so only real objects arrive here.
# 6>$null drops the chatter.
function Get-Outdated
{
    @(& $scoopPs1 status 6>$null | Where-Object { $_.'Latest Version' } | ForEach-Object { $_.Name })
}

$installedApps = @(& $scoopPs1 list 6>$null)
$globalNames = @($installedApps | Where-Object { $_.Info -match 'Global install' } | ForEach-Object { $_.Name })
$perUserNames = @($installedApps | Where-Object { $_.Info -notmatch 'Global install' } | ForEach-Object { $_.Name })

# `scoop status` emits one row per name with no scope marker, so an app that is
# installed both per-user and globally cannot be told apart from here. Such a
# name gets filed under "global" below and would then never be updated. Say so
# instead of dropping it in silence. Measured 2026-08-13 on this machine: no
# overlap (16 global, 87 per-user), so this is a guard, not a live problem.
$ambiguous = @($globalNames | Where-Object { $perUserNames -contains $_ })

$before = Get-Outdated
$skipped = @($before | Where-Object { $Skip -contains $_ })
$globalOutdated = @($before | Where-Object { $Skip -notcontains $_ -and $globalNames -contains $_ })
$targets = @($before | Where-Object { $Skip -notcontains $_ -and $globalNames -notcontains $_ })

$ambiguousOutdated = @($before | Where-Object { $ambiguous -contains $_ })
if ($ambiguousOutdated.Count -gt 0)
{
    Write-Host ("Installed both per-user and globally, so the per-user copy is NOT updated here: {0}" -f ($ambiguousOutdated -join ', ')) -ForegroundColor Yellow
}

if ($skipped.Count -gt 0) { Write-Host ("Skipping: {0}" -f ($skipped -join ', ')) -ForegroundColor DarkGray }

# This script is meant to be callable from pwsh, and a live pwsh session is the
# one thing that blocks its own update (see the header). Say so up front rather
# than letting pwsh look like a permanent unexplained failure at the end.
$pwshDir = Join-Path $env:USERPROFILE 'scoop\apps\pwsh'
if ($targets -contains 'pwsh' -and @(Get-Process | Where-Object { $_.Path -like "$pwshDir\*" }).Count -gt 0)
{
    Write-Host 'pwsh is running, so scoop will skip it. Run this from nushell, cmd or 5.1 to update pwsh.' -ForegroundColor Yellow
}
if ($globalOutdated.Count -gt 0)
{
    Write-Host ("Global, update by hand with ``gsudo scoop update -g <app>``: {0}" -f ($globalOutdated -join ', ')) -ForegroundColor DarkGray
}

if ($targets.Count -eq 0)
{
    Write-Host 'Nothing to update.' -ForegroundColor Green
    exit 0
}

Write-Host ("Targets ({0}): {1}" -f $targets.Count, ($targets -join ', ')) -ForegroundColor Cyan

$i = 0
foreach ($app in $targets)
{
    $i++
    Write-Host ""
    Write-Host ("[{0}/{1}] {2}" -f $i, $targets.Count, $app) -ForegroundColor Yellow
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File $scoopPs1 update $app
}

Write-Host ""
Write-Host 'Re-reading scoop status to decide what actually succeeded...' -ForegroundColor Cyan
$after = Get-Outdated

$failed  = @($targets | Where-Object { $after -contains $_ })
$updated = @($targets | Where-Object { $after -notcontains $_ })

Write-Host ""
Write-Host ("Updated: {0}{1}" -f $updated.Count, $(if ($updated.Count) { ' (' + ($updated -join ', ') + ')' } else { '' })) -ForegroundColor Green
if ($failed.Count -gt 0)
{
    Write-Host ("STILL OUTDATED: {0}" -f ($failed -join ', ')) -ForegroundColor Red
    exit 1
}
exit 0
