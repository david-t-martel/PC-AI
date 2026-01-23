@{
    RootModule = 'PC-AI.Virtualization.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a4c7e2d1-8b3f-4a5e-9d6c-1f2e3b4a5c6d'
    Author = 'PC_AI Framework'
    CompanyName = 'PC_AI'
    Copyright = '(c) 2025 PC_AI Framework. All rights reserved.'
    Description = 'WSL2, Hyper-V, and Docker diagnostics and optimization for PC-AI framework.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-WSLStatus',
        'Optimize-WSLConfig',
        'Set-WSLDefenderExclusions',
        'Repair-WSLNetworking',
        'Get-HyperVStatus',
        'Get-DockerStatus',
        'Backup-WSLConfig'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('WSL', 'HyperV', 'Docker', 'Virtualization', 'PC-AI')
            ProjectUri = 'https://github.com/david-t-martel/PC_AI'
        }
    }
}
