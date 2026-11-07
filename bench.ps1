[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Status,
    [switch]$Yes,
    [switch]$NonInteractive,
    [string]$Python,
    [string]$TorchIndex = 'https://download.pytorch.org/whl/cu130',
    [int]$Size = 8192,
    [int]$Iters = 5,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'

# Benchmark support is deliberately not part of the default setup: the CUDA
# PyTorch wheel is a multi-GB download and needs a Python the machine may not
# have. This script owns that install so neither the wizard nor the status app
# has to guess, and so the requirement can never be silently missing again.

$repoRoot = $PSScriptRoot
$cache = Join-Path $env:LOCALAPPDATA 'gpu-unlock-windows'
$benchRoot = Join-Path $cache 'bench'
$venv = Join-Path $benchRoot '.venv'
$venvPython = Join-Path $venv 'Scripts\python.exe'
$stampPath = Join-Path $benchRoot 'env.json'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

function Get-PythonVersion {
    param([string]$Exe)
    try {
        $out = & $Exe -c "import sys;print('%d.%d.%d' % sys.version_info[:3])" 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
        return ([string]$out).Trim()
    }
    catch { return $null }
}

function Resolve-BenchPython {
    param([string]$Requested)

    if ($Requested) {
        if (-not (Test-Path -LiteralPath $Requested)) { throw "Python not found: $Requested" }
        $v = Get-PythonVersion -Exe $Requested
        if (-not $v) { throw "Not a working Python interpreter: $Requested" }
        return [pscustomobject]@{ Exe = $Requested; Version = $v }
    }

    $candidates = New-Object System.Collections.ArrayList
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        foreach ($tag in @('-3.14', '-3.13', '-3.12', '-3.11', '-3.10')) {
            try {
                $exe = (& $launcher.Source $tag -c "import sys;print(sys.executable)" 2>$null)
                if ($LASTEXITCODE -eq 0 -and $exe) { [void]$candidates.Add(([string]$exe).Trim()) }
            }
            catch { }
        }
    }
    $onPath = Get-Command python -ErrorAction SilentlyContinue
    if ($onPath) { [void]$candidates.Add($onPath.Source) }

    foreach ($exe in $candidates) {
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $v = Get-PythonVersion -Exe $exe
        if (-not $v) { continue }
        $parts = $v.Split('.')
        $major = [int]$parts[0]
        $minor = [int]$parts[1]
        # PyTorch ships wheels for 3.10 through the current 3.x line; anything
        # else would only fail later, at the pip step.
        if ($major -eq 3 -and $minor -ge 10 -and $minor -le 15) {
            return [pscustomobject]@{ Exe = $exe; Version = $v }
        }
    }

    throw 'No supported Python found (3.10-3.15 required). Install Python from https://www.python.org/downloads/ and re-run this script, or pass -Python <path>.'
}

function Get-BenchState {
    $state = [pscustomobject]@{
        Installed = $false
        Python    = ''
        Torch     = ''
        Cuda      = ''
        Device    = ''
        CudaOk    = $false
    }
    if (-not (Test-Path -LiteralPath $venvPython)) { return $state }
    $state.Installed = $true
    try {
        # Key/value output, stderr discarded and warnings off: torch itself can
        # emit a numpy UserWarning, and with $ErrorActionPreference='Stop' a
        # merged stderr record used to abort this probe and look like a failure.
        $probe = & $venvPython -W ignore -c "import torch,sys; sys.stdout.write('TORCH=%s\nCUDA=%s\nAVAIL=%s\nDEV=%s\n' % (torch.__version__, torch.version.cuda or 'none', str(torch.cuda.is_available()), torch.cuda.get_device_name(0) if torch.cuda.is_available() else ''))" 2>$null
        foreach ($line in @($probe)) {
            $text = ([string]$line).Trim()
            if ($text -match '^TORCH=(.*)$') { $state.Torch = $Matches[1].Trim() }
            elseif ($text -match '^CUDA=(.*)$') { $state.Cuda = $Matches[1].Trim() }
            elseif ($text -match '^AVAIL=(.*)$') { $state.CudaOk = ($Matches[1].Trim() -eq 'True') }
            elseif ($text -match '^DEV=(.*)$') { $state.Device = $Matches[1].Trim() }
        }
        $state.Python = Get-PythonVersion -Exe $venvPython
    }
    catch { return $state }
    return $state
}

function Install-BenchEnv {
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        throw 'nvidia-smi not found. Install the NVIDIA driver first - the benchmark needs a CUDA device.'
    }

    $py = Resolve-BenchPython -Requested $Python
    Write-Step "Python $($py.Version): $($py.Exe)"
    Write-Step "Creating the benchmark environment in $venv"
    if (Test-Path -LiteralPath $venv) {
        Write-Warn 'Reusing the existing environment; pip will repair it.'
    }
    else {
        New-Item -ItemType Directory -Force -Path $benchRoot | Out-Null
        & $py.Exe -m venv $venv
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $venvPython)) {
            throw "Could not create a virtual environment with $($py.Exe)."
        }
    }

    Write-Step 'Updating pip'
    & $venvPython -m pip install --upgrade --quiet pip
    if ($LASTEXITCODE -ne 0) { throw 'pip upgrade failed.' }

    Write-Step "Installing PyTorch from $TorchIndex (several GB - this is the slow part)"
    $started = Get-Date
    & $venvPython -m pip install --index-url $TorchIndex torch
    if ($LASTEXITCODE -ne 0) {
        throw "PyTorch install failed. Check the network and that $TorchIndex still serves this Python version."
    }
    # numpy is not a torch dependency; without it torch warns on every import.
    try { & $venvPython -m pip install --quiet numpy 2>$null } catch { }
    $elapsed = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)

    $state = Get-BenchState
    if (-not $state.Installed) { throw 'The environment was created but does not report PyTorch.' }
    if (-not $state.CudaOk) {
        throw "PyTorch $($state.Torch) is installed but torch.cuda.is_available() is False (CUDA runtime report: $($state.Cuda)). The wheel and the driver must match."
    }

    $record = [pscustomobject]@{
        installedAt = (Get-Date).ToString('o')
        python      = $state.Python
        torch       = $state.Torch
        cuda        = $state.Cuda
        device      = $state.Device
        index       = $TorchIndex
        venv        = $venv
    }
    $record | ConvertTo-Json | Set-Content -LiteralPath $stampPath -Encoding UTF8

    Write-Ok "PyTorch $($state.Torch) (CUDA $($state.Cuda)) ready on $($state.Device)"
    Write-Ok "Install took $elapsed min"
    return $state
}

function Invoke-Bench {
    $state = Get-BenchState
    if (-not $state.Installed -or -not $state.CudaOk) {
        throw 'Benchmark support is not installed. Run: .\bench.ps1 -Install'
    }
    $script = Join-Path $repoRoot 'benchmark\bench.py'
    if (-not (Test-Path -LiteralPath $script)) { throw "Missing benchmark script: $script" }

    $arguments = @($script, '--size', $Size, '--iters', $Iters)
    if ($Json) { $arguments += '--json' }
    & $venvPython @arguments
    if ($LASTEXITCODE -ne 0) { throw "Benchmark failed (exit $LASTEXITCODE)." }
}

# ------------------------------------------------------------------ main

if ($Status -or (-not $Install -and $PSBoundParameters.ContainsKey('Status'))) {
    $state = Get-BenchState
    if ($state.Installed -and $state.CudaOk) {
        Write-Host "installed: PyTorch $($state.Torch), CUDA $($state.Cuda), $($state.Device)" -ForegroundColor Green
        Write-Host "python:    $($state.Python)"
        Write-Host "path:      $venv"
        exit 0
    }
    if ($state.Installed) {
        Write-Host "broken:    PyTorch $($state.Torch) present but CUDA unavailable" -ForegroundColor Yellow
        exit 1
    }
    Write-Host 'not installed (run: .\bench.ps1 -Install)' -ForegroundColor Yellow
    exit 1
}

if ($Install) {
    $state = Install-BenchEnv
    Write-Host ''
    Write-Host "Next: .\bench.ps1    (runs the BF16 GEMM benchmark)" -ForegroundColor Gray
    exit 0
}

$state = Get-BenchState
if (-not $state.Installed -or -not $state.CudaOk) {
    Write-Host 'Benchmark support is not installed yet.' -ForegroundColor Yellow
    Write-Host 'It downloads a multi-GB CUDA PyTorch wheel into your user profile (no admin needed).' -ForegroundColor Gray
    $install = [bool]$Yes
    if (-not $install -and -not $NonInteractive) {
        $answer = Read-Host 'Install it now? [y/N]'
        $install = ($answer -match '^\s*[Yy]')
    }
    if (-not $install) {
        Write-Host 'Nothing changed. Run .\bench.ps1 -Install when you want it.' -ForegroundColor Gray
        exit 2
    }
    $state = Install-BenchEnv
    Write-Host ''
}

Invoke-Bench
exit 0
