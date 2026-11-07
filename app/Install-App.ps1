[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Remove,
    [switch]$NoAutoStart,
    [switch]$NoDesktop,
    [switch]$NoStartMenu,
    [switch]$SkipElevation,
    [switch]$Silent,
    [switch]$Force,
    [string]$InstallDir
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskName = 'GpuUnlockStatus'
$appName = 'GPU Unlock'
$versionPath = Join-Path $repo 'VERSION'
if (Test-Path -LiteralPath $versionPath) {
    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
}
else {
    $configPath = Join-Path $repo 'unlock.config.json'
    if (Test-Path -LiteralPath $configPath) {
        $version = ((Get-Content -LiteralPath $configPath -Raw) | ConvertFrom-Json).app.version
    }
    else {
        $version = 'unknown'
    }
}

# Default install directory. When uninstalling, the installed copy does not pass
# -InstallDir, so honour the path recorded at install time (custom installs).
if (-not $InstallDir) {
    $registeredDir = $null
    try {
        $registeredDir = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\GpuUnlock' -Name 'InstallDir' -ErrorAction Stop).InstallDir
    }
    catch { $registeredDir = $null }
    if ($registeredDir -and (Test-Path -LiteralPath (Join-Path $registeredDir 'app\GpuUnlock.ps1'))) {
        $InstallDir = $registeredDir
    }
    else {
        $InstallDir = Join-Path $env:ProgramFiles $appName
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$timestamp] [$Level] $Message"
    if (-not $Silent) {
        $color = if ($Level -eq 'ERROR') { 'Red' } elseif ($Level -eq 'WARN') { 'Yellow' } else { 'Green' }
        Write-Host $logLine -ForegroundColor $color
    }
    try {
        $logDir = Join-Path $env:ProgramData $appName
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
        Add-Content -Path (Join-Path $logDir 'install.log') -Value $logLine -ErrorAction SilentlyContinue
    } catch { }
}

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (-not (Test-Admin)) {
        if ($SkipElevation) {
            Write-Log "Administrator rights required. Re-run without -SkipElevation." 'ERROR'
            exit 1
        }
        Write-Log "Requesting administrator elevation..."
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
        if ($Remove) { $argList += '-Remove' }
        if ($NoAutoStart) { $argList += '-NoAutoStart' }
        if ($NoDesktop) { $argList += '-NoDesktop' }
        if ($NoStartMenu) { $argList += '-NoStartMenu' }
        if ($Silent) { $argList += '-Silent' }
        if ($Force) { $argList += '-Force' }
        if ($InstallDir) { $argList += "-InstallDir `"$InstallDir`"" }
        try {
            $child = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -PassThru -Wait
        }
        catch {
            Write-Log "Elevation was declined or failed: $($_.Exception.Message)" 'ERROR'
            exit 1
        }
        # The elevated child performed the work; return its actual result.
        exit $child.ExitCode
    }
    return $true
}

function Write-ErrorLog {
    param([string]$Context, [string]$Level = 'WARN')
    $msg = $_.ToString()
    if ($_.Exception) { $msg = $_.Exception.Message }
    Write-Log "${Context}: $msg" $Level
}

function New-AppShortcut {
    param([string]$Path, [string]$Arguments, [string]$Description = 'GPU Unlock Status', [string]$IconPath = '', [string]$WorkingDirectory)
    if (-not $PSCmdlet.ShouldProcess("Create shortcut: $Path")) { return $true }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($Path)
        $lnk.TargetPath = $powershell
        $lnk.Arguments = $Arguments
        if ($WorkingDirectory) { $lnk.WorkingDirectory = $WorkingDirectory } else { $lnk.WorkingDirectory = $repo }
        $lnk.IconLocation = $IconPath
        $lnk.Description = $Description
        $lnk.Save()
        Write-Log "Created shortcut: $Path"
        return $true
    }
    catch { Write-ErrorLog "Failed to create shortcut $Path"; return $false }
}

function Remove-AppShortcut {
    param([string]$Path)
    if (-not $PSCmdlet.ShouldProcess("Remove shortcut: $Path")) { return $true }
    if (Test-Path -LiteralPath $Path) {
        try {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            Write-Log "Removed shortcut: $Path"
            return $true
        }
        catch { Write-ErrorLog "Failed to remove shortcut $Path"; return $false }
    }
    return $true
}

function Get-UninstallCommandLine {
    param(
        [Parameter(Mandatory)][string]$PowerShellPath,
        [Parameter(Mandatory)][string]$UninstallScript
    )
    return ('"' + $PowerShellPath + '" -NoProfile -ExecutionPolicy Bypass -File "' + $UninstallScript + '" -Remove -Silent -Force')
}

function Get-UninstallIcon {
    param([Parameter(Mandatory)][string]$InstallDir)
    $candidate = Join-Path $InstallDir 'icon.ico'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return (Join-Path $env:SystemRoot 'System32\imageres.dll,109')
}

function Register-Uninstaller {
    param([string]$InstallDir, [string]$UninstallScript)
    if (-not $PSCmdlet.ShouldProcess("Register uninstaller in Windows Apps & Features")) { return $true }
    $uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GpuUnlock"
    try {
        $uninstallCommand = Get-UninstallCommandLine -PowerShellPath $powershell -UninstallScript $UninstallScript
        $displayIcon = Get-UninstallIcon -InstallDir $InstallDir
        if (-not (Test-Path $uninstallKey)) { New-Item -Path $uninstallKey -Force | Out-Null }
        Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value "$appName $version" -Force
        Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value $version -Force
        Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'GPU Unlock Project' -Force
        Set-ItemProperty -Path $uninstallKey -Name 'InstallLocation' -Value $InstallDir -Force
        Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' -Value $uninstallCommand -Force
        Set-ItemProperty -Path $uninstallKey -Name 'QuietUninstallString' -Value $uninstallCommand -Force
        Set-ItemProperty -Path $uninstallKey -Name 'NoModify' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $uninstallKey -Name 'NoRepair' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $uninstallKey -Name 'EstimatedSize' -Value 5120 -Type DWord -Force
        Set-ItemProperty -Path $uninstallKey -Name 'InstallDate' -Value (Get-Date -Format 'yyyyMMdd') -Force
        Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value $displayIcon -Force
        Write-Log "Registered uninstaller in Windows Apps & Features"
        return $true
    }
    catch { Write-ErrorLog "Failed to register uninstaller" 'ERROR'; return $false }
}

function Unregister-Uninstaller {
    if (-not $PSCmdlet.ShouldProcess("Unregister uninstaller from Windows Apps & Features")) { return $true }
    $uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GpuUnlock"
    if (Test-Path $uninstallKey) {
        try {
            Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction Stop
            Write-Log "Unregistered uninstaller"
            return $true
        }
        catch { Write-ErrorLog "Failed to unregister uninstaller" 'ERROR'; return $false }
    }
    return $true
}

function Install-Files {
    param([string]$InstallDir)
    if (-not $PSCmdlet.ShouldProcess("Install application files to: $InstallDir")) { return $true }
    try {
        if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }
        
        $files = @('unlock.config.json', 'verify.ps1', 'TROUBLESHOOTING.md', 'README.md',
                   'LICENSE', 'THIRD-PARTY-NOTICES.md', 'VERSION')
        foreach ($f in $files) {
            $src = Join-Path $repo $f
            $dst = Join-Path $InstallDir $f
            if (Test-Path $src) {
                Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
                Write-Log "Installed: $f"
            }
        }
        
        $docsSrc = Join-Path $repo 'docs'
        $docsDst = Join-Path $InstallDir 'docs'
        if (Test-Path $docsSrc) {
            if (Test-Path $docsDst) { Remove-Item -Recurse -Force -Path $docsDst }
            Copy-Item -LiteralPath $docsSrc -Destination $docsDst -Recurse -Force -ErrorAction Stop
            Write-Log "Installed docs folder"
        }
        
        $appSrc = Join-Path $repo 'app'
        $appDst = Join-Path $InstallDir 'app'
        if (Test-Path $appSrc) {
            if (Test-Path $appDst) { Remove-Item -Recurse -Force -Path $appDst }
            Copy-Item -LiteralPath $appSrc -Destination $appDst -Recurse -Force -ErrorAction Stop
            Write-Log "Installed app folder"
        }
        
        $modSrc = Join-Path $repo 'Unlock'
        $modDst = Join-Path $InstallDir 'Unlock'
        if (Test-Path $modSrc) {
            if (Test-Path $modDst) { Remove-Item -Recurse -Force -Path $modDst }
            Copy-Item -LiteralPath $modSrc -Destination $modDst -Recurse -Force -ErrorAction Stop
            Write-Log "Installed Unlock module folder"
        }
        
        Write-Log "Application files installed to: $InstallDir"
        return $true
    }
    catch { Write-ErrorLog "Failed to install files" 'ERROR'; return $false }
}

function Remove-Files {
    param([string]$InstallDir)
    if (-not $PSCmdlet.ShouldProcess("Remove application files from: $InstallDir")) { return $true }
    if (Test-Path $InstallDir) {
        try {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
            Write-Log "Removed application files from: $InstallDir"
            return $true
        }
        catch { Write-ErrorLog "Failed to remove files" 'ERROR'; return $false }
    }
    return $true
}

function Create-Shortcuts {
    param([string]$InstallDir)
    $iconPath = Join-Path $InstallDir 'icon.ico'
    if (-not (Test-Path $iconPath)) { $iconPath = (Join-Path $env:SystemRoot 'System32\imageres.dll,109') }
    $installedApp = Join-Path $InstallDir 'app\GpuUnlock.ps1'
    $workDir = Join-Path $InstallDir 'app'
    $shortcutArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedApp`" -Interactive"
    $success = $true
    
    if (-not $NoDesktop) {
        $desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) "$appName.lnk"
        $success = (New-AppShortcut -Path $desktopLink -Arguments $shortcutArgs -IconPath $iconPath -WorkingDirectory $workDir) -and $success
    }
    
    if (-not $NoStartMenu) {
        $startLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' "$appName.lnk"
        $success = (New-AppShortcut -Path $startLink -Arguments $shortcutArgs -IconPath $iconPath -WorkingDirectory $workDir) -and $success
        $uninstallWizard = Join-Path $InstallDir 'app\UninstallWizard.ps1'
        if (Test-Path -LiteralPath $uninstallWizard) {
            $uninstallArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstallWizard`""
            $uninstallLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Uninstall GPU Unlock.lnk'
            $success = (New-AppShortcut -Path $uninstallLink -Arguments $uninstallArgs -Description 'Uninstall GPU Unlock' -IconPath $iconPath -WorkingDirectory $workDir) -and $success
        }
    }
    
    return $success
}

function Remove-Shortcuts {
    $success = $true
    if (-not $NoDesktop) {
        $desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) "$appName.lnk"
        $success = (Remove-AppShortcut -Path $desktopLink) -and $success
    }
    if (-not $NoStartMenu) {
        $startLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' "$appName.lnk"
        $success = (Remove-AppShortcut -Path $startLink) -and $success
        $uninstallLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Uninstall GPU Unlock.lnk'
        $success = (Remove-AppShortcut -Path $uninstallLink) -and $success
    }
    return $success
}

function Register-GpuUnlockTask {
    param([string]$InstallDir)
    if (-not $PSCmdlet.ShouldProcess("Register scheduled task: $taskName")) { return $true }
    try {
        $installedApp = Join-Path $InstallDir 'app\GpuUnlock.ps1'
        $action = New-ScheduledTaskAction -Execute $powershell `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedApp`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $trigger.Delay = 'PT15S'
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principalDef = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principalDef -Force -ErrorAction Stop | Out-Null
        Write-Log "Scheduled task registered: $taskName"
        return $true
    }
    catch { Write-ErrorLog "Failed to register scheduled task" 'ERROR'; return $false }
}

function Unregister-GpuUnlockTask {
    if (-not $PSCmdlet.ShouldProcess("Unregister scheduled task: $taskName")) { return $true }
    try {
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Log "Scheduled task not present: $taskName"
            return $true
        }
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        Write-Log "Scheduled task unregistered: $taskName"
        return $true
    }
    catch { Write-ErrorLog "Failed to unregister scheduled task" 'WARN'; return $false }
}

function Set-RegistryKeys {
    param([string]$InstallDir)
    if (-not $PSCmdlet.ShouldProcess("Set registry keys for: $appName")) { return $true }
    try {
        $appKey = "HKCU:\SOFTWARE\GpuUnlock"
        if (-not (Test-Path $appKey)) { New-Item -Path $appKey -Force | Out-Null }
        Set-ItemProperty -Path $appKey -Name 'InstallDir' -Value $InstallDir -Force
        Set-ItemProperty -Path $appKey -Name 'Version' -Value $version -Force
        Set-ItemProperty -Path $appKey -Name 'InstallDate' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force
        $autoStart = if ($NoAutoStart) { 0 } else { 1 }
        Set-ItemProperty -Path $appKey -Name 'AutoStart' -Value $autoStart -Type DWord -Force
        Set-ItemProperty -Path $appKey -Name 'CacheDir' -Value (Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows') -Force
        Set-ItemProperty -Path $appKey -Name 'LogLevel' -Value 'INFO' -Force
        
        Write-Log "Registry keys configured"
        return $true
    }
    catch { Write-ErrorLog "Failed to set registry keys" 'ERROR'; return $false }
}

function Remove-RegistryKeys {
    if (-not $PSCmdlet.ShouldProcess("Remove registry keys for: $appName")) { return $true }
    $appKey = "HKCU:\SOFTWARE\GpuUnlock"
    if (Test-Path $appKey) {
        try {
            Remove-Item -Path $appKey -Recurse -Force -ErrorAction Stop
            Write-Log "Registry keys removed"
            return $true
        }
        catch { Write-ErrorLog "Failed to remove registry keys" 'ERROR'; return $false }
    }
    return $true
}

# Main execution
if (-not (Ensure-Admin)) { exit 1 }

if ($Remove) {
    Write-Log "Uninstalling $appName $version..."
    $shortcutsRemoved = Remove-Shortcuts
    $taskRemoved = $true
    if (-not $NoAutoStart) { $taskRemoved = Unregister-GpuUnlockTask }
    if (-not $taskRemoved) {
        Write-Log "Uninstall incomplete: the $taskName logon check could not be removed." 'ERROR'
        exit 1
    }
    if (-not (Unregister-Uninstaller)) {
        Write-Log "Uninstall incomplete: the Apps & Features entry could not be removed." 'ERROR'
        exit 1
    }
    $registryRemoved = Remove-RegistryKeys
    $filesRemoved = $true
    if (-not $Force) {
        Write-Log "Keeping application files at $InstallDir (use -Force to remove)" 'INFO'
    } else {
        $filesRemoved = Remove-Files -InstallDir $InstallDir
    }
    if (-not ($shortcutsRemoved -and $registryRemoved -and $filesRemoved)) {
        Write-Log "Uninstall incomplete: some components could not be removed. Re-run as administrator." 'ERROR'
        exit 1
    }
    Write-Log "$appName uninstalled successfully" 'INFO'
    exit 0
}

Write-Log "Installing $appName $version..."

if (-not (Install-Files -InstallDir $InstallDir)) { exit 1 }

if (-not (Create-Shortcuts -InstallDir $InstallDir)) { Write-Log "Some shortcuts failed to create" 'WARN' }

$taskRegistered = $true
if (-not $NoAutoStart) {
    $taskRegistered = Register-GpuUnlockTask -InstallDir $InstallDir
    if (-not $taskRegistered) { Write-Log "Scheduled task registration failed" 'ERROR' }
}

$uninstallScript = Join-Path $InstallDir 'Uninstall.ps1'
if ($PSCmdlet.ShouldProcess("Install uninstaller script", $uninstallScript)) {
    if (Test-Path (Join-Path $repo 'Uninstall.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repo 'Uninstall.ps1') -Destination $uninstallScript -Force
    }
    else {
        $uninstallContent = @'
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot 'app\Install-App.ps1') -Remove -Silent -Force
'@
        Set-Content -Path $uninstallScript -Value $uninstallContent -Encoding UTF8
    }
}
$uninstallerRegistered = Register-Uninstaller -InstallDir $InstallDir -UninstallScript $uninstallScript
$registryConfigured = Set-RegistryKeys -InstallDir $InstallDir

if (-not ($taskRegistered -and $uninstallerRegistered -and $registryConfigured)) {
    Write-Log "Installation incomplete: one or more Windows components could not be configured." 'ERROR'
    exit 1
}

Write-Log "$appName $version installed successfully!" 'INFO'
Write-Log "Install location: $InstallDir" 'INFO'
Write-Log "Run `"$appName`" from Start Menu or Desktop" 'INFO'
