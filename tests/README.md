# Tests

Two runners are provided:

## Primary runner (no dependencies)

`run-tests.ps1` uses only built-in PowerShell and runs on Windows PowerShell 5.1
or PowerShell 7:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

It prints one `ok`/`FAIL` line per assertion and ends with a `Total tests:`
summary line. Exit code is 0 only when every assertion passes.

## Syntax check

`parse-all.ps1` parses every `.ps1`/`.psm1` file and exits non-zero on a syntax
error:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\parse-all.ps1
```

## Optional Pester runner

`run-tests.Pester.ps1` requires [Pester](https://github.com/pester/Pester) 5 or
later (tested with Pester 6):

```powershell
Install-Module -Name Pester -Force -Scope CurrentUser
Invoke-Pester -Path .\tests\run-tests.Pester.ps1
```

Pester is optional; the primary runner covers the same behavior without any
external module.
