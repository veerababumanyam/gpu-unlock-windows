[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$NoAutoStart,
    [switch]$NoDesktop,
    [switch]$SkipElevation
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $PSScriptRoot 'GpuUnlock.ps1'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskName = 'GpuUnlockStatus'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $SkipElevation -and -not $isAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Remove) { $argList += '-Remove' }
    if ($NoAutoStart) { $argList += '-NoAutoStart' }
    if ($NoDesktop) { $argList += '-NoDesktop' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait
    }
    catch {
        Write-Host "Elevation was declined or failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    return
}

function New-AppShortcut {
    param([string]$Path, [string]$Arguments)
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($Path)
    $lnk.TargetPath = $powershell
    $lnk.Arguments = $Arguments
    $lnk.WorkingDirectory = $repo
    $lnk.IconLocation = (Join-Path $env:SystemRoot 'System32\imageres.dll,109')
    $lnk.Description = 'GPU Unlock status'
    $lnk.Save()
}

$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'GPU Unlock Status.lnk'
$startLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\GPU Unlock Status.lnk'
$shortcutArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$app`" -Interactive"

if ($Remove) {
    foreach ($p in @($desktopLink, $startLink)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host 'GPU Unlock app removed.' -ForegroundColor Yellow
    return
}

if (-not $NoDesktop) { New-AppShortcut -Path $desktopLink -Arguments $shortcutArgs }
New-AppShortcut -Path $startLink -Arguments $shortcutArgs

if (-not $NoAutoStart) {
    try {
        $action = New-ScheduledTaskAction -Execute $powershell `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$app`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $trigger.Delay = 'PT15S'
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $principalDef = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principalDef -Force | Out-Null
        Write-Host "Logon status check installed (task: $taskName)." -ForegroundColor Green
    }
    catch {
        Write-Host "Could not install the logon check (needs admin): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host 'Shortcuts created: Desktop and Start Menu -> GPU Unlock Status.' -ForegroundColor Green
