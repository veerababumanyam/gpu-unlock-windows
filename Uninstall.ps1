<#
.SYNOPSIS
    GPU Unlock uninstaller.

.DESCRIPTION
    Removes the GpuUnlockStatus scheduled task, shortcuts, Apps & Features
    entry, registry settings, installed files, cache and installer logs.
    With -CleanStick, generated files are also removed from a GPU Unlock USB
    stick; the stick's EFI boot loader is left in place.

    The USB stick backup created by setup is kept by default. Use
    -RemoveBackups to remove it as well.

.PARAMETER Remove
    Required confirmation switch.

.PARAMETER Silent
    Suppress console output (used by Apps & Features).

.PARAMETER Force
    Also remove the installed application files.

.PARAMETER InstallDir
    Optional custom installation directory. When omitted, the installer
    resolves the path recorded at install time.

.PARAMETER CleanStick
    Remove GPU Unlock-generated files from a removable stick that contains
    GPU Unlock markers.

.PARAMETER RemoveBackups
    Also remove the local backup of the stick's previous boot loader.

.EXAMPLE
    .\Uninstall.ps1 -Remove -Force

.EXAMPLE
    .\Uninstall.ps1 -Remove -Force -CleanStick
#>

[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$Silent,
    [switch]$Force,
    [string]$InstallDir,
    [switch]$CleanStick,
    [switch]$RemoveBackups
)

$ErrorActionPreference = 'Stop'

function Write-UninstallLog {
    param([string]$Message, [string]$Level = 'INFO')
    if ($Silent) { return }
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN' { 'Yellow' }
        default { 'Gray' }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Remove-UnlockStickFiles {
    $patterns = @(
        'i_know_what_i_am_doing.txt',
        'tx-quiet.txt',
        'gsp-gate.txt',
        'SHA256SUMS.txt',
        'booter_load_*.bin',
        'gsp_boot_*.bin',
        'gsp_boot_desc_*.bin',
        'fwimage_*.bin',
        'fwsignature_*.bin',
        'scrubber_*.bin',
        'sec2_bl_*.bin',
        'v67-*.bin'
    )

    $volumes = @(Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter })
    foreach ($volume in $volumes) {
        $root = "$($volume.DriveLetter):\"
        $hasMarker = @('i_know_what_i_am_doing.txt', 'tx-quiet.txt', 'gsp-gate.txt' |
            Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
        if (-not $hasMarker) { continue }

        foreach ($pattern in $patterns) {
            Get-ChildItem -LiteralPath $root -Filter $pattern -File -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
        Write-UninstallLog "Removed GPU Unlock files from $root. The EFI boot loader was left in place; format the stick to erase everything."
    }
}

if (-not $Remove) {
    Write-Error 'Usage: .\Uninstall.ps1 -Remove [-Silent] [-Force] [-InstallDir <path>] [-CleanStick] [-RemoveBackups]'
    exit 1
}

$scriptDir = Split-Path -Parent $PSCommandPath
$installScript = Join-Path $scriptDir 'app\Install-App.ps1'
if (-not (Test-Path -LiteralPath $installScript)) {
    $installScript = Join-Path $scriptDir 'Install-App.ps1'
}
if (-not (Test-Path -LiteralPath $installScript)) {
    Write-Error "Install-App.ps1 not found. Cannot uninstall cleanly."
    exit 1
}

Write-UninstallLog 'Removing GPU Unlock application...'
$relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $installScript + '"'),
              '-Remove', '-Silent', '-Force')
if ($InstallDir) { $relaunch += @('-InstallDir', ('"' + $InstallDir + '"')) }

$LASTEXITCODE = 0
& powershell.exe @relaunch
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-UninstallLog "Application removal failed (exit $code)." 'ERROR'
    exit $code
}

# Remove the per-user cache (downloads, ssdiag, logs) but keep the stick backup
# unless the caller explicitly asks for its removal.
$cache = Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows'
if (Test-Path -LiteralPath $cache) {
    Get-ChildItem -LiteralPath $cache -Force -ErrorAction SilentlyContinue |
        Where-Object { $RemoveBackups -or $_.Name -ne 'backup' } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Get-ChildItem -LiteralPath $cache -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $cache -Force -ErrorAction SilentlyContinue
    }
    Write-UninstallLog "Removed cache: $cache"
}

$programData = Join-Path $env:ProgramData 'GPU Unlock'
if (Test-Path -LiteralPath $programData) {
    Remove-Item -LiteralPath $programData -Recurse -Force -ErrorAction SilentlyContinue
    Write-UninstallLog "Removed installer logs: $programData"
}

if ($CleanStick) {
    Remove-UnlockStickFiles
}

Write-UninstallLog 'GPU Unlock uninstalled successfully.'
exit 0
