$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Unlock.psm1') -Force

$script:fail = 0
function Assert-UnlockTest {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "ok   $Message"
    }
    else {
        Write-Host "FAIL $Message" -ForegroundColor Red
        $script:fail++
    }
}

Assert-UnlockTest ((Convert-UnlockBusId '00000000:04:00.0') -eq '0000:04:00.0') 'nvidia-smi bus id normalizes'
Assert-UnlockTest ((Convert-UnlockBusId '04:00.0') -eq '0000:04:00.0') 'short bus id normalizes'
Assert-UnlockTest ((Convert-UnlockBusId '0000:04:00.0') -eq '0000:04:00.0') 'full bus id is stable'

$cfg = Get-UnlockConfig
Assert-UnlockTest (@($cfg.expectedFiles.ad102).Count -eq 7) 'config lists 7 ad102 assets'
Assert-UnlockTest (@($cfg.expectedFiles.ga102).Count -eq 7) 'config lists 7 ga102 assets'
Assert-UnlockTest (@($cfg.expectedFiles.tu10x).Count -eq 7) 'config lists 7 tu10x assets'

$unlocked = "SS0 = 0x88888888`nSS1 = 0x00000008"
$r = ConvertFrom-SsdiagOutput -Text $unlocked
Assert-UnlockTest ($r.Ok) 'ssdiag unlocked sample passes'

$locked = "SS0 = 0x00000000`nSS1 = 0x00000000"
$r = ConvertFrom-SsdiagOutput -Text $locked
Assert-UnlockTest (-not $r.Ok) 'ssdiag locked sample fails'

$lower = "ss0: 0x88888888`nss1: 0x0000008"
$r = ConvertFrom-SsdiagOutput -Text $lower
Assert-UnlockTest ($r.Ok) 'ssdiag parser is case-insensitive'

$partial = "SS0 = 0x88888888"
$r = ConvertFrom-SsdiagOutput -Text $partial
Assert-UnlockTest (-not $r.Ok) 'ssdiag without SS1 does not pass'

$mtmp = Join-Path $env:TEMP ('gpu-unlock-markers-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $mtmp | Out-Null
try {
    $m = Set-UnlockMarkers -Root $mtmp -Unattended -Quiet -Countdown 7
    Assert-UnlockTest ($m.AutoRun -and $m.Quiet -and $m.Countdown -eq 7) 'markers written'
    $m = Set-UnlockMarkers -Root $mtmp
    Assert-UnlockTest ((-not $m.AutoRun) -and (-not $m.Quiet)) 'markers removed'
}
finally {
    Remove-Item -LiteralPath $mtmp -Recurse -Force -ErrorAction SilentlyContinue
}

$tmp = Join-Path $env:TEMP ('gpu-unlock-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $r = Test-UnlockStaging -Root $tmp -Family ad102
    Assert-UnlockTest (-not $r.Ok) 'empty staging is rejected'

    foreach ($f in $cfg.expectedFiles.ad102) {
        Set-Content -LiteralPath (Join-Path $tmp $f) -Value 'x'
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'EFI\BOOT') | Out-Null
    Set-Content -LiteralPath (Join-Path $tmp 'EFI\BOOT\BOOTX64.EFI') -Value 'x'

    $r = Test-UnlockStaging -Root $tmp -Family ad102
    Assert-UnlockTest ($r.Ok) 'complete staging is accepted'

    $all = Test-UnlockStaging -Root $tmp -Family all
    Assert-UnlockTest (@($all.Expected).Count -eq 21) 'all-family staging expects 21 unique files'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:fail -gt 0) {
    Write-Host "$script:fail test(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All tests passed.' -ForegroundColor Green
