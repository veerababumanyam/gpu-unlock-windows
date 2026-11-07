[CmdletBinding()]
param(
    [string]$Cache = (Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows'),
    [switch]$Elevate
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Unlock\Unlock.psm1') -Force -DisableNameChecking

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($Elevate) {
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
                     '-Cache', ('"' + $Cache + '"'))
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
        return
    }
    Write-Host 'ssdiag needs an elevated PowerShell.' -ForegroundColor Red
    Write-Host "Re-run:  .\verify.ps1 -Elevate" -ForegroundColor Yellow
    exit 2
}

$ssdiag = Join-Path $Cache 'ssdiag.exe'
if (-not (Test-Path -LiteralPath $ssdiag)) {
    throw "ssdiag not found at $ssdiag; run .\install.ps1 first."
}

$result = Invoke-UnlockSsdiag -SsdiagPath $ssdiag
Write-Output $result.Raw
Write-Output ''
Write-Output ("SS0={0}  SS1={1}" -f $result.Ss0, $result.Ss1)
if ($result.Ok) {
    Write-Host 'PASS: tensor overrides are effective.' -ForegroundColor Green
    exit 0
}
Write-Host 'NOT UNLOCKED (or selectors reverted). Replay the USB boot; see README recovery.' -ForegroundColor Red
exit 1