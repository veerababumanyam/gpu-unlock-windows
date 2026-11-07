Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-SsdiagOutput {
    <#
    ssdiag prints the FEAT cluster of *every* family it knows on *every* chip
    ("cross-visibility"). An Ada/Ampere/Blackwell die has nothing at the Turing
    0x4096xx window, so that window answers 0xbadf5040 (PRIV_VIOLATION); a
    Turing die answers the same at 0x823xxx.

    The first "SS0 =" in the dump therefore belongs to the window this card does
    not have: parsing it reports 0xbadf5040 on a fully unlocked card. ssdiag's
    own VERDICT line is computed from the addresses mapped for this die, so it
    decides the result and names the family whose cluster is shown.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $verdict = [regex]::Match(
        $Text,
        '(?im)^[ \t]*VERDICT[ \t]*\[(?<family>[^\]]+)\][^\r\n]*?(?<state>NOT_UNLOCKED|UNLOCKED)')

    $family = ''
    $state = ''
    if ($verdict.Success) {
        $family = $verdict.Groups['family'].Value.Trim()
        $state = $verdict.Groups['state'].Value
        # A multi-GPU dump repeats every label per card. Keep the block that
        # belongs to the first verdict (the primary display function), which is
        # the same card the previous single-match parse reported.
        $scope = $Text.Substring(0, $verdict.Index)
    }
    else {
        $scope = $Text
    }

    # Cluster rows look like "  ampere/ada 0x823xxx  SS0       = 0x88888888 [...]";
    # older builds print a bare "SS0 = 0x..." with no label.
    $pairs = @([regex]::Matches($scope, '(?im)^[ \t]*(?<label>[^\r\n]*?)[ \t]*\bSS(?<index>[01])\b[ \t]*[=:][ \t]*(?<value>0x[0-9a-fA-F]+)') |
        ForEach-Object {
            [pscustomobject]@{
                Label = $_.Groups['label'].Value.Trim()
                Index = [int]$_.Groups['index'].Value
                Value = $_.Groups['value'].Value
            }
        })

    $selected = @()
    if ($family -match '(?i)turing') {
        $selected = @($pairs | Where-Object { $_.Label -match '(?i)turing|0x4096' })
    }
    elseif ($family) {
        $selected = @($pairs | Where-Object { $_.Label -match '(?i)amp|ada|blackwell|823' })
    }
    if ($selected.Count -eq 0) {
        $selected = @($pairs | Where-Object { [string]::IsNullOrEmpty($_.Label) })
    }
    if ($selected.Count -eq 0) { $selected = $pairs }

    $ss0Values = @($selected | Where-Object { $_.Index -eq 0 })
    $ss1Values = @($selected | Where-Object { $_.Index -eq 1 })
    $ss0 = ''
    $ss1 = ''
    if ($ss0Values.Count -gt 0) { $ss0 = $ss0Values[-1].Value }
    if ($ss1Values.Count -gt 0) { $ss1 = $ss1Values[-1].Value }

    $ok = $false
    if ($state) {
        $ok = ($state -eq 'UNLOCKED')
    }
    elseif ($ss0 -and $ss1) {
        $target = [Convert]::ToUInt32('88888888', 16)
        $ok = ([Convert]::ToUInt32($ss0.Substring(2), 16) -eq $target) -and
              (([Convert]::ToUInt32($ss1.Substring(2), 16) -band 0xF) -eq 0x8)
    }

    [pscustomobject]@{ Ok = $ok; Ss0 = $ss0; Ss1 = $ss1; Family = $family; Raw = $Text }
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
