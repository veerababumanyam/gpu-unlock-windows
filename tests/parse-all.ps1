$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' })
$failures = @()

foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $failures += [pscustomobject]@{
            Path     = $file.FullName
            Messages = @($parseErrors | ForEach-Object { $_.Message })
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL $($failure.Path)" -ForegroundColor Red
        foreach ($message in $failure.Messages) {
            Write-Host "  $message" -ForegroundColor Red
        }
    }
    exit 1
}

Write-Host "Parsed $($files.Count) PowerShell files."
