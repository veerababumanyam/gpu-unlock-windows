Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Get-UnlockStick {
    param(
        [string]$DriveLetter,
        [switch]$Interactive
    )
    $vols = @(Get-Volume | Where-Object { $_.DriveType -eq 'Removable' })

    if ($DriveLetter) {
        $letter = $DriveLetter.TrimEnd(':').ToUpper()
        $v = $vols | Where-Object { $_.DriveLetter -eq $letter } | Select-Object -First 1
        if (-not $v) { throw "Removable volume ${letter}: not found." }
        return $v
    }
    if ($vols.Count -eq 0) { throw 'No removable volume detected. Insert a USB stick or pass -Stick X:.' }
    if ($vols.Count -gt 1) {
        if ($Interactive) {
            Write-Host "Multiple removable drives detected:" -ForegroundColor Yellow
            $vols | ForEach-Object {
                $fs = if ($_.FileSystem) { $_.FileSystem } else { 'Unknown (unformatted)' }
                $size = [math]::Round($_.Size / 1GB, 1)
                Write-Host "  [$($_.DriveLetter):] $($_.FileSystemLabel) - $fs - ${size}GB"
            }
            $choice = Read-Host "Select drive letter (e.g., E)"
            $letter = $choice.TrimEnd(':').ToUpper()
            $v = $vols | Where-Object { $_.DriveLetter -eq $letter } | Select-Object -First 1
            if (-not $v) { throw "Removable volume ${letter}: not found." }
            return $v
        }
        $letters = ($vols | ForEach-Object { $_.DriveLetter }) -join ', '
        throw "Multiple removable volumes ($letters); pass -Stick X: or use -Interactive."
    }
    $vols[0]
}

Export-ModuleMember -Function Get-UnlockTargets, Get-UnlockFamilyFromTargets, Get-UnlockStick