Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UnlockRelease {
    param(
        [Parameter(Mandatory)][string]$Cache,
        [switch]$WhatIf
    )

    $cfg = Get-UnlockConfig
    $tag = [string]$cfg.release
    $repo = [string]$cfg.repository
    try {
        if (-not $WhatIf) { New-Item -ItemType Directory -Force -Path $Cache | Out-Null }
    }
    catch {
        throw "Failed to create cache directory '$Cache': $($_.Exception.Message)"
    }

    $relDir = Join-Path $Cache ("release\" + $tag)
    $sumsPath = Join-Path $Cache 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $sumsPath)) {
        try {
            if ($WhatIf) {
                Write-Host "[WhatIf] Would download SHA256SUMS.txt from https://github.com/$repo/releases/download/$tag/SHA256SUMS.txt"
            } else {
                Write-Progress -Activity "Downloading release metadata" -Status "SHA256SUMS.txt" -PercentComplete 10
                Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/releases/download/$tag/SHA256SUMS.txt" -OutFile $sumsPath
                Write-Progress -Activity "Downloading release metadata" -Status "SHA256SUMS.txt" -PercentComplete 20 -Completed
            }
        }
        catch {
            throw "Failed to download SHA256SUMS.txt: $($_.Exception.Message)"
        }
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
            try {
                if ($WhatIf) {
                    Write-Host "[WhatIf] Would download $zipName from https://github.com/$repo/releases/download/$tag/$zipName"
                } else {
                    Write-Progress -Activity "Downloading release archive" -Status "$zipName" -PercentComplete 30
                    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/releases/download/$tag/$zipName" -OutFile $zipPath
                    Write-Progress -Activity "Downloading release archive" -Status "$zipName" -PercentComplete 60 -Completed
                }
            }
            catch {
                throw "Failed to download release zip: $($_.Exception.Message)"
            }
        }
        if (-not $WhatIf) {
            try {
                Write-Progress -Activity "Extracting release" -Status "Expanding archive" -PercentComplete 70
                Expand-Archive -LiteralPath $zipPath -DestinationPath $relDir -Force
                Write-Progress -Activity "Extracting release" -Status "Expanding archive" -PercentComplete 90 -Completed
            }
            catch {
                throw "Failed to extract release archive: $($_.Exception.Message)"
            }
        }
    }

    if (-not $WhatIf) {
        $verified = 0
        foreach ($name in $sums.Keys) {
            $p = Join-Path $relDir $name
            if (Test-Path -LiteralPath $p) {
                $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
                if ($h -ne $sums[$name]) { throw "Release integrity failure: $name (hash mismatch)" }
                $verified++
            }
        }
        if ($verified -lt $global:MinVerifiedFiles) { throw "Release verification incomplete ($verified/$($global:MinVerifiedFiles) files verified)." }
    }

    $ssdiag = Join-Path $Cache 'ssdiag.exe'
    if (-not (Test-Path -LiteralPath $ssdiag)) {
        $asset = [string]$cfg.ssdiagAsset
        try {
            if ($WhatIf) {
                Write-Host "[WhatIf] Would download ssdiag from https://github.com/$repo/releases/download/$tag/$asset"
            } else {
                Write-Progress -Activity "Downloading ssdiag" -Status "ssdiag.exe" -PercentComplete 95
                Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/releases/download/$tag/$asset" -OutFile $ssdiag
                $want = $sums[$global:SsdiagAssetName]
                if ($want) {
                    $h = (Get-FileHash -LiteralPath $ssdiag -Algorithm SHA256).Hash.ToLower()
                    if ($h -ne $want) { throw 'Release integrity failure: ssdiag (hash mismatch)' }
                }
                Write-Progress -Activity "Downloading ssdiag" -Status "ssdiag.exe" -PercentComplete 100 -Completed
            }
        }
        catch {
            throw "Failed to download ssdiag asset: $($_.Exception.Message)"
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
        [Parameter(Mandatory)][string]$Family,
        [switch]$WhatIf
    )
    if ($WhatIf) {
        Write-Host "[WhatIf] Would run make-usbroot.ps1 -Family $Family -Out $OutDir -Work $WorkDir"
        return
    }
    if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

    $makerArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Maker,
                   '-Family', $Family, '-Out', $OutDir, '-Work', $WorkDir)
    & powershell.exe @makerArgs
    if ($LASTEXITCODE -ne 0) { throw "make-usbroot.ps1 failed (exit $LASTEXITCODE)." }
}

Export-ModuleMember -Function Get-UnlockRelease, Invoke-UnlockMaker