
# Module manifest for module 'PSAutoLab'
#

@{
    RootModule           = 'PSAutoLab.psm1'
    ModuleVersion        = '4.22.1'
    CompatiblePSEditions = @('Desktop')
    GUID                 = 'b68f9460-9e54-4207-b385-8654ce78ca95'
    Author               = 'Pluralsight'
    CompanyName          = 'Pluralsight LLC'
    Copyright            = '(c) 2016-2022 Pluralsight LLC. All rights reserved.'
    Description          = 'This module contains the control scripts to build, snapshot and remove lab environements using DSC configurations and the Lability PowerShell module.'
    PowerShellVersion    = '5.1'
    RequiredModules      = @(@{ModuleName = "Lability"; RequiredVersion = "0.21.1" }, @{ModuleName = "Pester"; RequiredVersion = "4.10.1" })

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    FormatsToProcess     = @(
        'formats\psautolabvm.format.ps1xml',
        'formats\isotest.format.ps1xml',
        'formats\psautolabsetting.format.ps1xml',
        'formats\psautolabresource.format.ps1xml'
    )

    FunctionsToExport    = @(
        'Enable-Internet', 'Invoke-RefreshLab', 'Invoke-RunLab',
        'Invoke-SetupLab', 'Invoke-ShutdownLab', 'Invoke-SnapshotLab',
        'Invoke-UnattendLab', 'Invoke-ValidateLab', 'Invoke-WipeLab',
        'Invoke-SetupHost', 'Invoke-RefreshHost', 'Get-PSAutoLabSetting',
        'Get-LabSnapshot', 'Update-Lab', 'Get-LabSummary', 'Test-LabDSCResource',
        'Open-PSAutoLabHelp', 'Test-ISOImage'
    )

    VariablesToExport    = @()
    AliasesToExport      = @('Refresh-Lab', 'Run-Lab', 'Setup-Lab', 'Shutdown-Lab', 'Snapshot-Lab', 'Unattend-Lab', 'Validate-Lab', 'Wipe-Lab', 'Setup-Host', 'Refresh-Host')
    PrivateData          = @{

        PSData = @{

            Tags         = @('lability', 'lab', 'dsc', 'training', 'pluralsight')
            LicenseUri   = 'https://github.com/pluralsight/PS-AutoLab-Env/blob/master/LICENSE'
            ProjectUri   = 'https://github.com/pluralsight/PS-AutoLab-Env'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'https://github.com/pluralsight/PS-AutoLab-Env/blob/master/changelog.md'

        } # End of PSData hashtable

    } # End of PrivateData hashtable

}

