@{
    # Script module file associated with this manifest
    RootModule = 'PC-AI.Hardware.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # ID used to uniquely identify this module
    GUID = 'b5d8e4f3-9a2c-4b1e-8f6d-3c7a9e1b5d2f'

    # Author of this module
    Author = 'PC_AI Framework'

    # Company or vendor of this module
    CompanyName = 'PC_AI'

    # Copyright statement for this module
    Copyright = '(c) 2025 PC_AI Framework. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Hardware diagnostics module for PC-AI framework. Provides device, disk, USB, and network adapter diagnostics.'

    # Minimum version of PowerShell required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-DeviceErrors',
        'Get-DiskHealth',
        'Get-UsbStatus',
        'Get-NetworkAdapters',
        'Get-SystemEvents',
        'New-DiagnosticReport'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module
    PrivateData = @{
        PSData = @{
            Tags = @('Diagnostics', 'Hardware', 'PC-AI')
            ProjectUri = 'https://github.com/david-t-martel/PC_AI'
        }
    }
}
