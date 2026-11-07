[CmdletBinding()]
param(
    [switch]$Elevated,
    [switch]$Capture,
    [string]$CapturePath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $repoRoot 'VERSION'
if (Test-Path -LiteralPath $versionPath) {
    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
}
else {
    $version = '2.2.2'
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin) -and -not $Elevated -and -not $Capture) {
    Add-Type -AssemblyName System.Windows.Forms
    try {
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                     '-File', ('"' + $PSCommandPath + '"'), '-Elevated')
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Administrator approval is required to remove the scheduled task and installed files.`n`n" + $_.Exception.Message),
            'Uninstall GPU Unlock', 'OK', 'Error')
    }
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ink = [System.Drawing.Color]::FromArgb(17, 24, 39)
$muted = [System.Drawing.Color]::FromArgb(107, 114, 128)
$accent = [System.Drawing.Color]::FromArgb(185, 28, 28)
$soft = [System.Drawing.Color]::FromArgb(249, 250, 251)
$okColor = [System.Drawing.Color]::FromArgb(21, 128, 61)
$errorColor = [System.Drawing.Color]::FromArgb(185, 28, 28)

$script:pageIndex = 0
$script:running = $false
$script:logPath = ''
$script:process = $null
$script:timer = $null

function New-WizardLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Size = 9, [bool]$Bold = $false, [System.Drawing.Color]$Color = $ink)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $Size, $style)
    $label.ForeColor = $Color
    $label.AutoSize = $false
    return $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Uninstall GPU Unlock'
$form.ClientSize = New-Object System.Drawing.Size(700, 520)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 92
$header.BackColor = $ink
$form.Controls.Add($header)
$header.Controls.Add((New-WizardLabel -Text 'Uninstall GPU Unlock' -X 28 -Y 16 -Width 640 -Height 34 -Size 20 -Bold $true -Color ([System.Drawing.Color]::White)))
$header.Controls.Add((New-WizardLabel -Text ("Version $version   -   removes the Windows app and settings") -X 30 -Y 54 -Width 640 -Height 22 -Color ([System.Drawing.Color]::FromArgb(209, 213, 219))))

$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = 68
$footer.BackColor = $soft
$form.Controls.Add($footer)

$statusLabel = New-WizardLabel -Text '' -X 24 -Y 22 -Width 360 -Height 24 -Color $muted
$footer.Controls.Add($statusLabel)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = 'Uninstall'
$btnNext.Size = New-Object System.Drawing.Size(116, 34)
$btnNext.Location = New-Object System.Drawing.Point(452, 17)
$btnNext.BackColor = $accent
$btnNext.ForeColor = [System.Drawing.Color]::White
$btnNext.FlatStyle = 'Flat'
$btnNext.FlatAppearance.BorderSize = 0
$footer.Controls.Add($btnNext)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Size = New-Object System.Drawing.Size(92, 34)
$btnCancel.Location = New-Object System.Drawing.Point(578, 17)
$btnCancel.Add_Click({ $form.Close() })
$footer.Controls.Add($btnCancel)

$form.AcceptButton = $btnNext
$form.CancelButton = $btnCancel

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($content)
$content.BringToFront()

function New-WizardPage {
    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = 'Fill'
    $page.BackColor = [System.Drawing.Color]::White
    $page.Visible = $false
    $content.Controls.Add($page)
    return $page
}

$installRoot = Join-Path $env:ProgramFiles 'GPU Unlock'
try {
    $registered = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\GpuUnlock' -Name 'InstallDir' -ErrorAction Stop).InstallDir
    if ($registered) { $installRoot = $registered }
}
catch { }
$appScript = Join-Path $installRoot 'app\GpuUnlock.ps1'
$isInstalled = Test-Path -LiteralPath $appScript

$pageConfirm = New-WizardPage
$pageConfirm.Controls.Add((New-WizardLabel -Text 'Remove GPU Unlock' -X 28 -Y 22 -Width 640 -Height 38 -Size 18 -Bold $true))
$pageConfirm.Controls.Add((New-WizardLabel -Text 'This removes the Windows app and its settings. It does not change your GPU firmware or the Windows boot order.' -X 28 -Y 60 -Width 640 -Height 40 -Color $muted))

$listText = if ($isInstalled) {
    "The following will be removed:`r`n  -  GpuUnlockStatus scheduled task`r`n  -  Desktop and Start Menu shortcuts`r`n  -  Apps & Features entry`r`n  -  Registry settings under HKCU\SOFTWARE\GpuUnlock`r`n  -  Installed files in $installRoot`r`n  -  Download cache and installer logs"
}
else {
    "GPU Unlock does not appear to be installed.`r`n`r`nCleanup will still remove any leftover shortcuts, scheduled task, registry settings, cache and installer logs."
}
$pageConfirm.Controls.Add((New-WizardLabel -Text $listText -X 28 -Y 108 -Width 640 -Height 140 -Size 9))

$chkCleanStick = New-Object System.Windows.Forms.CheckBox
$chkCleanStick.Text = 'Also remove generated files from the GPU Unlock USB stick'
$chkCleanStick.Location = New-Object System.Drawing.Point(28, 262)
$chkCleanStick.Size = New-Object System.Drawing.Size(640, 24)
$pageConfirm.Controls.Add($chkCleanStick)

$pageConfirm.Controls.Add((New-WizardLabel -Text 'Optional. This removes the unpacker assets and marker files from a stick that contains GPU Unlock markers. The stick EFI boot loader is left in place; format the stick to erase everything.' -X 48 -Y 288 -Width 620 -Height 48 -Color $muted))

$chkRemoveBackups = New-Object System.Windows.Forms.CheckBox
$chkRemoveBackups.Text = 'Also remove the local backup of the previous stick boot loader'
$chkRemoveBackups.Location = New-Object System.Drawing.Point(28, 344)
$chkRemoveBackups.Size = New-Object System.Drawing.Size(640, 24)
$pageConfirm.Controls.Add($chkRemoveBackups)

$pageConfirm.Controls.Add((New-WizardLabel -Text 'The backup is kept by default so the stick can be restored manually if needed.' -X 48 -Y 370 -Width 620 -Height 30 -Color $muted))

$pageProgress = New-WizardPage
$pageProgress.Controls.Add((New-WizardLabel -Text 'Uninstalling' -X 28 -Y 22 -Width 640 -Height 38 -Size 18 -Bold $true))
$pageProgress.Controls.Add((New-WizardLabel -Text 'Keep this window open while Windows components are removed.' -X 28 -Y 60 -Width 640 -Height 24 -Color $muted))

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(28, 96)
$txtLog.Size = New-Object System.Drawing.Size(640, 280)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.WordWrap = $false
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$txtLog.BackColor = $soft
$txtLog.BorderStyle = 'FixedSingle'
$pageProgress.Controls.Add($txtLog)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(28, 390)
$progressBar.Size = New-Object System.Drawing.Size(640, 18)
$progressBar.Style = 'Marquee'
$progressBar.MarqueeAnimationSpeed = 30
$pageProgress.Controls.Add($progressBar)

$lblProgress = New-WizardLabel -Text 'Starting...' -X 28 -Y 416 -Width 640 -Height 26 -Color $muted
$pageProgress.Controls.Add($lblProgress)

$pageFinish = New-WizardPage
$lblFinishIcon = New-WizardLabel -Text '' -X 28 -Y 18 -Width 60 -Height 60 -Size 34 -Bold $true
$pageFinish.Controls.Add($lblFinishIcon)
$lblFinishTitle = New-WizardLabel -Text '' -X 92 -Y 24 -Width 580 -Height 40 -Size 20 -Bold $true
$pageFinish.Controls.Add($lblFinishTitle)
$lblFinishBody = New-WizardLabel -Text '' -X 28 -Y 96 -Width 640 -Height 220 -Size 10
$pageFinish.Controls.Add($lblFinishBody)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = 'Open log'
$btnOpenLog.Location = New-Object System.Drawing.Point(28, 336)
$btnOpenLog.Size = New-Object System.Drawing.Size(110, 32)
$btnOpenLog.Add_Click({
        if ($script:logPath -and (Test-Path -LiteralPath $script:logPath)) { Start-Process -FilePath $script:logPath }
    })
$pageFinish.Controls.Add($btnOpenLog)

$pages = @($pageConfirm, $pageProgress, $pageFinish)

function Show-WizardPage {
    param([int]$Index)
    for ($i = 0; $i -lt $pages.Count; $i++) { $pages[$i].Visible = ($i -eq $Index) }
    $script:pageIndex = $Index
    Update-Navigation
}

function Update-Navigation {
    $page = $script:pageIndex
    $btnCancel.Visible = (-not $script:running -and $page -lt 2)
    $btnNext.Visible = $true
    if ($page -eq 0) { $btnNext.Text = 'Uninstall'; $btnNext.Enabled = $true }
    elseif ($page -eq 1) { $btnNext.Enabled = $false }
    else { $btnNext.Text = 'Finish'; $btnNext.Enabled = $true }
    if ($script:running) {
        $btnNext.Enabled = $false
        $btnCancel.Visible = $false
    }
}

function Start-Uninstall {
    $script:running = $true
    Show-WizardPage 1
    $txtLog.Text = ''
    $lblProgress.Text = 'Removing GPU Unlock...'

    $uninstallScript = Join-Path $repoRoot 'Uninstall.ps1'
    if (-not (Test-Path -LiteralPath $uninstallScript)) {
        $lblProgress.Text = 'Uninstaller not found.'
        $txtLog.Text = 'Uninstall.ps1 was not found next to this wizard. Reinstall GPU Unlock and try again.'
        Complete-Uninstall 1
        return
    }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $uninstallScript + '"'),
                 '-Remove', '-Force')
    if ($chkCleanStick.Checked) { $argList += '-CleanStick' }
    if ($chkRemoveBackups.Checked) { $argList += '-RemoveBackups' }

    $script:logPath = Join-Path $env:TEMP ('gpu-unlock-uninstall-' + [guid]::NewGuid().ToString('N') + '.log')
    $errPath = Join-Path $env:TEMP ('gpu-unlock-uninstall-' + [guid]::NewGuid().ToString('N') + '.err')
    try {
        $script:process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
            -RedirectStandardOutput $script:logPath -RedirectStandardError $errPath `
            -WindowStyle Hidden -PassThru
    }
    catch {
        $lblProgress.Text = 'Uninstall could not start.'
        $txtLog.Text = $_.Exception.Message
        Complete-Uninstall 1
        return
    }

    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = 600
    $script:timer.Add_Tick({
            if (-not $script:process) { return }
            if (Test-Path -LiteralPath $script:logPath) {
                $tail = @(Get-Content -LiteralPath $script:logPath -Tail 250 -ErrorAction SilentlyContinue)
                if ($tail.Count -gt 0) {
                    $txtLog.Text = ($tail -join "`r`n")
                    $txtLog.SelectionStart = $txtLog.Text.Length
                    $txtLog.ScrollToCaret()
                    $last = @($tail | Where-Object { $_.Trim() }) | Select-Object -Last 1
                    if ($last) { $lblProgress.Text = $last.Trim() }
                }
            }
            if ($script:process.HasExited) {
                $script:timer.Stop()
                Complete-Uninstall $script:process.ExitCode
            }
        })
    $script:timer.Start()
}

function Complete-Uninstall {
    param([int]$ExitCode)
    $script:running = $false
    $script:timer = $null
    $progressBar.Style = 'Blocks'
    $progressBar.Value = 100
    Show-WizardPage 2
    if ($ExitCode -eq 0) {
        $lblFinishIcon.Text = [char]0x2713
        $lblFinishIcon.ForeColor = $okColor
        $lblFinishTitle.Text = 'Uninstall complete'
        $lblFinishTitle.ForeColor = $okColor
        $lblFinishBody.Text = "GPU Unlock was removed.`r`n`r`nThe GPU itself is unchanged and Windows boots normally. If you also removed stick files, the stick's EFI boot loader was left in place; format the stick if you want to erase everything."
        $lblProgress.Text = 'Uninstall completed successfully.'
    }
    else {
        $lblFinishIcon.Text = [char]0x2717
        $lblFinishIcon.ForeColor = $errorColor
        $lblFinishTitle.Text = 'Uninstall did not complete'
        $lblFinishTitle.ForeColor = $errorColor
        $lblFinishBody.Text = "The uninstaller stopped with exit code $ExitCode.`r`n`r`nOpen the log for the exact error, close any open GPU Unlock window, and run UNINSTALL.cmd again as administrator."
        $lblProgress.Text = "Uninstall failed (exit $ExitCode)."
    }
    Update-Navigation
}

$btnNext.Add_Click({
        if ($script:pageIndex -eq 0) { Start-Uninstall }
        elseif ($script:pageIndex -eq 2) { $form.Close() }
    })

$form.Add_FormClosing({
        param($sender, $eventArgs)
        if ($script:running) {
            $eventArgs.Cancel = $true
            [void][System.Windows.Forms.MessageBox]::Show('Uninstall is still running. Wait for it to finish.', 'Uninstall GPU Unlock', 'OK', 'Information')
        }
    })

Show-WizardPage 0

if ($Capture) {
    if (-not $CapturePath) { $CapturePath = Join-Path $repoRoot 'docs\images\uninstall-wizard.png' }
    $captureDir = Split-Path -Parent $CapturePath
    if ($captureDir -and -not (Test-Path -LiteralPath $captureDir)) { New-Item -ItemType Directory -Force -Path $captureDir | Out-Null }
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 300
    $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bitmap.Save($CapturePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $form.Close()
    return
}

[void]$form.ShowDialog()
