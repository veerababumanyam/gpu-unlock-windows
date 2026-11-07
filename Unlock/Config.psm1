Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Constants (global so all submodules can access) ---
$global:EfiPath           = 'EFI/BOOT/BOOTX64.EFI'
$global:AutoRunMarker     = 'i_know_what_i_am_doing.txt'
$global:QuietMarker       = 'tx-quiet.txt'
$global:StickLabel        = 'GPU-UNLOCK'
$global:SsdiagAssetName   = 'ssdiag-x86_64-windows.exe'
$global:MinCountdown      = 1
$global:MaxCountdown      = 30
$global:MinVerifiedFiles  = 8

function Get-UnlockConfig {
    # $PSScriptRoot is <repo>\Unlock, so one parent is the repo root.
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $path = Join-Path $repoRoot 'unlock.config.json'
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

function Get-ValidFamilies {
    $cfg = Get-UnlockConfig
    return @($cfg.expectedFiles.PSObject.Properties.Name)
}

Export-ModuleMember -Function Get-UnlockConfig, Convert-UnlockBusId, Get-ValidFamilies
Export-ModuleMember -Variable EfiPath, AutoRunMarker, QuietMarker, StickLabel, SsdiagAssetName, MinCountdown, MaxCountdown, MinVerifiedFiles