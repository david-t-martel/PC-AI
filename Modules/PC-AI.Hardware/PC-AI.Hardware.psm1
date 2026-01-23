#Requires -Version 5.1
<#
.SYNOPSIS
    PC-AI Hardware Diagnostics Module

.DESCRIPTION
    Provides hardware diagnostic functions for PC-AI framework including:
    - Device Manager error detection
    - Disk SMART status monitoring
    - USB device status
    - Network adapter diagnostics
    - System event log analysis

.NOTES
    Author: PC_AI Framework
    Version: 1.0.0
#>

# Module variables
$script:ModuleRoot = $PSScriptRoot
$script:ConfigPath = Join-Path (Split-Path $ModuleRoot -Parent | Split-Path -Parent) 'Config'

# Import private functions
$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }
}

# Import public functions
$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-DeviceErrors',
    'Get-DiskHealth',
    'Get-UsbStatus',
    'Get-NetworkAdapters',
    'Get-SystemEvents',
    'New-DiagnosticReport'
)
