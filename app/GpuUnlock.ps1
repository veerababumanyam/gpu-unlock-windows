[CmdletBinding()]
param(
    [switch]$Interactive,
    [switch]$Repair,
    [string]$Cache = (Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows'),
    [switch]$Silent
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Unlock\Unlock.psm1') -Force -DisableNameChecking

$repoRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $Cache 'status.log'
New-Item -ItemType Directory -Force -Path $Cache | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$timestamp] [$Level] $Message"
    try {
        Invoke-LogRotation -LogPath $logPath -MaxSizeMB 5 -MaxFiles 5
        Add-Content -LiteralPath $logPath -Value $logLine -ErrorAction Stop
    } catch { }
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($Interactive) {
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
                     '-Interactive', '-Cache', ('"' + $Cache + '"'))
        if ($Repair) { $argList += '-Repair' }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
        return
    }
    Write-Log "not elevated; cannot check" 'WARN'
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-GpuUnlockStatus {
    param([string[]]$Arguments = @())
    $ssdiag = Join-Path $Cache 'ssdiag.exe'
    if (-not (Test-Path -LiteralPath $ssdiag)) {
        return [pscustomobject]@{ Ok = $false; Ss0 = ''; Ss1 = ''; Raw = "ssdiag not found at $ssdiag. Run SETUP.cmd first." }
    }
    try {
        Invoke-UnlockSsdiag -SsdiagPath $ssdiag -Arguments $Arguments
    }
    catch {
        [pscustomobject]@{ Ok = $false; Ss0 = ''; Ss1 = ''; Raw = $_.Exception.Message }
    }
}

if (-not $Interactive) {
    $status = Get-GpuUnlockStatus
    Write-Log ("ok={0} ss0={1} ss1={2}" -f $status.Ok, $status.Ss0, $status.Ss1)
    if (-not $status.Ok -and -not $Silent) {
        [void][System.Windows.Forms.MessageBox]::Show(
            ("GPU unlock is NOT active.`n`nSS0={0}  SS1={1}`n`nInsert the GPU Unlock USB stick and restart.`nIf it is already inserted, check the BIOS boot order." -f $status.Ss0, $status.Ss1),
            'GPU Unlock', 'OK', 'Warning')
    }
    if ($status.Ok) { exit 0 } else { exit 1 }
}

$script:last = $null

function Update-Ui {
    $script:last = Get-GpuUnlockStatus
    if ($script:last.Ok) {
        $label.Text = 'UNLOCKED'
        $label.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 0)
    }
    else {
        $label.Text = 'NOT UNLOCKED'
        $label.ForeColor = [System.Drawing.Color]::FromArgb(190, 30, 30)
    }

    $gpu = ''
    try { $gpu = (@(Get-UnlockTargets) | ForEach-Object { "$($_.Name) @ $($_.BusId)" }) -join ', ' } catch { }

    $details.Text = @(
        "GPU:  $gpu",
        "SS0:  $($script:last.Ss0)",
        "SS1:  $($script:last.Ss1)",
        '',
        $script:last.Raw
    ) -join [Environment]::NewLine
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GPU Unlock Status'
$form.Size = New-Object System.Drawing.Size(640, 520)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.MinimumSize = New-Object System.Drawing.Size(500, 400)

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(16, 12)
$label.Size = New-Object System.Drawing.Size(590, 36)
$label.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$label.Text = 'Checking...'
$label.Anchor = 'Top, Left, Right'

$hint = New-Object System.Windows.Forms.Label
$hint.Location = New-Object System.Drawing.Point(16, 48)
$hint.Size = New-Object System.Drawing.Size(590, 34)
$hint.Text = 'If NOT UNLOCKED: keep the USB stick connected, restart, and make sure the stick is first in the BIOS boot order.'
$hint.ForeColor = [System.Drawing.Color]::DimGray
$hint.Anchor = 'Top, Left, Right'

$details = New-Object System.Windows.Forms.TextBox
$details.Location = New-Object System.Drawing.Point(16, 86)
$details.Size = New-Object System.Drawing.Size(590, 350)
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.Font = New-Object System.Drawing.Font('Consolas', 9)
$details.Anchor = 'Top, Bottom, Left, Right'

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = 'Check again'
$btnCheck.Location = New-Object System.Drawing.Point(16, 446)
$btnCheck.Size = New-Object System.Drawing.Size(110, 32)
$btnCheck.Anchor = 'Bottom, Left'

$btnRepair = New-Object System.Windows.Forms.Button
$btnRepair.Text = 'Repair selectors'
$btnRepair.Location = New-Object System.Drawing.Point(134, 446)
$btnRepair.Size = New-Object System.Drawing.Size(120, 32)
$btnRepair.Anchor = 'Bottom, Left'

$btnGuide = New-Object System.Windows.Forms.Button
$btnGuide.Text = 'Open guide'
$btnGuide.Location = New-Object System.Drawing.Point(262, 446)
$btnGuide.Size = New-Object System.Drawing.Size(100, 32)
$btnGuide.Anchor = 'Bottom, Left'

$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Text = 'Open log'
$btnLog.Location = New-Object System.Drawing.Point(370, 446)
$btnLog.Size = New-Object System.Drawing.Size(100, 32)
$btnLog.Anchor = 'Bottom, Left'

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(506, 446)
$btnClose.Size = New-Object System.Drawing.Size(100, 32)
$btnClose.Anchor = 'Bottom, Right'
$btnClose.DialogResult = 'Cancel'

$btnCheck.Add_Click({ Update-Ui })
$btnRepair.Add_Click({
    $r = Get-GpuUnlockStatus -Arguments @('--reapply')
    [void][System.Windows.Forms.MessageBox]::Show(
        ("Repair attempted.`n`nSS0={0}  SS1={1}" -f $r.Ss0, $r.Ss1), 'GPU Unlock', 'OK', 'Information')
    Update-Ui
})
$btnGuide.Add_Click({
    $guide = Join-Path $repoRoot 'TROUBLESHOOTING.md'
    if (Test-Path -LiteralPath $guide) { Start-Process $guide }
    else { [void][System.Windows.Forms.MessageBox]::Show('TROUBLESHOOTING.md was not found in the install folder.', 'GPU Unlock', 'OK', 'Information') }
})
$btnLog.Add_Click({ 
    if (Test-Path $logPath) { Start-Process $logPath } 
    else { [void][System.Windows.Forms.MessageBox]::Show('No log file found yet.', 'GPU Unlock', 'OK', 'Information') }
})
$btnClose.Add_Click({ $form.Close() })

$form.Controls.AddRange(@($label, $hint, $details, $btnCheck, $btnRepair, $btnGuide, $btnLog, $btnClose))
$form.AcceptButton = $btnCheck
$form.CancelButton = $btnClose

if ($Repair) {
    $null = Get-GpuUnlockStatus -Arguments @('--reapply')
}
Update-Ui
[void]$form.ShowDialog()