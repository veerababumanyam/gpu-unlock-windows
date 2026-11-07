Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import all submodules
$Root = $PSScriptRoot
@(
    'Config.psm1'
    'Environment.psm1'
    'Release.psm1'
    'Staging.psm1'
    'Markers.psm1'
    'Diagnostics.psm1'
    'Hardware.psm1'
) | ForEach-Object {
    Import-Module (Join-Path $Root $_) -Force -DisableNameChecking
}

# Re-export all public functions
Export-ModuleMember -Function *