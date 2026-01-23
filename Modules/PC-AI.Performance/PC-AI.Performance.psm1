#Requires -Version 5.1
<#
.SYNOPSIS
    PC-AI Performance Module Loader

.DESCRIPTION
    This module provides performance monitoring and optimization functions for Windows systems.
    It includes disk space analysis, process performance monitoring, disk optimization,
    and real-time system resource monitoring capabilities.

.NOTES
    Module: PC-AI.Performance
    Version: 1.0.0
    Author: PC_AI Project
#>

# Get the module root path
$ModuleRoot = $PSScriptRoot

# Define paths for public and private functions
$PublicPath = Join-Path -Path $ModuleRoot -ChildPath 'Public'
$PrivatePath = Join-Path -Path $ModuleRoot -ChildPath 'Private'

# Import private functions first (helpers used by public functions)
$PrivateFunctions = @()
if (Test-Path -Path $PrivatePath) {
    $PrivateFunctions = Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -ErrorAction SilentlyContinue
    foreach ($Function in $PrivateFunctions) {
        try {
            Write-Verbose "Importing private function: $($Function.BaseName)"
            . $Function.FullName
        }
        catch {
            Write-Error "Failed to import private function $($Function.BaseName): $_"
        }
    }
}

# Import public functions
$PublicFunctions = @()
if (Test-Path -Path $PublicPath) {
    $PublicFunctions = Get-ChildItem -Path $PublicPath -Filter '*.ps1' -ErrorAction SilentlyContinue
    foreach ($Function in $PublicFunctions) {
        try {
            Write-Verbose "Importing public function: $($Function.BaseName)"
            . $Function.FullName
        }
        catch {
            Write-Error "Failed to import public function $($Function.BaseName): $_"
        }
    }
}

# Export public functions
$FunctionsToExport = $PublicFunctions | ForEach-Object { $_.BaseName }
Export-ModuleMember -Function $FunctionsToExport

# Module initialization message
Write-Verbose "PC-AI.Performance module loaded. Imported $($PrivateFunctions.Count) private and $($PublicFunctions.Count) public functions."
