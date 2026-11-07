Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UnlockConfig {
    $path = Join-Path $PSScriptRoot 'unlock.config.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing config: $path" }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Convert-UnlockBusId {
    param([Parameter(Mandatory)][string]$BusId)
    $b = $BusId.Trim().ToLower()
    if ($b -match '^[0-9a-f]{8}:(.+)$') { return '0000:' + $Matches[1] }
    if ($b -match '^[0-9a-f]{4}:(.+)$') { return $b }
    if ($b -match '^[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]$') { return '0000:' + $b }
    return $b
}

function Get-UnlockTargets {
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) { throw 'nvidia-smi not found; install the NVIDIA driver.' }
    $lines = @(& $smi.Source --query-gpu=index,name,pci.bus_id,driver_version --format=csv,noheader)
    if ($LASTEXITCODE -ne 0) { throw 'nvidia-smi query failed.' }
    $out = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $p = $line -split '\s*,\s*'
        if ($p.Count -ge 4) {
            $out += [pscustomobject]@{
                Index  = [int]$p[0]
                Name   = $p[1]
                BusId  = Convert-UnlockBusId $p[2]
                Driver = $p[3]
            }
        }
    }
    if ($out.Count -eq 0) { throw 'No NVIDIA GPU reported by nvidia-smi.' }
    $out
}

function Get-UnlockFamilyFromTargets {
    param([Parameter(Mandatory)][object[]]$Targets)
    $fams = @()
    foreach ($t in $Targets) {
        if ($t.Name -match 'RTX\s*40') { $fams += 'ad102' }
        elseif ($t.Name -match 'RTX\s*30') { $fams += 'ga102' }
        elseif ($t.Name -match 'RTX\s*20|GTX\s*16') { $fams += 'tu10x' }
    }
    @($fams | Select-Object -Unique)
}

function Test-UnlockEnvironment {
    $checks = @()

    $sbKey = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
    $uefi = $null -ne $sbKey
    if ($uefi) {
        $checks += [pscustomobject]@{ Name = 'UEFI'; Level = 'ok'; Detail = 'UEFI firmware' }
    }
    else {
        $checks += [pscustomobject]@{ Name = 'UEFI'; Level = 'error'; Detail = 'Legacy/BIOS boot - the unlock is UEFI-only.' }
    }

    if ($uefi) {
        $sb = [int]$sbKey.UEFISecureBootEnabled
        if ($sb -eq 0) {
            $checks += [pscustomobject]@{ Name = 'Secure Boot'; Level = 'ok'; Detail = 'disabled' }
        }
        else {
            $checks += [pscustomobject]@{ Name = 'Secure Boot'; Level = 'error'; Detail = 'enabled - disable it in firmware and verify Confirm-SecureBootUEFI returns False.' }
        }
    }
    else {
        $checks += [pscustomobject]@{ Name = 'Secure Boot'; Level = 'warn'; Detail = 'unknown (non-UEFI)' }
    }

    $hb = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue
    if (($null -ne $hb) -and ([int]$hb.HiberbootEnabled -eq 1)) {
        $checks += [pscustomobject]@{ Name = 'Fast Startup'; Level = 'warn'; Detail = 'enabled - run elevated: powercfg /h off' }
    }
    else {
        $checks += [pscustomobject]@{ Name = 'Fast Startup'; Level = 'ok'; Detail = 'disabled' }
    }

    $bl = $null
    try { $bl = @(Get-BitLockerVolume -ErrorAction Stop) } catch { $bl = $null }
    if ($null -eq $bl) {
        $checks += [pscustomobject]@{ Name = 'BitLocker'; Level = 'ok'; Detail = 'not present' }
    }
    else {
        $on = @($bl | Where-Object { $_.ProtectionStatus -eq 'On' })
        if ($on.Count -gt 0) {
            $checks += [pscustomobject]@{ Name = 'BitLocker'; Level = 'warn'; Detail = 'protection On - keep the recovery key before boot changes' }
        }
        else {
            $checks += [pscustomobject]@{ Name = 'BitLocker'; Level = 'ok'; Detail = 'off' }
        }
    }

    $errors = @($checks | Where-Object { $_.Level -eq 'error' })
    [pscustomobject]@{ Checks = $checks; Ok = ($errors.Count -eq 0) }
}

function Get-UnlockRelease {
    param([Parameter(Mandatory)][string]$Cache)

    $cfg = Get-UnlockConfig
    $tag = [string]$cfg.release
    $repo = [string]$cfg.repository
    New-Item -ItemType Directory -Force -Path $Cache | Out-Null

    $relDir = Join-Path $Cache ("release\" + $tag)
    $sumsPath = Join-Path $Cache 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $sumsPath)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/releases/download/$tag/SHA256SUMS.txt" -OutFile $sumsPath
    }

    $sums = @{}
    foreach ($line in Get-Content -LiteralPath $sumsPath) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') { $sums[$Matches[2]] = $Matches[1].ToLower() }
    }

    if (-not (Test-Path -LiteralPath $relDir)) {
        $zipName = "nv-uefi-unlocker-$tag.zip"
        $zipPath = Join-Path $Cache $zipName
        if (-not (Test-Path -LiteralPath $zipPath)) {
            Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/releases/download/$tag/$zipName" -OutFile $zipPath
        }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $relDir -Force
    }

    $verified = 0
    foreach ($name in $sums.Keys) {
        $p = Join-Path $relDir $name
        if (Test-Path -LiteralPath $p) {
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
            if ($h -ne $sums[$name]) { throw "Release integrity failure: $name" }
            $verified++
        }
    }
    if ($verified -lt 8) { throw "Release verification incomplete ($verified files)." }

    $ssdiag = Join-Path $Cache 'ssdiag.exe'
    if (-not (Test-Path -LiteralPath $ssdiag)) {
        $asset = [string]$cfg.ssdiagAsset
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/releases/download/$tag/$asset" -OutFile $ssdiag
        $want = $sums['ssdiag-x86_64-windows.exe']
        if ($want) {
            $h = (Get-FileHash -LiteralPath $ssdiag -Algorithm SHA256).Hash.ToLower()
            if ($h -ne $want) { throw 'Release integrity failure: ssdiag' }
        }
    }

    [pscustomobject]@{
        Dir    = $relDir
        Maker  = (Join-Path $relDir 'make-usbroot.ps1')
        Ssdiag = $ssdiag
        Tag    = $tag
    }
}

function Invoke-UnlockMaker {
    param(
        [Parameter(Mandatory)][string]$Maker,
        [Parameter(Mandatory)][string]$OutDir,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$Family
    )
    if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

    $makerArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Maker,
                   '-Family', $Family, '-Out', $OutDir, '-Work', $WorkDir)
    & powershell.exe @makerArgs
    if ($LASTEXITCODE -ne 0) { throw "make-usbroot.ps1 failed (exit $LASTEXITCODE)." }
}

function Test-UnlockStaging {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Family
    )
    $cfg = Get-UnlockConfig
    if ($Family -eq 'all') {
        $expected = @( (@($cfg.expectedFiles.ad102) + @($cfg.expectedFiles.ga102) + @($cfg.expectedFiles.tu10x) + @($cfg.efiPath)) | Select-Object -Unique )
    }
    else {
        $expected = @($cfg.expectedFiles.$Family) + @($cfg.efiPath)
    }

    $missing = @()
    foreach ($rel in $expected) {
        $p = Join-Path $Root ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p)) { $missing += $rel }
    }
    [pscustomobject]@{ Ok = ($missing.Count -eq 0); Missing = $missing; Expected = $expected }
}

function Set-UnlockMarkers {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$Unattended,
        [switch]$Quiet,
        [int]$Countdown = 5
    )
    $autoPath = Join-Path $Root 'i_know_what_i_am_doing.txt'
    $quietPath = Join-Path $Root 'tx-quiet.txt'

    if ($Unattended) {
        if ($Countdown -lt 1 -or $Countdown -gt 30) { throw 'Countdown must be between 1 and 30.' }
        Set-Content -LiteralPath $autoPath -Value ([string]$Countdown) -Encoding Ascii -Force
    }
    elseif (Test-Path -LiteralPath $autoPath) {
        Remove-Item -LiteralPath $autoPath -Force
    }

    if ($Quiet) {
        New-Item -ItemType File -Path $quietPath -Force | Out-Null
    }
    elseif (Test-Path -LiteralPath $quietPath) {
        Remove-Item -LiteralPath $quietPath -Force
    }

    $autoOn = Test-Path -LiteralPath $autoPath
    [pscustomobject]@{
        AutoRun   = $autoOn
        Quiet     = (Test-Path -LiteralPath $quietPath)
        Countdown = $(if ($autoOn) { [int]((Get-Content -LiteralPath $autoPath -Raw).Trim()) } else { 0 })
    }
}

function Get-UnlockStick {
    param([string]$DriveLetter)
    $vols = @(Get-Volume | Where-Object { $_.DriveType -eq 'Removable' })

    if ($DriveLetter) {
        $letter = $DriveLetter.TrimEnd(':').ToUpper()
        $v = $vols | Where-Object { $_.DriveLetter -eq $letter } | Select-Object -First 1
        if (-not $v) { throw "Removable volume ${letter}: not found." }
        return $v
    }
    if ($vols.Count -eq 0) { throw 'No removable volume detected. Insert a FAT32 USB stick or pass -Stick X:.' }
    if ($vols.Count -gt 1) {
        $letters = ($vols | ForEach-Object { $_.DriveLetter }) -join ', '
        throw "Multiple removable volumes ($letters); pass -Stick X:."
    }
    $vols[0]
}

function Install-UnlockStick {
    param(
        [Parameter(Mandatory)][string]$Staging,
        [Parameter(Mandatory)][string]$Family,
        [string]$DriveLetter,
        [switch]$FormatStick,
        [switch]$ConfirmFormat,
        [Parameter(Mandatory)][string]$BackupRoot
    )
    $cfg = Get-UnlockConfig
    $vol = Get-UnlockStick -DriveLetter $DriveLetter
    $root = "$($vol.DriveLetter):\"

    if ($vol.FileSystem -ne 'FAT32') {
        if (-not $FormatStick) {
            throw "Stick $root is $($vol.FileSystem); UEFI needs FAT32. Use another stick, or -FormatStick -ConfirmFormat (erases it)."
        }
        if (-not $ConfirmFormat) { throw 'Refusing to format without -ConfirmFormat.' }
        Format-Volume -DriveLetter $vol.DriveLetter -FileSystem FAT32 -NewFileSystemLabel 'GPU-UNLOCK' -Confirm:$false -Force | Out-Null
    }

    $check = Test-UnlockStaging -Root $Staging -Family $Family
    if (-not $check.Ok) { throw ('Staging incomplete: ' + ($check.Missing -join ', ')) }

    $efiRel = ($cfg.efiPath -replace '/', '\')
    $existing = Join-Path $root $efiRel
    $backed = $false
    if (Test-Path -LiteralPath $existing) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $bak = Join-Path $BackupRoot $stamp
        New-Item -ItemType Directory -Force -Path $bak | Out-Null
        Copy-Item -LiteralPath $existing -Destination (Join-Path $bak 'BOOTX64.EFI') -Force
        $backed = $true
    }

    foreach ($rel in $check.Expected) {
        $relWin = $rel -replace '/', '\'
        $dest = Join-Path $root $relWin
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item -LiteralPath (Join-Path $Staging $relWin) -Destination $dest -Force
    }

    $sums = Join-Path $Staging 'SHA256SUMS.txt'
    if (Test-Path -LiteralPath $sums) { Copy-Item -LiteralPath $sums -Destination (Join-Path $root 'SHA256SUMS.txt') -Force }

    $bad = @()
    foreach ($rel in $check.Expected) {
        $relWin = $rel -replace '/', '\'
        $a = (Get-FileHash -LiteralPath (Join-Path $Staging $relWin) -Algorithm SHA256).Hash
        $b = (Get-FileHash -LiteralPath (Join-Path $root $relWin) -Algorithm SHA256).Hash
        if ($a -ne $b) { $bad += $rel }
    }

    [pscustomobject]@{ Root = $root; Volume = $vol; Ok = ($bad.Count -eq 0); Bad = $bad; BackedUp = $backed }
}

function ConvertFrom-SsdiagOutput {
    param([Parameter(Mandatory)][string]$Text)

    $ss0 = [regex]::Match($Text, '(?i)SS0\s*[=:]\s*(0x[0-9a-f]+)').Groups[1].Value
    $ss1 = [regex]::Match($Text, '(?i)SS1\s*[=:]\s*(0x[0-9a-f]+)').Groups[1].Value

    $ok = $false
    if ($ss0 -and $ss1) {
        $target = [Convert]::ToUInt32('88888888', 16)
        $ok = ([Convert]::ToUInt32($ss0.Substring(2), 16) -eq $target) -and
              (([Convert]::ToUInt32($ss1.Substring(2), 16) -band 0xF) -eq 0x8)
    }
    [pscustomobject]@{ Ok = $ok; Ss0 = $ss0; Ss1 = $ss1; Raw = $Text }
}

function Invoke-UnlockSsdiag {
    param(
        [Parameter(Mandatory)][string]$SsdiagPath,
        [string[]]$Arguments = @()
    )

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'ssdiag requires an elevated PowerShell (Run as administrator).'
    }

    $text = (& $SsdiagPath @Arguments 2>&1 | Out-String)
    ConvertFrom-SsdiagOutput -Text $text
}

Export-ModuleMember -Function *
