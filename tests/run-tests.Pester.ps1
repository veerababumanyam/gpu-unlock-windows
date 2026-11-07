# Pester-based tests for gpu-unlock-windows
# Run with: Invoke-Pester -Path .\tests\run-tests.Pester.ps1

$ErrorActionPreference = 'Stop'
# Pester 4+ separates discovery from run, so import in BeforeAll.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot 'Unlock\Unlock.psd1') -Force -DisableNameChecking
    $script:fixtureDir = Join-Path $PSScriptRoot 'fixtures'
}

Describe "Convert-UnlockBusId" {
    It "normalizes 8-hex prefix bus IDs" {
        Convert-UnlockBusId '00000000:04:00.0' | Should -Be '0000:04:00.0'
    }

    It "normalizes short bus IDs" {
        Convert-UnlockBusId '04:00.0' | Should -Be '0000:04:00.0'
    }

    It "keeps full bus IDs stable" {
        Convert-UnlockBusId '0000:04:00.0' | Should -Be '0000:04:00.0'
    }
}

Describe "Get-UnlockConfig" {
    BeforeAll {
        $script:cfg = Get-UnlockConfig
    }

    It "loads config successfully" {
        $script:cfg | Should -Not -BeNullOrEmpty
    }

    It "lists 7 ad102 assets" {
        $script:cfg.expectedFiles.ad102.Count | Should -Be 7
    }

    It "lists 7 ga102 assets" {
        $script:cfg.expectedFiles.ga102.Count | Should -Be 7
    }

    It "lists 7 tu10x assets" {
        $script:cfg.expectedFiles.tu10x.Count | Should -Be 7
    }

    It "includes efiPath" {
        $script:cfg.efiPath | Should -Be 'EFI/BOOT/BOOTX64.EFI'
    }
}

Describe "ConvertFrom-SsdiagOutput" {
    It "parses unlocked sample correctly" {
        $unlocked = "SS0 = 0x88888888`nSS1 = 0x00000008"
        $r = ConvertFrom-SsdiagOutput -Text $unlocked
        $r.Ok | Should -Be $true
        $r.Ss0 | Should -Be '0x88888888'
        $r.Ss1 | Should -Be '0x00000008'
    }

    It "fails locked sample" {
        $locked = "SS0 = 0x00000000`nSS1 = 0x00000000"
        $r = ConvertFrom-SsdiagOutput -Text $locked
        $r.Ok | Should -Be $false
    }

    It "is case-insensitive" {
        $lower = "ss0: 0x88888888`nss1: 0x0000008"
        $r = ConvertFrom-SsdiagOutput -Text $lower
        $r.Ok | Should -Be $true
    }

    It "rejects partial output without SS1" {
        $partial = "SS0 = 0x88888888"
        $r = ConvertFrom-SsdiagOutput -Text $partial
        $r.Ok | Should -Be $false
    }

    It "uses the verdict family, not the dead other-family window" {
        $fixture = Join-Path $script:fixtureDir 'ssdiag-ada-rtx4080s-live.txt'
        $r = ConvertFrom-SsdiagOutput -Text (Get-Content -LiteralPath $fixture -Raw)
        $r.Ok | Should -Be $true
        $r.Ss0 | Should -Be '0x88888888'
        $r.Ss1 | Should -Be '0x00000008'
        $r.Family | Should -Be 'ada'
    }

    It "stays locked when only the verdict family is locked" {
        $locked = @"
  turing 0x4096xx      SS0       = 0xbadf5040 [PRIV_VIOLATION]
  turing 0x4096xx      SS1       = 0xbadf5040 [PRIV_VIOLATION]
  ampere/ada 0x823xxx  SS0       = 0x23443031 [0* 0* 0* 0* 0* 0* 0* 0*]
  ampere/ada 0x823xxx  SS1       = 0x00000002 [0*]
VERDICT [ada]: NOT_UNLOCKED
"@
        $r = ConvertFrom-SsdiagOutput -Text $locked
        $r.Ok | Should -Be $false
        $r.Ss0 | Should -Be '0x23443031'
    }
}

Describe "Benchmark wiring" {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
    }

    It "ships bench.ps1 and the benchmark script" {
        (Test-Path -LiteralPath (Join-Path $script:root 'bench.ps1')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:root 'benchmark\bench.py')) | Should -Be $true
    }

    It "setup exposes the opt-in install switch" {
        $setup = Get-Content -LiteralPath (Join-Path $script:root 'setup.ps1') -Raw
        $setup -match '\[switch\]\$InstallBench' | Should -Be $true
    }
}

Describe "Set-UnlockMarkers" {
    It "writes markers with correct values" {
        $mtmp = Join-Path $env:TEMP ('gpu-unlock-markers-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $mtmp | Out-Null
        try {
            $m = Set-UnlockMarkers -Root $mtmp -Unattended -Quiet -Countdown 7
            $m.AutoRun | Should -Be $true
            $m.Quiet | Should -Be $true
            $m.Countdown | Should -Be 7

            # Verify files exist
            (Test-Path (Join-Path $mtmp 'i_know_what_i_am_doing.txt')) | Should -Be $true
            (Test-Path (Join-Path $mtmp 'tx-quiet.txt')) | Should -Be $true
            (Get-Content (Join-Path $mtmp 'i_know_what_i_am_doing.txt') -Raw).Trim() | Should -Be '7'
        }
        finally {
            Remove-Item -LiteralPath $mtmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "removes markers when called without switches" {
        $mtmp = Join-Path $env:TEMP ('gpu-unlock-markers-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $mtmp | Out-Null
        try {
            # First write them
            Set-UnlockMarkers -Root $mtmp -Unattended -Quiet -Countdown 5 | Out-Null
            # Then remove
            $m = Set-UnlockMarkers -Root $mtmp
            $m.AutoRun | Should -Be $false
            $m.Quiet | Should -Be $false
            (Test-Path (Join-Path $mtmp 'i_know_what_i_am_doing.txt')) | Should -Be $false
            (Test-Path (Join-Path $mtmp 'tx-quiet.txt')) | Should -Be $false
        }
        finally {
            Remove-Item -LiteralPath $mtmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-UnlockStaging" {
    BeforeAll {
        $script:cfg = Get-UnlockConfig
    }

    It "rejects empty staging" {
        $tmp = Join-Path $env:TEMP ('gpu-unlock-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $r = Test-UnlockStaging -Root $tmp -Family ad102
            $r.Ok | Should -Be $false
            $r.Missing.Count | Should -BeGreaterThan 0
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "accepts complete single-family staging" {
        $tmp = Join-Path $env:TEMP ('gpu-unlock-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            foreach ($f in $script:cfg.expectedFiles.ad102) {
                Set-Content -LiteralPath (Join-Path $tmp $f) -Value 'x'
            }
            New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'EFI\BOOT') | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp 'EFI\BOOT\BOOTX64.EFI') -Value 'x'

            $r = Test-UnlockStaging -Root $tmp -Family ad102
            $r.Ok | Should -Be $true
            $r.Missing.Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "all-family staging expects 21 unique files" {
        $tmp = Join-Path $env:TEMP ('gpu-unlock-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            # Populate all families
            foreach ($fam in @('ad102','ga102','tu10x')) {
                foreach ($f in $script:cfg.expectedFiles.$fam) {
                    Set-Content -LiteralPath (Join-Path $tmp $f) -Value 'x'
                }
            }
            New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'EFI\BOOT') | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp 'EFI\BOOT\BOOTX64.EFI') -Value 'x'

            $all = Test-UnlockStaging -Root $tmp -Family all
            $all.Expected.Count | Should -Be 21
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-UnlockStick" {
    Context "with explicit drive letter" {
        It "throws for non-existent drive" {
            { Get-UnlockStick -DriveLetter 'Z:' } | Should -Throw
        }
    }

    Context "parameter validation" {
        It "accepts -Interactive switch" {
            (Get-Command Get-UnlockStick).Parameters.ContainsKey('Interactive') | Should -Be $true
        }
    }
}

Describe "Install-UnlockStick" {
    Context "parameter validation" {
        It "accepts -Interactive switch" {
            (Get-Command Install-UnlockStick).Parameters.ContainsKey('Interactive') | Should -Be $true
        }
        It "accepts -FormatStick switch" {
            (Get-Command Install-UnlockStick).Parameters.ContainsKey('FormatStick') | Should -Be $true
        }
        It "accepts -ConfirmFormat switch" {
            (Get-Command Install-UnlockStick).Parameters.ContainsKey('ConfirmFormat') | Should -Be $true
        }
    }
}

Describe "Test-UnlockEnvironment" {
    It "returns a pscustomobject with Checks and Ok properties" {
        $envResult = Test-UnlockEnvironment
        $envResult | Should -Not -BeNullOrEmpty
        ($envResult.PSObject.Properties.Name -contains 'Checks') | Should -Be $true
        ($envResult.PSObject.Properties.Name -contains 'Ok') | Should -Be $true
    }

    It "Checks is an array of objects with Name, Level, Detail" {
        $envResult = Test-UnlockEnvironment
        foreach ($check in $envResult.Checks) {
            ($check.PSObject.Properties.Name -contains 'Name') | Should -Be $true
            ($check.PSObject.Properties.Name -contains 'Level') | Should -Be $true
            ($check.PSObject.Properties.Name -contains 'Detail') | Should -Be $true
            $check.Level | Should -Match '^(ok|warn|error)$'
        }
    }
}

Describe "Get-UnlockRelease" {
    Context "mocked (requires network)" {
        It "would download and verify release" -Skip -Tag "network" {
            # This test is skipped in CI without network
        }
    }
}

Describe "Invoke-UnlockMaker" {
    Context "mocked (requires elevation + network)" {
        It "would invoke make-usbroot.ps1" -Skip -Tag "elevation" {
        }
    }
}

Describe "Constants and Validation" {
    It "exposes Get-ValidFamilies function" {
        $families = Get-ValidFamilies
        $families | Should -Not -BeNullOrEmpty
        $families | Should -Contain 'ad102'
        $families | Should -Contain 'ga102'
        $families | Should -Contain 'tu10x'
    }

    It "validates -Countdown range via ValidateScript" {
        $ctmp = Join-Path $env:TEMP ('gpu-unlock-countdown-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $ctmp | Out-Null
        try {
            # Valid countdowns should not throw
            { Set-UnlockMarkers -Root $ctmp -Unattended -Countdown 1 } | Should -Not -Throw
            { Set-UnlockMarkers -Root $ctmp -Unattended -Countdown 30 } | Should -Not -Throw

            # Invalid countdowns should throw
            { Set-UnlockMarkers -Root $ctmp -Unattended -Countdown 0 } | Should -Throw
            { Set-UnlockMarkers -Root $ctmp -Unattended -Countdown 31 } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $ctmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "uses constants for marker filenames" {
        $mtmp = Join-Path $env:TEMP ('gpu-unlock-markers-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $mtmp | Out-Null
        try {
            Set-UnlockMarkers -Root $mtmp -Unattended -Quiet -Countdown 5 | Out-Null
            (Test-Path (Join-Path $mtmp 'i_know_what_i_am_doing.txt')) | Should -Be $true
            (Test-Path (Join-Path $mtmp 'tx-quiet.txt')) | Should -Be $true
        }
        finally {
            Remove-Item -LiteralPath $mtmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}