Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

Export-ModuleMember -Function ConvertFrom-SsdiagOutput, Invoke-UnlockSsdiag