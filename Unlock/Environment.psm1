Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-UnlockEnvironment {
    $checks = @()

    $sbKey = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
    $uefi = $null -ne $sbKey
    if ($uefi) {
        $checks += [pscustomobject]@{ Name = 'UEFI'; Level = 'ok'; Detail = 'UEFI firmware' }
    }
    else {
        $checks += [pscustomobject]@{ Name = 'UEFI'; Level = 'error'; Detail = 'Legacy/BIOS boot - the unlock is UEFI-only.' }
    }

    if ($uefi) {
        $sb = [int]$sbKey.UEFISecureBootEnabled
        if ($sb -eq 0) {
            $checks += [pscustomobject]@{ Name = 'Secure Boot'; Level = 'ok'; Detail = 'disabled' }
        }
        else {
            $checks += [pscustomobject]@{ Name = 'Secure Boot'; Level = 'error'; Detail = 'enabled - disable it in firmware and verify Confirm-SecureBootUEFI returns False.' }
        }
    }
    else {
        $checks += [pscustomobject]@{ Name = 'Secure Boot'; Level = 'warn'; Detail = 'unknown (non-UEFI)' }
    }

    $hb = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue
    if (($null -ne $hb) -and ([int]$hb.HiberbootEnabled -eq 1)) {
        $checks += [pscustomobject]@{ Name = 'Fast Startup'; Level = 'warn'; Detail = 'enabled - run elevated: powercfg /h off' }
    }
    else {
        $checks += [pscustomobject]@{ Name = 'Fast Startup'; Level = 'ok'; Detail = 'disabled' }
    }

    $bl = $null
    try { $bl = @(Get-BitLockerVolume -ErrorAction Stop) } catch { $bl = $null }
    if ($null -eq $bl) {
        $checks += [pscustomobject]@{ Name = 'BitLocker'; Level = 'ok'; Detail = 'not present' }
    }
    else {
        $on = @($bl | Where-Object { $_.ProtectionStatus -eq 'On' })
        if ($on.Count -gt 0) {
            $checks += [pscustomobject]@{ Name = 'BitLocker'; Level = 'warn'; Detail = 'protection On - keep the recovery key before boot changes' }
        }
        else {
            $checks += [pscustomobject]@{ Name = 'BitLocker'; Level = 'ok'; Detail = 'off' }
        }
    }

    $errors = @($checks | Where-Object { $_.Level -eq 'error' })
    [pscustomobject]@{ Checks = $checks; Ok = ($errors.Count -eq 0) }
}

function Invoke-LogRotation {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [long]$MaxSizeMB = 5,
        [int]$MaxFiles = 5
    )
    if (-not (Test-Path -LiteralPath $LogPath)) { return }
    $sizeMB = (Get-Item -LiteralPath $LogPath).Length / 1MB
    if ($sizeMB -lt $MaxSizeMB) { return }
    
    for ($i = $MaxFiles; $i -ge 1; $i--) {
        $src = if ($i -eq 1) { $LogPath } else { "$LogPath.$($i - 1)" }
        $dst = "$LogPath.$i"
        if (Test-Path -LiteralPath $src) {
            Move-Item -LiteralPath $src -Destination $dst -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Test-UnlockEnvironment, Invoke-LogRotation