[CmdletBinding()]
param(
    [switch]$InstallApp,
    [switch]$InstallStick,
    [switch]$Uninstall,
    [string]$InstallDir,
    [switch]$Silent,
    [switch]$Force,
    [ValidateSet('all', 'localhost', 'ad102', 'ga102', 'tu10x')]
    [string]$Family = 'all',
    [string]$Stick,
    [switch]$Manual,
    [ValidateRange(1, 30)]
    [int]$Countdown = 5,
    [switch]$NoApp,
    [switch]$FormatStick,
    [switch]$ConfirmFormat,
    [switch]$Interactive = $true,
    [switch]$DryRun,
    [switch]$WhatIf,
    [string]$Cache,
    [string]$InputsDir,
    [switch]$SkipMaker,
    [switch]$NoStick,
    [switch]$NoAutoStart,
    [switch]$NoDesktop,
    [switch]$NoStartMenu,
    [switch]$SkipElevation
)
$ErrorActionPreference = 'Stop'
if ($Silent) { $ProgressPreference = 'SilentlyContinue' }

$repo = $PSScriptRoot
$appName = 'GPU Unlock'
$versionPath = Join-Path $PSScriptRoot 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath)) { throw "Missing version file: $versionPath" }
$version = (Get-Content -LiteralPath $versionPath -Raw).Trim()

# --- Elevate once so double-clicking SETUP.cmd can do everything ---
function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin) -and -not $SkipElevation) {
    $forward = @()
    foreach ($name in @('InstallApp','InstallStick','Uninstall','Silent','Force','Manual','NoApp',
                        'FormatStick','ConfirmFormat','Interactive','DryRun','WhatIf','SkipMaker',
                        'NoStick','NoAutoStart','NoDesktop','NoStartMenu')) {
        if ((Get-Variable -Name $name -ValueOnly -ErrorAction SilentlyContinue)) { $forward += "-$name" }
    }
    foreach ($pair in @(@('Family', $Family), @('Stick', $Stick), @('InstallDir', $InstallDir),
                        @('Cache', $Cache), @('InputsDir', $InputsDir))) {
        if ($PSBoundParameters.ContainsKey($pair[0])) { $forward += "-$($pair[0]) `"$($pair[1])`"" }
    }
    if ($PSBoundParameters.ContainsKey('Countdown')) { $forward += "-Countdown $Countdown" }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"')) + $forward
    Write-Host 'Requesting administrator rights...' -ForegroundColor Yellow
    try {
        $child = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -PassThru -Wait
    }
    catch {
        Write-Host "Elevation was declined or failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    exit $child.ExitCode
}

Import-Module (Join-Path $PSScriptRoot 'Unlock\Unlock.psm1') -Force -DisableNameChecking

Write-Host "=== $appName Setup v$version ===" -ForegroundColor Cyan
Write-Host ""

if ($Uninstall) {
    Write-Host "Uninstalling $appName..." -ForegroundColor Yellow
    $uninstallScript = Join-Path $repo 'Uninstall.ps1'
    if (-not (Test-Path $uninstallScript)) {
        Write-Host "Uninstall.ps1 not found!" -ForegroundColor Red
        exit 1
    }
    $LASTEXITCODE = 0
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstallScript -Remove -Silent -Force
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Uninstall failed (exit $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    exit 0
}

# Default: install both app and stick
if (-not $InstallApp -and -not $InstallStick) {
    $InstallApp = $true
    $InstallStick = $true
}

$exitCode = 0

if ($InstallStick) {
    Write-Host ""
    Write-Host "Step 1/2: Prepare USB Stick" -ForegroundColor Cyan
    Write-Host "---------------------------" -ForegroundColor Gray

    $stickArgs = @{ Family = $Family; Countdown = $Countdown }
    if ($Stick) { $stickArgs.Stick = $Stick }
    if ($Manual) { $stickArgs.Manual = $true }
    if ($FormatStick) { $stickArgs.FormatStick = $true }
    if ($ConfirmFormat) { $stickArgs.ConfirmFormat = $true }
    if ($Interactive) { $stickArgs.Interactive = $true }
    if ($DryRun) { $stickArgs.DryRun = $true }
    if ($WhatIf) { $stickArgs.WhatIf = $true }
    if ($Cache) { $stickArgs.Cache = $Cache }
    if ($InputsDir) { $stickArgs.InputsDir = $InputsDir }
    if ($SkipMaker) { $stickArgs.SkipMaker = $true }
    if ($NoStick) { $stickArgs.NoStick = $true }

    try {
        & (Join-Path $repo 'install.ps1') @stickArgs
        if ($DryRun -or $WhatIf) {
            Write-Host "USB stick dry run completed (no changes)." -ForegroundColor Yellow
        }
        else {
            Write-Host "USB stick preparation completed successfully!" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "USB stick preparation failed: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    }
}

if ($InstallApp -and -not $NoApp -and -not $DryRun -and -not $WhatIf -and $exitCode -eq 0) {
    Write-Host ""
    Write-Host "Step 2/2: Install Windows Application" -ForegroundColor Cyan
    Write-Host "-------------------------------------" -ForegroundColor Gray

    $appArgs = @{}
    if ($NoAutoStart) { $appArgs.NoAutoStart = $true }
    if ($NoDesktop) { $appArgs.NoDesktop = $true }
    if ($NoStartMenu) { $appArgs.NoStartMenu = $true }
    if ($SkipElevation) { $appArgs.SkipElevation = $true }
    if ($Silent) { $appArgs.Silent = $true }
    if ($Force) { $appArgs.Force = $true }
    if ($InstallDir) { $appArgs.InstallDir = $InstallDir }

    try {
        $LASTEXITCODE = 0
        & (Join-Path $repo 'app\Install-App.ps1') @appArgs
        if ($LASTEXITCODE -ne 0) { throw "Install-App.ps1 failed (exit $LASTEXITCODE)." }
        Write-Host "Windows application installed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "Application installation failed: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    }
}

Write-Host ""
if ($exitCode -eq 0) {
    if ($DryRun -or $WhatIf) {
        Write-Host "=== Dry run complete - no changes were made. ===" -ForegroundColor Yellow
    }
    else {
        Write-Host "=== Setup completed successfully! ===" -ForegroundColor Green
        Write-Host ""
        if ($InstallStick) {
            Write-Host "Next steps for the USB stick:" -ForegroundColor Cyan
            Write-Host "  1. Keep the USB stick connected and restart" -ForegroundColor Gray
            Write-Host "  2. Enter BIOS (Del/F2 at boot), set the USB stick (UEFI: ...) as #1 boot priority" -ForegroundColor Gray
            Write-Host "  3. Save & Exit (F10)" -ForegroundColor Gray
            Write-Host "  4. Windows will boot with GPU Unlock active" -ForegroundColor Gray
            Write-Host ""
        }
        if ($InstallApp -and -not $NoApp) {
            Write-Host "Status app: 'GPU Unlock' in Start Menu / Desktop" -ForegroundColor Gray
            if (-not $NoAutoStart) {
                Write-Host "Auto-check: Runs at every logon (15s delay)" -ForegroundColor Gray
            }
        }
    }
}
else {
    Write-Host "=== Setup failed ===" -ForegroundColor Red
}

exit $exitCode