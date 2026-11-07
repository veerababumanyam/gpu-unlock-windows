$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'Unlock\Unlock.psm1') -Force -DisableNameChecking

$script:fail = 0
$script:pass = 0
function Assert-UnlockTest {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "ok   $Message"
        $script:pass++
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

# New tests for auto-format and multi-stick selection
# Test Get-UnlockStick with explicit drive letter (expects error for non-existent drive)
try {
    $vol = Get-UnlockStick -DriveLetter 'Z:'
    Assert-UnlockTest ($false) 'Get-UnlockStick should throw for non-existent drive'
}
catch {
    Assert-UnlockTest ($true) 'Get-UnlockStick throws for non-existent drive letter'
}

# Test Install-UnlockStick format path (mocked - requires elevation so we test logic only)
# We verify the function signature accepts the new parameters
$func = Get-Command Install-UnlockStick
$params = $func.Parameters.Keys
Assert-UnlockTest ($params.Contains('Interactive')) 'Install-UnlockStick accepts -Interactive switch'
Assert-UnlockTest ($params.Contains('FormatStick')) 'Install-UnlockStick accepts -FormatStick switch'
Assert-UnlockTest ($params.Contains('ConfirmFormat')) 'Install-UnlockStick accepts -ConfirmFormat switch'

$func2 = Get-Command Get-UnlockStick
$params2 = $func2.Parameters.Keys
Assert-UnlockTest ($params2.Contains('Interactive')) 'Get-UnlockStick accepts -Interactive switch'

# --- Regression tests for installer/module packaging defects ---
function Get-ScriptFunctionText {
    param([string]$Path, [string]$Name)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { return $null }
    $definition = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
            }, $true)) | Select-Object -First 1
    if (-not $definition) { return $null }
    return $definition.Extent.Text
}

$installAppPath = Join-Path $repoRoot 'app\Install-App.ps1'

# A function named like an existing command shadows it and recurses into itself.
$tokens = $null
$parseErrors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseFile($installAppPath, [ref]$tokens, [ref]$parseErrors)
Assert-UnlockTest (@($parseErrors).Count -eq 0) 'Install-App.ps1 parses'
$installerFunctions = @($installerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true) | ForEach-Object { $_.Name })
$shadowedFunctions = @($installerFunctions | Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue })
Assert-UnlockTest ($shadowedFunctions.Count -eq 0) ("installer functions do not shadow existing commands (found: " + ($shadowedFunctions -join ', ') + ')')

# setup.ps1 must not report success when a child installer step fails.
$setupTemp = Join-Path $env:TEMP ('gpu-unlock-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $setupTemp | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'setup.ps1') -Destination (Join-Path $setupTemp 'setup.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'Unlock') -Destination (Join-Path $setupTemp 'Unlock') -Recurse -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $setupTemp 'app') | Out-Null
    Set-Content -LiteralPath (Join-Path $setupTemp 'app\Install-App.ps1') -Value 'exit 7' -Encoding Ascii

    $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    $setupExit = -1
    $setupOutput = ''
    if ($psExe) {
        $setupOutput = (& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $setupTemp 'setup.ps1') -SkipElevation -InstallApp -NoStick 2>&1 | Out-String)
        $setupExit = $LASTEXITCODE
    }
    Assert-UnlockTest ($psExe -and $setupExit -ne 0) "setup exits non-zero when a child step fails (exit $setupExit)"
    Assert-UnlockTest ($setupOutput -match '(?i)fail') 'setup reports the failed step'
}
finally {
    Remove-Item -LiteralPath $setupTemp -Recurse -Force -ErrorAction SilentlyContinue
}

# The Apps & Features entry must launch PowerShell with -File, not a bare .ps1 path.
$uninstallFunction = Get-ScriptFunctionText -Path $installAppPath -Name 'Get-UninstallCommandLine'
if ($uninstallFunction) { . ([ScriptBlock]::Create($uninstallFunction)) }
$uninstallCommand = $null
if ($uninstallFunction) {
    $uninstallCommand = Get-UninstallCommandLine -PowerShellPath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -UninstallScript 'C:\Program Files\GPU Unlock\Uninstall.ps1'
}
Assert-UnlockTest ($null -ne $uninstallCommand -and $uninstallCommand.Contains('powershell.exe') -and $uninstallCommand.Contains('-File') -and $uninstallCommand.Contains('-Remove') -and $uninstallCommand.Contains('-Force') -and $uninstallCommand.Contains('"C:\Program Files\GPU Unlock\Uninstall.ps1"')) 'Apps & Features uninstall command runs powershell with -File -Remove -Force'

# The uninstall entry must not point at an icon file the installer never creates.
$iconFunction = Get-ScriptFunctionText -Path $installAppPath -Name 'Get-UninstallIcon'
if ($iconFunction) { . ([ScriptBlock]::Create($iconFunction)) }
$iconPath = $null
if ($iconFunction) {
    $iconPath = Get-UninstallIcon -InstallDir (Join-Path $env:TEMP ('gpu-unlock-icon-' + [guid]::NewGuid().ToString('N')))
}
Assert-UnlockTest ($iconPath -and ($iconPath -match 'imageres\.dll')) 'uninstall entry falls back to an existing system icon'

# Log rotation must keep the configured number of files.
$rotationTemp = Join-Path $env:TEMP ('gpu-unlock-rotate-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $rotationTemp | Out-Null
try {
    $rotationLog = Join-Path $rotationTemp 'status.log'
    Set-Content -LiteralPath $rotationLog -Value ('x' * 1100000) -Encoding Ascii
    foreach ($i in 1..4) {
        Set-Content -LiteralPath "$rotationLog.$i" -Value 'old' -Encoding Ascii
    }
    Invoke-LogRotation -LogPath $rotationLog -MaxSizeMB 1 -MaxFiles 5
    Assert-UnlockTest (Test-Path -LiteralPath "$rotationLog.5") 'log rotation keeps five rotated files'
    Assert-UnlockTest (-not (Test-Path -LiteralPath "$rotationLog.6")) 'log rotation does not create a sixth file'
}
finally {
    Remove-Item -LiteralPath $rotationTemp -Recurse -Force -ErrorAction SilentlyContinue
}

$versionFile = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
$configVersion = ((Get-Content -LiteralPath (Join-Path $repoRoot 'unlock.config.json') -Raw) | ConvertFrom-Json).app.version
$manifestData = & ([ScriptBlock]::Create((Get-Content -LiteralPath (Join-Path $repoRoot 'Unlock\Unlock.psd1') -Raw)))
$manifestVersion = $manifestData.ModuleVersion
Assert-UnlockTest (($versionFile -eq $configVersion) -and ($versionFile -eq $manifestVersion)) "VERSION, config and module versions agree ($versionFile)"

# The public module must export its manifest API and remove it again cleanly.
$manifestFunctions = @($manifestData.FunctionsToExport)
$unlockModule = Get-Module -Name Unlock
$exportedFunctions = @()
if ($unlockModule) { $exportedFunctions = @($unlockModule.ExportedFunctions.Keys) }
$missingFunctions = @($manifestFunctions | Where-Object { $exportedFunctions -notcontains $_ })
Assert-UnlockTest ($missingFunctions.Count -eq 0) ("Unlock module exports every manifest function (missing: " + ($missingFunctions -join ', ') + ')')

Remove-Module -Name Unlock -Force -ErrorAction SilentlyContinue
$leakedFunctions = @($manifestFunctions | Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue })
Assert-UnlockTest ($leakedFunctions.Count -eq 0) ("Remove-Module Unlock removes its commands (still present: " + ($leakedFunctions -join ', ') + ')')
Import-Module (Join-Path $repoRoot 'Unlock\Unlock.psm1') -Force -DisableNameChecking

if ($script:fail -gt 0) {
    Write-Host "$script:fail test(s) failed" -ForegroundColor Red
    exit 1
}
$passed = if ($script:pass -gt 0) { $script:pass } else { 0 }
Write-Host "Total tests: $($passed + $script:fail), Passed: $passed, Failed: $script:fail" -ForegroundColor Green
Write-Host 'All tests passed.' -ForegroundColor Green