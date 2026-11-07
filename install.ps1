[CmdletBinding()]
param(
    [string]$Stick,
    [ValidateSet('localhost', 'ad102', 'ga102', 'tu10x', 'all')]
    [string]$Family = 'localhost',
    [string]$Cache = (Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows'),
    [string]$InputsDir,
    [switch]$SkipMaker,
    [switch]$NoStick,
    [switch]$FormatStick,
    [switch]$ConfirmFormat,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Unlock.psm1') -Force

Write-Host ''
Write-Host '== gpu-unlock for Windows ==' -ForegroundColor Cyan

$envResult = Test-UnlockEnvironment
$envResult.Checks | Format-Table Name, Level, Detail -AutoSize | Out-String | Write-Host

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

if ($DryRun) {
    Write-Host "Dry run OK: preflight passed, family=$Family. No download or copy performed." -ForegroundColor Yellow
    return
}

$release = Get-UnlockRelease -Cache $Cache
Write-Host "Release $($release.Tag) verified: $($release.Dir)" -ForegroundColor Green

$staging = Join-Path $Cache 'usbroot'
if (-not $SkipMaker) {
    if (-not $InputsDir) { $InputsDir = Join-Path $Cache 'inputs' }
    Write-Host "Generating assets for $Family ..." -ForegroundColor Cyan
    Invoke-UnlockMaker -Maker $release.Maker -OutDir $staging -WorkDir $InputsDir -Family $Family
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
    -FormatStick:$FormatStick -ConfirmFormat:$ConfirmFormat -BackupRoot $backup
if (-not $install.Ok) { throw ('Stick verification failed for: ' + ($install.Bad -join ', ')) }

Write-Host "Stick ready: $($install.Root) (hashes verified)" -ForegroundColor Green
Write-Host ''
Write-Host 'Next: Restart -> F12 -> UEFI: <stick> -> Space/Enter.' -ForegroundColor Cyan
Write-Host 'Then run (elevated): .\verify.ps1' -ForegroundColor Cyan
