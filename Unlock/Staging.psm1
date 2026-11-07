Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-UnlockStaging {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateScript({ $_ -in ((Get-ValidFamilies) + 'all') })]
        [string]$Family
    )
    $cfg = Get-UnlockConfig
    if ($Family -eq 'all') {
        $expected = @( (@($cfg.expectedFiles.ad102) + @($cfg.expectedFiles.ga102) + @($cfg.expectedFiles.tu10x) + @($global:EfiPath)) | Select-Object -Unique )
    }
    else {
        $expected = @($cfg.expectedFiles.$Family) + @($global:EfiPath)
    }

    $missing = @()
    foreach ($rel in $expected) {
        $p = Join-Path $Root ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p)) { $missing += $rel }
    }
    [pscustomobject]@{ Ok = ($missing.Count -eq 0); Missing = $missing; Expected = $expected }
}

function Install-UnlockStick {
    param(
        [Parameter(Mandatory)][string]$Staging,
        [Parameter(Mandatory)][ValidateScript({ $_ -in ((Get-ValidFamilies) + 'all') })]
        [string]$Family,
        [string]$DriveLetter,
        [switch]$FormatStick,
        [switch]$ConfirmFormat,
        [switch]$Interactive,
        [Parameter(Mandatory)][string]$BackupRoot,
        [switch]$WhatIf
    )
    $cfg = Get-UnlockConfig
    $vol = Get-UnlockStick -DriveLetter $DriveLetter -Interactive:$Interactive
    $root = "$($vol.DriveLetter):\"

    # Validate the generated files before changing or formatting the stick.
    $check = Test-UnlockStaging -Root $Staging -Family $Family
    if (-not $check.Ok) { throw ('Staging incomplete: ' + ($check.Missing -join ', ')) }

    # Preserve the existing boot loader before a format could erase it.
    $efiRel = ($cfg.efiPath -replace '/', '\')
    $existing = Join-Path $root $efiRel
    $backed = $false
    if (Test-Path -LiteralPath $existing) {
        if ($WhatIf) {
            Write-Host "[WhatIf] Would backup existing $efiRel to $BackupRoot"
        } else {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $bak = Join-Path $BackupRoot $stamp
            New-Item -ItemType Directory -Force -Path $bak | Out-Null
            Copy-Item -LiteralPath $existing -Destination (Join-Path $bak 'BOOTX64.EFI') -Force
            $backed = $true
            Write-Host "Backed up existing $efiRel to $bak" -ForegroundColor Cyan
        }
    }

    $formatted = $false
    if ($vol.FileSystem -ne 'FAT32') {
        if (-not $FormatStick) {
            if ($Interactive) {
                Write-Host "Stick $root is $($vol.FileSystem); UEFI needs FAT32." -ForegroundColor Yellow
                $confirm = Read-Host "Format to FAT32? This will ERASE all data on the stick (y/N)"
                if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                    $FormatStick = $true
                    $ConfirmFormat = $true
                }
                else {
                    throw "Aborted: stick must be FAT32 for UEFI boot."
                }
            }
            else {
                throw "Stick $root is $($vol.FileSystem); UEFI needs FAT32. Use another stick, or -FormatStick -ConfirmFormat (erases it)."
            }
        }
        if (-not $ConfirmFormat) { throw 'Refusing to format without -ConfirmFormat.' }
        if ($WhatIf) {
            $formatted = $true
            Write-Host "[WhatIf] Would format $root to FAT32"
        } else {
            Format-Volume -DriveLetter $vol.DriveLetter -FileSystem FAT32 -NewFileSystemLabel $global:StickLabel -Confirm:$false -Force | Out-Null
            $formatted = $true
            Write-Host "Formatted $root to FAT32." -ForegroundColor Green
        }
    }

    $totalFiles = $check.Expected.Count
    $currentFile = 0
    foreach ($rel in $check.Expected) {
        $currentFile++
        $relWin = $rel -replace '/', '\'
        $dest = Join-Path $root $relWin
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if ($WhatIf) {
            Write-Host "[WhatIf] Would copy $rel to $dest"
        } else {
            Write-Progress -Activity "Copying files to USB stick" -Status "Copying $rel ($currentFile/$totalFiles)" -PercentComplete ([int]($currentFile * 100 / $totalFiles))
            Copy-Item -LiteralPath (Join-Path $Staging $relWin) -Destination $dest -Force
        }
    }
    if (-not $WhatIf) { Write-Progress -Activity "Copying files to USB stick" -Status "Completed" -PercentComplete 100 -Completed }

    $sums = Join-Path $Staging 'SHA256SUMS.txt'
    if (Test-Path -LiteralPath $sums) { 
        if ($WhatIf) {
            Write-Host "[WhatIf] Would copy SHA256SUMS.txt to stick"
        } else {
            Copy-Item -LiteralPath $sums -Destination (Join-Path $root 'SHA256SUMS.txt') -Force 
        }
    }

    $gate = Join-Path $Staging 'gsp-gate.txt'
    if (Test-Path -LiteralPath $gate) {
        if ($WhatIf) {
            Write-Host "[WhatIf] Would copy gsp-gate.txt to stick"
        } else {
            Copy-Item -LiteralPath $gate -Destination (Join-Path $root 'gsp-gate.txt') -Force
        }
    }

    $bad = @()
    if (-not $WhatIf) {
        foreach ($rel in $check.Expected) {
            $relWin = $rel -replace '/', '\'
            $a = (Get-FileHash -LiteralPath (Join-Path $Staging $relWin) -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath (Join-Path $root $relWin) -Algorithm SHA256).Hash
            if ($a -ne $b) { $bad += $rel }
        }
        if (Test-Path -LiteralPath $gate) {
            $a = (Get-FileHash -LiteralPath $gate -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath (Join-Path $root 'gsp-gate.txt') -Algorithm SHA256).Hash
            if ($a -ne $b) { $bad += 'gsp-gate.txt' }
        }
    }

    [pscustomobject]@{ Root = $root; Volume = $vol; Ok = ($bad.Count -eq 0); Bad = $bad; BackedUp = $backed; Formatted = $formatted }
}

Export-ModuleMember -Function Test-UnlockStaging, Install-UnlockStick