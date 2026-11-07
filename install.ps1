[CmdletBinding()]
param(
    [string]$Stick,
    [ValidateSet('all', 'localhost', 'ad102', 'ga102', 'tu10x')]
    [string]$Family = 'all',
    [string]$Cache = (Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows'),
    [string]$InputsDir,
    [switch]$SkipMaker,
    [switch]$NoStick,
    [switch]$FormatStick,
    [switch]$ConfirmFormat,
    [switch]$Interactive = $true,
    [switch]$Manual,
    [ValidateRange(1, 30)]
    [int]$Countdown = 5,
    [switch]$DryRun,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Unlock\Unlock.psm1') -Force

Write-Output ''
Write-Output '== gpu-unlock for Windows =='

$envResult = Test-UnlockEnvironment
$envResult.Checks | ForEach-Object {
    $color = switch ($_.Level) {
        'ok'     { 'Green' }
        'warn'   { 'Yellow' }
        'error'  { 'Red' }
        default  { 'White' }
    }
    Write-Host ("  [{0}] {1,-14} {2}" -f $_.Level.ToUpper(), $_.Name, $_.Detail) -ForegroundColor $color
}

$targets = @(Get-UnlockTargets)
$targets | Format-Table Index, Name, BusId, Driver -AutoSize | Out-String | Write-Host

if (-not $envResult.Ok) {
    throw 'Preflight failed. Fix the ERROR rows above and re-run.'
}

if ($Family -eq 'localhost') {
    $fams = @(Get-UnlockFamilyFromTargets -Targets $targets)
    if ($fams.Count -eq 0) { throw 'No supported NVIDIA RTX 20/30/40 GPU found.' }
    if ($fams.Count -eq 1) { $Family = $fams[0] } else { $Family = 'all' }
    Write-Host "Detected family: $Family" -ForegroundColor Green
}

if ($DryRun -or $WhatIf) {
    Write-Host "Dry run/WhatIf OK: preflight passed, family=$Family. No download or copy performed." -ForegroundColor Yellow
    return
}

$release = Get-UnlockRelease -Cache $Cache -WhatIf:$WhatIf
Write-Host "Release $($release.Tag) verified: $($release.Dir)" -ForegroundColor Green

$staging = Join-Path $Cache 'usbroot'
if (-not $SkipMaker) {
    if (-not $InputsDir) { $InputsDir = Join-Path $Cache 'inputs' }
    Write-Host "Generating assets for $Family ..." -ForegroundColor Cyan
    Invoke-UnlockMaker -Maker $release.Maker -OutDir $staging -WorkDir $InputsDir -Family $Family -WhatIf:$WhatIf
}

$check = Test-UnlockStaging -Root $staging -Family $Family
if (-not $check.Ok) { throw ('Generated staging is incomplete: ' + ($check.Missing -join ', ')) }
Write-Host "Staging verified ($(@($check.Expected).Count) files)." -ForegroundColor Green

if ($NoStick) {
    Write-Host "Staged at: $staging" -ForegroundColor Yellow
    return
}

$backup = Join-Path $Cache 'backup'
$install = Install-UnlockStick -Staging $staging -Family $Family -DriveLetter $Stick `
    -FormatStick:$FormatStick -ConfirmFormat:$ConfirmFormat -Interactive:$Interactive -BackupRoot $backup -WhatIf:$WhatIf
if (-not $install.Ok) { throw ('Stick verification failed for: ' + ($install.Bad -join ', ')) }

$markers = Set-UnlockMarkers -Root $install.Root -Unattended:(-not $Manual) -Quiet:(-not $Manual) -Countdown $Countdown -WhatIf:$WhatIf

Write-Host "Stick ready: $($install.Root) (hashes verified)" -ForegroundColor Green
if ($install.Formatted) { Write-Host "Stick was formatted to FAT32." -ForegroundColor Green }
Write-Host ("Unattended run: {0} (countdown {1}s); quiet console: {2}" -f $markers.AutoRun, $markers.Countdown, $markers.Quiet) -ForegroundColor Green
Write-Host ''
Write-Host 'One-time BIOS step: set the stick (UEFI: ...) first in the boot order.' -ForegroundColor Cyan
Write-Host 'Then every restart with the stick connected runs the unlock automatically.' -ForegroundColor Cyan
Write-Host 'Without the stick, Windows boots normally.' -ForegroundColor Cyan