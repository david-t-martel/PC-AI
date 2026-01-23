@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'PC-AI.Performance.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'e7f1a5b4-9c6d-4e0f-1a3b-4c5d6e7f8a9b'

    # Author of this module
    Author = 'PC_AI Project'

    # Company or vendor of this module
    CompanyName = 'PC_AI'

    # Copyright statement for this module
    Copyright = '(c) 2025 PC_AI Project. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Performance monitoring and optimization module for PC_AI diagnostics system. Provides disk space analysis, process performance monitoring, disk optimization, and real-time system resource monitoring.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Get-DiskSpace',
        'Get-ProcessPerformance',
        'Optimize-Disks',
        'Watch-SystemResources'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Performance', 'Diagnostics', 'Monitoring', 'Optimization', 'Windows', 'PC_AI')

            # A URL to the license for this module.
            LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 1.0.0
- Initial release
- Get-DiskSpace: Analyze drive space with threshold alerts
- Get-ProcessPerformance: Top processes by CPU/memory usage
- Optimize-Disks: Smart TRIM/defrag based on drive type
- Watch-SystemResources: Real-time system monitoring
'@

            # Prerelease string of this module
            Prerelease = ''
        }
    }

    # HelpInfo URI of this module
    HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    DefaultCommandPrefix = ''
}
