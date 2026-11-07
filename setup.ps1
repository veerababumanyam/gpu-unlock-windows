[CmdletBinding()]
param(
    [string]$Stick,
    [ValidateSet('all', 'localhost', 'ad102', 'ga102', 'tu10x')]
    [string]$Family = 'all',
    [switch]$Manual,
    [ValidateRange(1, 30)]
    [int]$Countdown = 5,
    [switch]$NoApp
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

Write-Host ''
Write-Host '=== GPU Unlock setup ===' -ForegroundColor Cyan
Write-Host 'Step 1/2: prepare the USB stick' -ForegroundColor Cyan
& (Join-Path $root 'install.ps1') -Stick $Stick -Family $Family -Manual:$Manual -Countdown $Countdown

if (-not $NoApp) {
    Write-Host ''
    Write-Host 'Step 2/2: install the status app' -ForegroundColor Cyan
    & (Join-Path $root 'app\Install-App.ps1')
}

Write-Host ''
Write-Host 'One-time BIOS step (this is what makes it automatic):' -ForegroundColor Cyan
Write-Host '  1. Leave the stick connected and restart. Press Del at the logo.' -ForegroundColor Gray
Write-Host '  2. Boot tab -> Boot Option Priorities -> set the stick (UEFI: ...) as #1.' -ForegroundColor Gray
Write-Host '  3. Save & Exit (F10).' -ForegroundColor Gray
Write-Host ''
Write-Host 'After that: stick in + restart = automatic unlock; stick out = normal Windows.' -ForegroundColor Green
Write-Host 'Full details: docs\BIOS-SETUP.md' -ForegroundColor Gray
