#Requires -Version 5.1

<#
.SYNOPSIS
    Shared test utilities for PCAI Inference tests.

.DESCRIPTION
    Common helper functions for integration, E2E, and functional tests:
    - Test model discovery (env var, LM Studio, Ollama)
    - DLL availability checks
    - Project path resolution
    - Test prerequisite validation

.NOTES
    Import this module in BeforeAll blocks:
    Import-Module (Join-Path $PSScriptRoot "..\Helpers\TestHelpers.psm1") -Force
#>

function Get-ProjectRoot {
    <#
    .SYNOPSIS
        Get the project root directory.
    .DESCRIPTION
        Returns the absolute path to the PC_AI project root.
        Works from any test subdirectory by traversing upward.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$StartPath
    )

    # Determine the starting point
    if (-not $StartPath) {
        $StartPath = $PSScriptRoot
    }

    # If StartPath is a file, get its directory
    if (Test-Path $StartPath -PathType Leaf) {
        $StartPath = Split-Path -Parent $StartPath
    }

    # Traverse upward to find the Tests directory, then go up one more level
    $current = $StartPath
    while ($current -and (Split-Path -Leaf $current) -ne 'Tests') {
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) {
            # Reached root without finding Tests directory
            # Assume we're in the module itself (Tests/Helpers)
            # Go up two levels from Helpers
            if ((Split-Path -Leaf $StartPath) -eq 'Helpers') {
                $testRoot = Split-Path -Parent $StartPath
                return Split-Path -Parent $testRoot
            }
            break
        }
        $current = $parent
    }

    if ($current -and (Split-Path -Leaf $current) -eq 'Tests') {
        # Found Tests directory, go up one level to project root
        return Split-Path -Parent $current
    }

    # Fallback: if we're in Helpers subdirectory of Tests
    if ($PSScriptRoot -and (Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)) -eq 'Tests') {
        return Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    # Last resort: return null and let caller handle
    return $null
}

function Get-TestModelPath {
    <#
    .SYNOPSIS
        Find a test model for inference tests.
    .DESCRIPTION
        Searches for a .gguf model file in the following order:
        1. PCAI_TEST_MODEL environment variable
        2. LM Studio cache directory
        3. Ollama cache directory
    .OUTPUTS
        String path to model file, or $null if not found.
    #>

    # Check environment variable first
    if ($env:PCAI_TEST_MODEL -and (Test-Path $env:PCAI_TEST_MODEL)) {
        Write-Verbose "Using model from PCAI_TEST_MODEL: $env:PCAI_TEST_MODEL"
        return $env:PCAI_TEST_MODEL
    }

    # Check LM Studio cache (Windows)
    $lmStudioPath = Join-Path $env:LOCALAPPDATA "lm-studio\models"
    if (Test-Path $lmStudioPath) {
        $ggufFiles = Get-ChildItem -Path $lmStudioPath -Filter "*.gguf" -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($ggufFiles) {
            Write-Verbose "Found model in LM Studio: $($ggufFiles.FullName)"
            return $ggufFiles.FullName
        }
    }

    # Check Ollama cache
    $ollamaPath = Join-Path $env:USERPROFILE ".ollama\models\blobs"
    if (Test-Path $ollamaPath) {
        $ggufFiles = Get-ChildItem -Path $ollamaPath -Filter "*.gguf" -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($ggufFiles) {
            Write-Verbose "Found model in Ollama: $($ggufFiles.FullName)"
            return $ggufFiles.FullName
        }
    }

    Write-Verbose "No test model found. Set PCAI_TEST_MODEL environment variable."
    return $null
}

function Test-InferenceDllAvailable {
    <#
    .SYNOPSIS
        Check if pcai_inference.dll exists.
    .DESCRIPTION
        Checks if the native inference DLL has been built and is available in bin/.
    .OUTPUTS
        Boolean indicating DLL availability.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectRoot
    )

    if (-not $ProjectRoot) {
        $ProjectRoot = Get-ProjectRoot -StartPath $PSScriptRoot
    }

    $binDir = Join-Path $ProjectRoot "bin"
    $dllPath = Join-Path $binDir "pcai_inference.dll"

    return Test-Path $dllPath
}

function Get-InferenceDllPath {
    <#
    .SYNOPSIS
        Get the full path to pcai_inference.dll.
    .OUTPUTS
        String path to DLL.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectRoot
    )

    if (-not $ProjectRoot) {
        $ProjectRoot = Get-ProjectRoot -StartPath $PSScriptRoot
    }

    $binDir = Join-Path $ProjectRoot "bin"
    return Join-Path $binDir "pcai_inference.dll"
}

function Assert-TestPrerequisites {
    <#
    .SYNOPSIS
        Validate test prerequisites and skip test if not met.
    .DESCRIPTION
        Checks for required test conditions (DLL, model, backend).
        If prerequisites are not met, uses Set-ItResult to skip the test.
    .PARAMETER RequireModel
        Require a test model to be available.
    .PARAMETER RequireDll
        Require pcai_inference.dll to be built.
    .PARAMETER RequireBackend
        Require a specific backend to be available (tests initialization).
    .OUTPUTS
        Boolean - $true if all prerequisites met, $false if test should be skipped.
    #>
    param(
        [switch]$RequireModel,
        [switch]$RequireDll,
        [switch]$RequireBackend,
        [string]$ProjectRoot
    )

    if (-not $ProjectRoot) {
        $ProjectRoot = Get-ProjectRoot -StartPath $PSScriptRoot
    }

    if ($RequireDll) {
        $dllPath = Get-InferenceDllPath -ProjectRoot $ProjectRoot
        if (-not (Test-Path $dllPath)) {
            Set-ItResult -Skipped -Because "DLL not available (build with Deploy\pcai-inference\build.ps1)"
            return $false
        }
    }

    if ($RequireModel) {
        $modelPath = Get-TestModelPath
        if (-not $modelPath) {
            Set-ItResult -Skipped -Because "No test model (set PCAI_TEST_MODEL environment variable)"
            return $false
        }
    }

    if ($RequireBackend) {
        # Import module if not already loaded
        $modulePath = Join-Path $ProjectRoot "Modules\PcaiInference.psm1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force -ErrorAction SilentlyContinue
        }

        $init = Initialize-PcaiInference -Backend llamacpp -ErrorAction SilentlyContinue
        if (-not $init) {
            Set-ItResult -Skipped -Because "llamacpp backend not available"
            try { Close-PcaiInference -ErrorAction SilentlyContinue } catch {}
            return $false
        }

        # Clean up after check
        try { Close-PcaiInference -ErrorAction SilentlyContinue } catch {}
    }

    return $true
}

function Get-TestPaths {
    <#
    .SYNOPSIS
        Get all common test paths in a single object.
    .DESCRIPTION
        Returns a hashtable with all standard test paths:
        - ProjectRoot, BinDir, DeployDir, ModulePath, DllPath, etc.
    .OUTPUTS
        Hashtable with test paths.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$StartPath
    )

    # Use $PSScriptRoot if no StartPath provided
    if (-not $StartPath) {
        $StartPath = $PSScriptRoot
    }

    # Resolve relative paths to absolute
    if ($StartPath -and (Test-Path $StartPath)) {
        $StartPath = Resolve-Path $StartPath
    }

    $projectRoot = Get-ProjectRoot -StartPath $StartPath

    if (-not $projectRoot) {
        throw "Could not determine project root from path: $StartPath"
    }

    $binDir = Join-Path $projectRoot "bin"
    $deployDir = Join-Path $projectRoot "Deploy\pcai-inference"
    $modulePath = Join-Path $projectRoot "Modules\PcaiInference.psm1"
    $dllPath = Join-Path $binDir "pcai_inference.dll"

    return @{
        ProjectRoot = $projectRoot
        BinDir      = $binDir
        DeployDir   = $deployDir
        ModulePath  = $modulePath
        DllPath     = $dllPath
        DllName     = "pcai_inference.dll"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProjectRoot',
    'Get-TestModelPath',
    'Test-InferenceDllAvailable',
    'Get-InferenceDllPath',
    'Assert-TestPrerequisites',
    'Get-TestPaths'
)
