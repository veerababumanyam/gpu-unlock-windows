<#
.SYNOPSIS
    GPU Unlock Uninstaller - Removes all components cleanly

.DESCRIPTION
    Uninstalls GPU Unlock (shortcuts, scheduled task, registry keys and,
    with -Force, installed application files). Runs from repo root or from
    the installed folder.

.NOTES
    Can also be run manually: .\Uninstall.ps1 -Remove [-Silent] [-Force]
#>

[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$Silent,
    [switch]$Force,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

if (-not $Remove) {
    Write-Error "Usage: .\Uninstall.ps1 -Remove [-Silent] [-Force] [-InstallDir <path>]"
    exit 1
}

$scriptDir = Split-Path -Parent $PSCommandPath
$installScript = Join-Path $scriptDir 'app\Install-App.ps1'

if (-not (Test-Path $installScript)) {
    # Repo root layout fallback
    $installScript = Join-Path $scriptDir 'Install-App.ps1'
}

if (-not (Test-Path $installScript)) {
    Write-Error "Install-App.ps1 not found. Cannot uninstall cleanly."
    exit 1
}

$relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installScript, '-Remove')
if ($Silent) { $relaunch += '-Silent' }
if ($Force) { $relaunch += '-Force' }
if ($InstallDir) { $relaunch += @('-InstallDir', $InstallDir) }

& powershell.exe @relaunch
exit $LASTEXITCODE