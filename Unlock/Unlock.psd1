@{
    RootModule = 'Unlock.psm1'
    ModuleVersion = '2.2.2'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'GPU Unlock Project'
    Description = 'GPU Unlock Windows - Modular PowerShell library for NVIDIA tensor-rate unlock'
    FunctionsToExport = @(
        'Get-UnlockConfig'
        'Convert-UnlockBusId'
        'Get-ValidFamilies'
        'Test-UnlockEnvironment'
        'Invoke-LogRotation'
        'Get-UnlockRelease'
        'Invoke-UnlockMaker'
        'Test-UnlockStaging'
        'Install-UnlockStick'
        'Set-UnlockMarkers'
        'ConvertFrom-SsdiagOutput'
        'Invoke-UnlockSsdiag'
        'Get-UnlockTargets'
        'Get-UnlockFamilyFromTargets'
        'Get-UnlockStick'
    )
    VariablesToExport = @(
        'EfiPath'
        'AutoRunMarker'
        'QuietMarker'
        'StickLabel'
        'SsdiagAssetName'
        'MinCountdown'
        'MaxCountdown'
        'MinVerifiedFiles'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('gpu', 'nvidia', 'unlock', 'uefi', 'tensor')
            LicenseUri = 'https://github.com/veerababumanyam/gpu-unlock-windows/blob/master/LICENSE'
            ProjectUri = 'https://github.com/veerababumanyam/gpu-unlock-windows'
        }
    }
}