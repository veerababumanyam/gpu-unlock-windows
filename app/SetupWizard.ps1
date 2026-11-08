[CmdletBinding()]
param(
    [switch]$Elevated,
    [switch]$Capture,
    [switch]$SelfTest,
    [string]$CapturePath,
    [string]$Cache = (Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $repoRoot 'VERSION'
if (Test-Path -LiteralPath $versionPath) {
    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
}
else {
    $version = '2.2.5'
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Open-GuideFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $candidates = @()
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
    }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    }
    foreach ($edge in $candidates) {
        if (Test-Path -LiteralPath $edge) {
            Start-Process -FilePath $edge -ArgumentList ('"' + $Path + '"') | Out-Null
            return $true
        }
    }
    try {
        Start-Process -FilePath $Path -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

if (-not (Test-IsAdmin) -and -not $Elevated -and -not $Capture -and -not $SelfTest) {
    Add-Type -AssemblyName System.Windows.Forms
    try {
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                     '-File', ('"' + $PSCommandPath + '"'), '-Elevated', '-Cache', ('"' + $Cache + '"'))
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Administrator approval is required to prepare the USB stick and configure Windows.`n`n" + $_.Exception.Message),
            'GPU Unlock Setup', 'OK', 'Error')
    }
    return
}

Import-Module (Join-Path $repoRoot 'Unlock\Unlock.psm1') -Force -DisableNameChecking
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ink = [System.Drawing.Color]::FromArgb(17, 24, 39)
$muted = [System.Drawing.Color]::FromArgb(107, 114, 128)
$accent = [System.Drawing.Color]::FromArgb(37, 99, 235)
$soft = [System.Drawing.Color]::FromArgb(249, 250, 251)
$okColor = [System.Drawing.Color]::FromArgb(21, 128, 61)
$warnColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
$errorColor = [System.Drawing.Color]::FromArgb(185, 28, 28)

$script:pageIndex = 0
$script:systemOk = $false
$script:family = $null
$script:targets = @()
$script:osName = ''
$script:osBuild = 0
$script:selectedVolume = $null
$script:formatStick = $false
$script:running = $false
$script:installStarted = $false
$script:logPath = ''
$script:setupProcess = $null
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
$form.Text = 'GPU Unlock Setup'
$form.ClientSize = New-Object System.Drawing.Size(760, 580)
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

$header.Controls.Add((New-WizardLabel -Text 'GPU Unlock Setup' -X 28 -Y 16 -Width 700 -Height 34 -Size 20 -Bold $true -Color ([System.Drawing.Color]::White)))
$header.Controls.Add((New-WizardLabel -Text ("Version $version   -   Windows 10/11   -   NVIDIA RTX 20/30/40") -X 30 -Y 54 -Width 700 -Height 22 -Size 9 -Color ([System.Drawing.Color]::FromArgb(209, 213, 219))))

$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = 68
$footer.BackColor = $soft
$form.Controls.Add($footer)

$statusLabel = New-WizardLabel -Text '' -X 24 -Y 22 -Width 420 -Height 24 -Size 9 -Color $muted
$footer.Controls.Add($statusLabel)

$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text = 'Back'
$btnBack.Size = New-Object System.Drawing.Size(92, 34)
$btnBack.Location = New-Object System.Drawing.Point(432, 17)
$btnBack.FlatStyle = 'System'
$btnBack.Add_Click({
        if ($script:pageIndex -eq 1) { Show-WizardPage 0 }
        elseif ($script:pageIndex -eq 2) { Show-WizardPage 1 }
        elseif ($script:pageIndex -eq 3) { Show-WizardPage 2 }
    })
$footer.Controls.Add($btnBack)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = 'Next'
$btnNext.Size = New-Object System.Drawing.Size(108, 34)
$btnNext.Location = New-Object System.Drawing.Point(532, 17)
$btnNext.BackColor = $accent
$btnNext.ForeColor = [System.Drawing.Color]::White
$btnNext.FlatStyle = 'Flat'
$btnNext.FlatAppearance.BorderSize = 0
$btnNext.Add_Click({
        switch ($script:pageIndex) {
            0 {
                Show-WizardPage 1
                Update-SystemReport
            }
            1 {
                Show-WizardPage 2
                Update-DriveList
            }
            2 {
                if (-not $script:selectedVolume) { return }
                $script:formatStick = $chkFormat.Checked
                if ($script:formatStick) {
                    $answer = [System.Windows.Forms.MessageBox]::Show(
                        ("Format $($script:selectedVolume.Letter): to FAT32?`n`nThis permanently erases every file on the USB stick."),
                        'Confirm format', 'YesNo', 'Warning')
                    if ($answer -ne 'Yes') { return }
                }
                Show-WizardPage 3
                Update-Summary
            }
            3 {
                if (-not ($chkStick.Checked -or $chkApp.Checked)) { return }
                Show-WizardPage 4
                Start-Setup
            }
            5 {
                $form.Close()
            }
        }
    })
$footer.Controls.Add($btnNext)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Size = New-Object System.Drawing.Size(92, 34)
$btnCancel.Location = New-Object System.Drawing.Point(648, 17)
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

# Page 0: welcome
$pageWelcome = New-WizardPage
$pageWelcome.Controls.Add((New-WizardLabel -Text 'Welcome to GPU Unlock' -X 28 -Y 22 -Width 700 -Height 38 -Size 18 -Bold $true))
$pageWelcome.Controls.Add((New-WizardLabel -Text 'This wizard prepares a USB stick, installs the GPU Unlock status app, and configures Windows so the unlock runs automatically before Windows starts.' -X 28 -Y 66 -Width 700 -Height 58))
$pageWelcome.Controls.Add((New-WizardLabel -Text "What you need:`r`n  -  Windows 10 or 11, 64-bit, with UEFI and Secure Boot disabled`r`n  -  An NVIDIA RTX 20, 30 or 40 series card`r`n  -  An 8 GB or larger USB stick (it will be formatted if it is not FAT32)`r`n  -  Internet access for the first download`r`n`r`nThe setup is automatic after you choose the USB stick. It downloads the pinned upstream release, builds the files for your GPU, verifies every hash, prepares the stick, installs the app, creates the shortcuts, and registers the logon check." -X 28 -Y 136 -Width 700 -Height 200))

$beforeBox = New-Object System.Windows.Forms.Panel
$beforeBox.Location = New-Object System.Drawing.Point(28, 350)
$beforeBox.Size = New-Object System.Drawing.Size(700, 92)
$beforeBox.BackColor = [System.Drawing.Color]::FromArgb(239, 246, 255)
$pageWelcome.Controls.Add($beforeBox)
$beforeBox.Controls.Add((New-WizardLabel -Text 'Before you start' -X 16 -Y 12 -Width 660 -Height 22 -Size 10 -Bold $true -Color $accent))
$beforeBox.Controls.Add((New-WizardLabel -Text 'Close other installers and keep the USB stick connected. The stick must be FAT32 for UEFI boot; this wizard will offer to format it when needed. A backup of an existing EFI\BOOT\BOOTX64.EFI is saved before the stick is changed.' -X 16 -Y 38 -Width 660 -Height 46 -Color $muted))

$pageWelcome.Controls.Add((New-WizardLabel -Text 'The unlock is volatile: it is applied on every restart with the stick connected. Without the stick, Windows boots normally.' -X 28 -Y 458 -Width 700 -Height 40 -Color $muted))

# Page 1: system report
$pageSystem = New-WizardPage
$pageSystem.Controls.Add((New-WizardLabel -Text 'Check your PC' -X 28 -Y 22 -Width 700 -Height 38 -Size 18 -Bold $true))
$pageSystem.Controls.Add((New-WizardLabel -Text 'Setup checks Windows, .NET, firmware, and your NVIDIA card before changing anything.' -X 28 -Y 60 -Width 700 -Height 24 -Color $muted))

$txtReport = New-Object System.Windows.Forms.TextBox
$txtReport.Location = New-Object System.Drawing.Point(28, 98)
$txtReport.Size = New-Object System.Drawing.Size(700, 300)
$txtReport.Multiline = $true
$txtReport.ReadOnly = $true
$txtReport.ScrollBars = 'Vertical'
$txtReport.WordWrap = $false
$txtReport.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtReport.BackColor = $soft
$txtReport.BorderStyle = 'FixedSingle'
$pageSystem.Controls.Add($txtReport)

$btnRecheck = New-Object System.Windows.Forms.Button
$btnRecheck.Text = 'Check again'
$btnRecheck.Location = New-Object System.Drawing.Point(28, 414)
$btnRecheck.Size = New-Object System.Drawing.Size(110, 32)
$btnRecheck.Add_Click({ Update-SystemReport })
$pageSystem.Controls.Add($btnRecheck)

$lblSystemHint = New-WizardLabel -Text 'Errors above must be fixed before setup can continue.' -X 150 -Y 420 -Width 560 -Height 24 -Color $muted
$pageSystem.Controls.Add($lblSystemHint)

$btnBiosGuide = New-Object System.Windows.Forms.Button
$btnBiosGuide.Text = 'Open guide'
$btnBiosGuide.Location = New-Object System.Drawing.Point(28, 456)
$btnBiosGuide.Size = New-Object System.Drawing.Size(130, 30)
$btnBiosGuide.Add_Click({
        $guide = Join-Path $repoRoot 'docs\GPU-Unlock-Guide.pdf'
        if (-not (Test-Path -LiteralPath $guide)) { $guide = Join-Path $repoRoot 'TROUBLESHOOTING.md' }
        if (-not (Open-GuideFile -Path $guide)) {
            [void][System.Windows.Forms.MessageBox]::Show('The GPU Unlock guide was not found.', 'GPU Unlock Setup', 'OK', 'Information')
        }
    })
$pageSystem.Controls.Add($btnBiosGuide)

# Page 2: USB
$pageUsb = New-WizardPage
$pageUsb.Controls.Add((New-WizardLabel -Text 'Choose the USB stick' -X 28 -Y 22 -Width 700 -Height 38 -Size 18 -Bold $true))
$pageUsb.Controls.Add((New-WizardLabel -Text 'The unlock runs from this stick before Windows starts. Only removable drives are listed.' -X 28 -Y 60 -Width 700 -Height 24 -Color $muted))

$cmbDrive = New-Object System.Windows.Forms.ComboBox
$cmbDrive.Location = New-Object System.Drawing.Point(28, 100)
$cmbDrive.Size = New-Object System.Drawing.Size(560, 28)
$cmbDrive.DropDownStyle = 'DropDownList'
$cmbDrive.DisplayMember = 'Display'
$cmbDrive.Add_SelectedIndexChanged({
        $script:selectedVolume = $cmbDrive.SelectedItem
        Update-DriveDetails
        Update-Navigation
    })
$pageUsb.Controls.Add($cmbDrive)

$btnRefreshUsb = New-Object System.Windows.Forms.Button
$btnRefreshUsb.Text = 'Refresh'
$btnRefreshUsb.Location = New-Object System.Drawing.Point(600, 98)
$btnRefreshUsb.Size = New-Object System.Drawing.Size(128, 30)
$btnRefreshUsb.Add_Click({ Update-DriveList })
$pageUsb.Controls.Add($btnRefreshUsb)

$lblDriveInfo = New-WizardLabel -Text '' -X 28 -Y 140 -Width 700 -Height 46 -Size 10
$pageUsb.Controls.Add($lblDriveInfo)

$chkFormat = New-Object System.Windows.Forms.CheckBox
$chkFormat.Text = 'Format this drive to FAT32 (erases all data)'
$chkFormat.Location = New-Object System.Drawing.Point(28, 198)
$chkFormat.Size = New-Object System.Drawing.Size(700, 26)
$pageUsb.Controls.Add($chkFormat)

$lblUsbWarning = New-WizardLabel -Text '' -X 28 -Y 234 -Width 700 -Height 60 -Color $errorColor
$pageUsb.Controls.Add($lblUsbWarning)

$lblUsbHelp = New-WizardLabel -Text 'If the stick is already FAT32, setup keeps its files and backs up EFI\BOOT\BOOTX64.EFI before copying. If it is not FAT32, setup formats it after you confirm. Use a rear USB port and an 8 GB or larger stick.' -X 28 -Y 308 -Width 700 -Height 80 -Color $muted
$pageUsb.Controls.Add($lblUsbHelp)

# Page 3: options
$pageOptions = New-WizardPage
$pageOptions.Controls.Add((New-WizardLabel -Text 'Ready to install' -X 28 -Y 22 -Width 700 -Height 38 -Size 18 -Bold $true))
$pageOptions.Controls.Add((New-WizardLabel -Text 'Everything below is detected automatically. Leave the defaults for a normal install.' -X 28 -Y 60 -Width 700 -Height 24 -Color $muted))

$lblSummary = New-WizardLabel -Text '' -X 28 -Y 94 -Width 700 -Height 110 -Size 9
$pageOptions.Controls.Add($lblSummary)

$chkStick = New-Object System.Windows.Forms.CheckBox
$chkStick.Text = 'Prepare the USB stick (required for the unlock)'
$chkStick.Location = New-Object System.Drawing.Point(28, 216)
$chkStick.Size = New-Object System.Drawing.Size(700, 26)
$chkStick.Checked = $true
$pageOptions.Controls.Add($chkStick)

$chkApp = New-Object System.Windows.Forms.CheckBox
$chkApp.Text = 'Install the GPU Unlock status app'
$chkApp.Location = New-Object System.Drawing.Point(28, 248)
$chkApp.Size = New-Object System.Drawing.Size(700, 26)
$chkApp.Checked = $true
$pageOptions.Controls.Add($chkApp)

$chkDesktop = New-Object System.Windows.Forms.CheckBox
$chkDesktop.Text = 'Create a Desktop shortcut'
$chkDesktop.Location = New-Object System.Drawing.Point(48, 288)
$chkDesktop.Size = New-Object System.Drawing.Size(660, 24)
$chkDesktop.Checked = $true
$pageOptions.Controls.Add($chkDesktop)

$chkStartMenu = New-Object System.Windows.Forms.CheckBox
$chkStartMenu.Text = 'Create a Start Menu shortcut (includes Uninstall GPU Unlock)'
$chkStartMenu.Location = New-Object System.Drawing.Point(48, 318)
$chkStartMenu.Size = New-Object System.Drawing.Size(660, 24)
$chkStartMenu.Checked = $true
$pageOptions.Controls.Add($chkStartMenu)

$chkAutoStart = New-Object System.Windows.Forms.CheckBox
$chkAutoStart.Text = 'Check the unlock at every logon'
$chkAutoStart.Location = New-Object System.Drawing.Point(48, 348)
$chkAutoStart.Size = New-Object System.Drawing.Size(660, 24)
$chkAutoStart.Checked = $true
$pageOptions.Controls.Add($chkAutoStart)

$pageOptions.Controls.Add((New-WizardLabel -Text 'Setup runs elevated and installs no extra runtimes by default (the benchmark''s PyTorch is opt-in). Shortcuts, the scheduled task and registry settings are applied automatically.' -X 28 -Y 392 -Width 700 -Height 52 -Color $muted))

# Page 4: progress
$pageProgress = New-WizardPage
$pageProgress.Controls.Add((New-WizardLabel -Text 'Installing' -X 28 -Y 22 -Width 700 -Height 38 -Size 18 -Bold $true))
$pageProgress.Controls.Add((New-WizardLabel -Text 'Keep this window open. Download and USB work can take several minutes.' -X 28 -Y 60 -Width 700 -Height 24 -Color $muted))

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(28, 96)
$txtLog.Size = New-Object System.Drawing.Size(700, 320)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.WordWrap = $false
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$txtLog.BackColor = $soft
$txtLog.BorderStyle = 'FixedSingle'
$pageProgress.Controls.Add($txtLog)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(28, 430)
$progressBar.Size = New-Object System.Drawing.Size(700, 18)
$progressBar.Style = 'Marquee'
$progressBar.MarqueeAnimationSpeed = 30
$pageProgress.Controls.Add($progressBar)

$lblProgress = New-WizardLabel -Text 'Starting...' -X 28 -Y 456 -Width 700 -Height 26 -Color $muted
$pageProgress.Controls.Add($lblProgress)

# Page 5: finish
$pageFinish = New-WizardPage
$lblFinishIcon = New-WizardLabel -Text '' -X 28 -Y 18 -Width 60 -Height 60 -Size 34 -Bold $true
$pageFinish.Controls.Add($lblFinishIcon)
$lblFinishTitle = New-WizardLabel -Text '' -X 92 -Y 24 -Width 640 -Height 40 -Size 20 -Bold $true
$pageFinish.Controls.Add($lblFinishTitle)
$lblFinishBody = New-WizardLabel -Text '' -X 28 -Y 96 -Width 700 -Height 260 -Size 10
$pageFinish.Controls.Add($lblFinishBody)

$btnOpenGuide = New-Object System.Windows.Forms.Button
$btnOpenGuide.Text = 'Open guide'
$btnOpenGuide.Location = New-Object System.Drawing.Point(28, 380)
$btnOpenGuide.Size = New-Object System.Drawing.Size(110, 32)
$btnOpenGuide.Add_Click({
        $guide = Join-Path $repoRoot 'docs\GPU-Unlock-Guide.pdf'
        if (-not (Test-Path -LiteralPath $guide)) { $guide = Join-Path $repoRoot 'TROUBLESHOOTING.md' }
        if (-not (Open-GuideFile -Path $guide)) {
            [void][System.Windows.Forms.MessageBox]::Show('The GPU Unlock guide was not found.', 'GPU Unlock Setup', 'OK', 'Information')
        }
    })
$pageFinish.Controls.Add($btnOpenGuide)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = 'Open log'
$btnOpenLog.Location = New-Object System.Drawing.Point(148, 380)
$btnOpenLog.Size = New-Object System.Drawing.Size(110, 32)
$btnOpenLog.Add_Click({
        if ($script:logPath -and (Test-Path -LiteralPath $script:logPath)) { Start-Process -FilePath $script:logPath }
    })
$pageFinish.Controls.Add($btnOpenLog)

$btnOpenApp = New-Object System.Windows.Forms.Button
$btnOpenApp.Text = 'Open GPU Unlock'
$btnOpenApp.Location = New-Object System.Drawing.Point(268, 380)
$btnOpenApp.Size = New-Object System.Drawing.Size(130, 32)
$btnOpenApp.Visible = $false
$btnOpenApp.Add_Click({
        $installRoot = Join-Path $env:ProgramFiles 'GPU Unlock'
        try {
            $registered = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\GpuUnlock' -Name 'InstallDir' -ErrorAction Stop).InstallDir
            if ($registered -and (Test-Path -LiteralPath (Join-Path $registered 'app\GpuUnlock.ps1'))) {
                $installRoot = $registered
            }
        }
        catch { }
        $appScript = Join-Path $installRoot 'app\GpuUnlock.ps1'
        if (Test-Path -LiteralPath $appScript) {
            $appArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $appScript + '"'), '-Interactive')
            Start-Process -FilePath 'powershell.exe' -ArgumentList $appArgs -Verb RunAs | Out-Null
        }
    })
$pageFinish.Controls.Add($btnOpenApp)

$pages = @($pageWelcome, $pageSystem, $pageUsb, $pageOptions, $pageProgress, $pageFinish)

function Show-WizardPage {
    param([int]$Index)
    for ($i = 0; $i -lt $pages.Count; $i++) {
        $pages[$i].Visible = ($i -eq $Index)
    }
    $script:pageIndex = $Index
    Update-Navigation
}

function Update-Navigation {
    $page = $script:pageIndex
    $btnBack.Visible = ($page -ge 1 -and $page -le 3)
    $btnBack.Enabled = $btnBack.Visible -and (-not $script:running)
    $btnCancel.Visible = (-not $script:running -and $page -le 3)
    $btnNext.Visible = ($page -le 5)
    switch ($page) {
        0 { $btnNext.Text = 'Next'; $btnNext.Enabled = $true }
        1 { $btnNext.Text = 'Next'; $btnNext.Enabled = $script:systemOk }
        2 { $btnNext.Text = 'Next'; $btnNext.Enabled = ($null -ne $script:selectedVolume) }
        3 {
            $btnNext.Text = 'Install'
            $btnNext.Enabled = ($chkStick.Checked -or $chkApp.Checked)
        }
        4 { $btnNext.Text = 'Install'; $btnNext.Enabled = $false }
        5 { $btnNext.Text = 'Finish'; $btnNext.Enabled = $true }
    }
    if ($script:running) {
        $btnNext.Enabled = $false
        $btnBack.Enabled = $false
        $btnCancel.Visible = $false
    }
}

function Add-ReportLine {
    param([string]$Level, [string]$Name, [string]$Detail)
    $tag = switch ($Level) {
        'ok' { '[OK]   ' }
        'warn' { '[WARN] ' }
        'error' { '[ERROR]' }
        default { '[INFO] ' }
    }
    return ('{0} {1,-14} {2}' -f $tag, $Name, $Detail)
}

function Update-SystemReport {
    $lines = New-Object System.Collections.Generic.List[string]
    $hasError = $false
    $hasWarning = $false

    $os = [Environment]::OSVersion.Version
    $script:osBuild = $os.Build
    $script:osName = if ($os.Build -ge 22000) { 'Windows 11' } elseif ($os.Build -ge 10240) { 'Windows 10' } else { 'Unsupported Windows' }
    if ($os.Build -ge 10240 -and [Environment]::Is64BitOperatingSystem) {
        $lines.Add((Add-ReportLine 'ok' 'Windows' ("$($script:osName), build $($os.Build), 64-bit")))
    }
    else {
        $lines.Add((Add-ReportLine 'error' 'Windows' ("$($script:osName), build $($os.Build) - Windows 10/11 64-bit is required")))
        $hasError = $true
    }

    if (Test-IsAdmin) {
        $lines.Add((Add-ReportLine 'ok' 'Administrator' 'elevated'))
    }
    else {
        $lines.Add((Add-ReportLine 'error' 'Administrator' 'not elevated'))
        $hasError = $true
    }

    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion -ge [version]'5.1') {
        $lines.Add((Add-ReportLine 'ok' 'PowerShell' $psVersion.ToString()))
    }
    else {
        $lines.Add((Add-ReportLine 'error' 'PowerShell' ("$psVersion - 5.1 or later is required")))
        $hasError = $true
    }

    $ndp = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    $netRelease = 0
    if ($ndp -and $ndp.Release) { $netRelease = [int]$ndp.Release }
    if ($netRelease -ge 461808) {
        $netName = if ($netRelease -ge 528040) { '4.8 or later' } else { '4.7.2 or later' }
        $lines.Add((Add-ReportLine 'ok' '.NET Framework' $netName))
    }
    else {
        $lines.Add((Add-ReportLine 'error' '.NET Framework' '4.7.2 or later is required (https://dotnet.microsoft.com/download/dotnet-framework)'))
        $hasError = $true
    }

    try {
        $environment = Test-UnlockEnvironment
        foreach ($check in $environment.Checks) {
            $lines.Add((Add-ReportLine $check.Level $check.Name $check.Detail))
            if ($check.Level -eq 'error') { $hasError = $true }
            if ($check.Level -eq 'warn') { $hasWarning = $true }
        }
    }
    catch {
        $lines.Add((Add-ReportLine 'error' 'Firmware' $_.Exception.Message))
        $hasError = $true
    }

    $script:targets = @()
    $script:family = $null
    try {
        $script:targets = @(Get-UnlockTargets)
        foreach ($gpu in $script:targets) {
            $lines.Add((Add-ReportLine 'ok' 'NVIDIA GPU' ("$($gpu.Name), $($gpu.BusId), driver $($gpu.Driver)")))
        }
        $families = @(Get-UnlockFamilyFromTargets -Targets $script:targets)
        if ($families.Count -eq 0) {
            $lines.Add((Add-ReportLine 'error' 'GPU family' 'no supported RTX 20/30/40 card detected'))
            $hasError = $true
        }
        elseif ($families.Count -eq 1) {
            $script:family = $families[0]
            $lines.Add((Add-ReportLine 'ok' 'GPU family' $script:family))
        }
        else {
            $script:family = 'all'
            $lines.Add((Add-ReportLine 'warn' 'GPU family' 'multiple generations detected - building all families'))
            $hasWarning = $true
        }
    }
    catch {
        $lines.Add((Add-ReportLine 'error' 'NVIDIA GPU' $_.Exception.Message))
        $hasError = $true
    }

    $txtReport.Text = ($lines -join "`r`n")
    $script:systemOk = -not $hasError
    if ($hasError) {
        $lblSystemHint.Text = 'Fix the errors above, then click Check again.'
        $lblSystemHint.ForeColor = $errorColor
    }
    elseif ($hasWarning) {
        $lblSystemHint.Text = 'Warnings are safe to continue; review them before installing.'
        $lblSystemHint.ForeColor = $warnColor
    }
    else {
        $lblSystemHint.Text = 'Everything needed is available. Click Next.'
        $lblSystemHint.ForeColor = $okColor
    }
    Update-Navigation
}

function Get-RemovableDrives {
    return @(Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } |
        Sort-Object DriveLetter)
}

function Update-DriveList {
    $drives = @(Get-RemovableDrives)
    $cmbDrive.Items.Clear()
    foreach ($drive in $drives) {
        $size = [math]::Round($drive.Size / 1GB, 1)
        $label = if ($drive.FileSystemLabel) { $drive.FileSystemLabel } else { '(no label)' }
        $fs = if ($drive.FileSystem) { $drive.FileSystem } else { 'unformatted' }
        $item = [pscustomobject]@{
            Display    = ("{0}:  {1}  -  {2}  -  {3} GB" -f $drive.DriveLetter, $label, $fs, $size)
            Letter     = $drive.DriveLetter
            Label      = $label
            FileSystem = $fs
            SizeGB     = $size
        }
        [void]$cmbDrive.Items.Add($item)
    }
    if ($cmbDrive.Items.Count -gt 0) {
        $cmbDrive.SelectedIndex = 0
        $cmbDrive.Enabled = $true
    }
    else {
        $script:selectedVolume = $null
        $cmbDrive.Enabled = $false
        $lblDriveInfo.Text = 'No removable USB drive found. Insert a stick and click Refresh.'
        $lblDriveInfo.ForeColor = $errorColor
        $lblUsbWarning.Text = ''
    }
    Update-Navigation
}

function Update-DriveDetails {
    $drive = $cmbDrive.SelectedItem
    if (-not $drive) { return }
    $lblDriveInfo.Text = ("{0}:  {1}  -  {2}  -  {3} GB" -f $drive.Letter, $drive.Label, $drive.FileSystem, $drive.SizeGB)
    $lblDriveInfo.ForeColor = $ink
    $isFat32 = ($drive.FileSystem -eq 'FAT32')
    $chkFormat.Checked = -not $isFat32
    $chkFormat.Enabled = $false
    if ($isFat32) {
        $lblUsbWarning.Text = 'The stick is already FAT32. Existing files are kept; the existing EFI boot loader is backed up first.'
        $lblUsbWarning.ForeColor = $muted
    }
    else {
        $lblUsbWarning.Text = 'This stick is not FAT32. It will be formatted after you confirm - EVERY FILE ON IT WILL BE ERASED.'
        $lblUsbWarning.ForeColor = $errorColor
    }
}

function Update-OptionState {
    $chkDesktop.Enabled = $chkApp.Checked
    $chkStartMenu.Enabled = $chkApp.Checked
    $chkAutoStart.Enabled = $chkApp.Checked
    Update-Navigation
}

function Update-Summary {
    $gpuText = ($script:targets | ForEach-Object { "$($_.Name) ($($_.BusId))" }) -join '; '
    if (-not $gpuText) { $gpuText = 'not detected' }
    $drive = $script:selectedVolume
    $driveText = if ($drive) { "$($drive.Letter): $($drive.FileSystem), $($drive.SizeGB) GB" } else { 'not selected' }
    if ($drive -and $script:formatStick) { $driveText += ' - will be formatted to FAT32' }
    $appText = if ($chkApp.Checked) { 'install status app' } else { 'do not install app' }
    $lblSummary.Text = @(
        "Windows:  $($script:osName) (build $($script:osBuild), 64-bit)",
        "Graphics: $gpuText",
        "Unlock:   family $($script:family) - all supported families are built when mixed",
        "USB:      $driveText",
        "App:      $appText"
    ) -join "`r`n"
}

function Start-Setup {
    $script:running = $true
    $script:installStarted = $true
    Update-Navigation
    $progressBar.Style = 'Marquee'
    $lblProgress.Text = 'Starting setup...'
    $txtLog.Text = ''

    $setupPath = Join-Path $repoRoot 'setup.ps1'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $setupPath + '"'),
                 '-SkipElevation', '-Silent', '-Family', 'localhost')
    if ($chkStick.Checked) {
        $argList += '-InstallStick'
        $argList += '-Stick'
        $argList += $script:selectedVolume.Letter
        if ($script:formatStick) { $argList += '-FormatStick'; $argList += '-ConfirmFormat' }
    }
    if ($chkApp.Checked) {
        $argList += '-InstallApp'
        if (-not $chkDesktop.Checked) { $argList += '-NoDesktop' }
        if (-not $chkStartMenu.Checked) { $argList += '-NoStartMenu' }
        if (-not $chkAutoStart.Checked) { $argList += '-NoAutoStart' }
    }
    if ($Cache) { $argList += '-Cache'; $argList += ('"' + $Cache + '"') }

    $script:logPath = Join-Path $env:TEMP ('gpu-unlock-setup-' + [guid]::NewGuid().ToString('N') + '.log')
    $errPath = Join-Path $env:TEMP ('gpu-unlock-setup-' + [guid]::NewGuid().ToString('N') + '.err')
    try {
        $script:setupProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
            -RedirectStandardOutput $script:logPath -RedirectStandardError $errPath `
            -WindowStyle Hidden -PassThru
    }
    catch {
        $lblProgress.Text = 'Setup could not start.'
        $txtLog.Text = $_.Exception.Message
        Complete-Setup 1
        return
    }

    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = 600
    $script:timer.Add_Tick({
            if (-not $script:setupProcess) { return }
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
            if ($script:setupProcess.HasExited) {
                $script:timer.Stop()
                Complete-Setup $script:setupProcess.ExitCode
            }
        })
    $script:timer.Start()
}

function Complete-Setup {
    param([int]$ExitCode)
    $script:running = $false
    $script:timer = $null
    $progressBar.Style = 'Blocks'
    $progressBar.Value = 100
    Show-WizardPage 5
    if (Test-Path -LiteralPath $script:logPath) {
        $tail = @(Get-Content -LiteralPath $script:logPath -Tail 250 -ErrorAction SilentlyContinue)
        $txtLog.Text = ($tail -join "`r`n")
    }
    if ($ExitCode -eq 0) {
        $lblFinishIcon.Text = [char]0x2713
        $lblFinishIcon.ForeColor = $okColor
        $lblFinishTitle.Text = 'Setup complete'
        $lblFinishTitle.ForeColor = $okColor
        $body = "The USB stick and Windows app are ready.`r`n`r`n1. Keep the USB stick connected.`r`n2. Restart and enter BIOS/UEFI (Del or F2).`r`n3. Set the 'UEFI: ...' USB entry as Boot Option #1.`r`n4. Save and exit (F10). Windows starts with GPU Unlock active.`r`n`r`nOpen 'GPU Unlock' from the Desktop or Start Menu to see the status. Without the stick, Windows boots normally."
        if (-not $chkStick.Checked) {
            $body = "The Windows app is installed.`r`n`r`nInsert a prepared GPU Unlock USB stick, restart, and use the app to check the status. Without the stick, Windows boots normally."
        }
        if (-not $chkApp.Checked) {
            $body = "The USB stick is ready.`r`n`r`n1. Keep the stick connected.`r`n2. Restart and enter BIOS/UEFI (Del or F2).`r`n3. Set the 'UEFI: ...' USB entry as Boot Option #1.`r`n4. Save and exit (F10). Windows starts with GPU Unlock active.`r`n`r`nThe status app was not installed."
        }
        $lblFinishBody.Text = $body
        $btnOpenApp.Visible = $chkApp.Checked
        $lblProgress.Text = 'Setup completed successfully.'
    }
    else {
        $lblFinishIcon.Text = [char]0x2717
        $lblFinishIcon.ForeColor = $errorColor
        $lblFinishTitle.Text = 'Setup did not complete'
        $lblFinishTitle.ForeColor = $errorColor
        $lblFinishBody.Text = "Setup stopped with exit code $ExitCode.`r`n`r`nOpen the log for the exact error. Fix the error and run SETUP.cmd again. Nothing is changed on the stick until the download and verification steps pass."
        $btnOpenApp.Visible = $false
        $lblProgress.Text = "Setup failed (exit $ExitCode)."
    }
    Update-Navigation
}

$chkStick.Add_CheckedChanged({ Update-OptionState })
$chkApp.Add_CheckedChanged({ Update-OptionState })

$form.Add_FormClosing({
        param($sender, $eventArgs)
        if ($script:running) {
            $eventArgs.Cancel = $true
            [void][System.Windows.Forms.MessageBox]::Show('Setup is still running. Wait for it to finish.', 'GPU Unlock Setup', 'OK', 'Information')
        }
    })

Show-WizardPage 0
Update-OptionState
Update-DriveList

if ($SelfTest) {
    Update-SystemReport
    Write-Output $txtReport.Text
    Write-Output ''
    Write-Output ("System OK: " + $script:systemOk)
    Write-Output ("Detected family: " + $script:family)
    return
}

if ($Capture) {
    if (-not $CapturePath) { $CapturePath = Join-Path $repoRoot 'docs\images\setup-wizard.png' }
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
