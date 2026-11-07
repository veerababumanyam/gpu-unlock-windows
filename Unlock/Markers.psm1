Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-UnlockMarkers {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$Unattended,
        [switch]$Quiet,
        [ValidateScript({ $_ -ge $global:MinCountdown -and $_ -le $global:MaxCountdown })]
        [int]$Countdown = 5,
        [switch]$WhatIf
    )
    $autoPath = Join-Path $Root $global:AutoRunMarker
    $quietPath = Join-Path $Root $global:QuietMarker

    if ($WhatIf) {
        Write-Host "[WhatIf] Would set markers: Unattended=$Unattended, Quiet=$Quiet, Countdown=$Countdown"
        return [pscustomobject]@{ AutoRun = $Unattended; Quiet = $Quiet; Countdown = $Countdown }
    }

    if ($Unattended) {
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

Export-ModuleMember -Function Set-UnlockMarkers