[CmdletBinding()]
param(
    [switch]$Interactive,
    [switch]$Repair,
    [string]$Cache = (Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Unlock.psm1') -Force

$repoRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $Cache 'status.log'
New-Item -ItemType Directory -Force -Path $Cache | Out-Null

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($Interactive) {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Interactive') `
            -Verb RunAs
        return
    }
    Add-Content -LiteralPath $logPath -Value ("{0} not elevated; cannot check" -f (Get-Date -Format s))
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
    Add-Content -LiteralPath $logPath -Value ("{0} ok={1} ss0={2} ss1={3}" -f (Get-Date -Format s), $status.Ok, $status.Ss0, $status.Ss1)
    if (-not $status.Ok) {
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
$form.Text = 'GPU Unlock'
$form.Size = New-Object System.Drawing.Size(640, 520)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(16, 12)
$label.Size = New-Object System.Drawing.Size(590, 36)
$label.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$label.Text = 'Checking...'

$hint = New-Object System.Windows.Forms.Label
$hint.Location = New-Object System.Drawing.Point(16, 48)
$hint.Size = New-Object System.Drawing.Size(590, 34)
$hint.Text = 'If NOT UNLOCKED: keep the USB stick connected, restart, and make sure the stick is first in the BIOS boot order.'
$hint.ForeColor = [System.Drawing.Color]::DimGray

$details = New-Object System.Windows.Forms.TextBox
$details.Location = New-Object System.Drawing.Point(16, 86)
$details.Size = New-Object System.Drawing.Size(590, 350)
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.Font = New-Object System.Drawing.Font('Consolas', 9)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = 'Check again'
$btnCheck.Location = New-Object System.Drawing.Point(16, 446)
$btnCheck.Size = New-Object System.Drawing.Size(110, 32)

$btnRepair = New-Object System.Windows.Forms.Button
$btnRepair.Text = 'Repair selectors'
$btnRepair.Location = New-Object System.Drawing.Point(134, 446)
$btnRepair.Size = New-Object System.Drawing.Size(120, 32)

$btnGuide = New-Object System.Windows.Forms.Button
$btnGuide.Text = 'Open guide'
$btnGuide.Location = New-Object System.Drawing.Point(262, 446)
$btnGuide.Size = New-Object System.Drawing.Size(100, 32)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(506, 446)
$btnClose.Size = New-Object System.Drawing.Size(100, 32)

$btnCheck.Add_Click({ Update-Ui })
$btnRepair.Add_Click({
    $r = Get-GpuUnlockStatus -Arguments @('--reapply')
    [void][System.Windows.Forms.MessageBox]::Show(
        ("Repair attempted.`n`nSS0={0}  SS1={1}" -f $r.Ss0, $r.Ss1), 'GPU Unlock', 'OK', 'Information')
    Update-Ui
})
$btnGuide.Add_Click({ Start-Process (Join-Path $repoRoot 'TROUBLESHOOTING.md') })
$btnClose.Add_Click({ $form.Close() })

$form.Controls.AddRange(@($label, $hint, $details, $btnCheck, $btnRepair, $btnGuide, $btnClose))

if ($Repair) {
    $null = Get-GpuUnlockStatus -Arguments @('--reapply')
}
Update-Ui
[void]$form.ShowDialog()
