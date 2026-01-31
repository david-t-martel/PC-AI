#Requires -Version 5.1
<#
.SYNOPSIS
    Build script for pcai-inference with dual-backend support

.DESCRIPTION
    Orchestrates building pcai-inference with llamacpp (requires MSVC/CMake)
    and/or mistralrs backends. Handles toolchain detection, CUDA configuration,
    and artifact deployment.

.PARAMETER Backend
    Which backend(s) to build: llamacpp, mistralrs, or all

.PARAMETER Configuration
    Build configuration: Debug or Release

.PARAMETER EnableCuda
    Enable CUDA support for GPU acceleration

.PARAMETER SkipTests
    Skip running tests after build

.PARAMETER Clean
    Clean build directories before building

.EXAMPLE
    .\build.ps1 -Backend all -Configuration Release -EnableCuda
#>

[CmdletBinding()]
param(
    [ValidateSet('llamacpp', 'mistralrs', 'all')]
    [string]$Backend = 'all',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$EnableCuda,
    [switch]$SkipTests,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$script:ProjectRoot = $PSScriptRoot
$script:RepoRoot = Split-Path -Parent $script:ProjectRoot
$script:Config = Get-Content (Join-Path $ProjectRoot 'build-config.json') | ConvertFrom-Json
$script:BinDir = Join-Path $ProjectRoot $script:Config.output.target_dir
$script:CudaInfo = $null

# Try multiple paths for CUDA helper
$cudaHelperPaths = @(
    (Join-Path $script:RepoRoot 'Tools\Initialize-CudaEnvironment.ps1'),
    (Join-Path (Split-Path -Parent $script:RepoRoot) 'Tools\Initialize-CudaEnvironment.ps1'),
    'C:\Users\david\PC_AI\Tools\Initialize-CudaEnvironment.ps1'
)
foreach ($path in $cudaHelperPaths) {
    if (Test-Path $path) {
        . $path
        break
    }
}

$script:CmakeInfo = $null
$cmakeHelper = Join-Path $script:RepoRoot 'Tools\Initialize-CmakeEnvironment.ps1'
if (Test-Path $cmakeHelper) {
    . $cmakeHelper
    $script:CmakeInfo = Initialize-CmakeEnvironment -Quiet
}

#region Toolchain Detection

function Test-Command {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Find-VsDevShell {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        return $null
    }

    $vsPath = & $vswhere -latest -property installationPath
    $devShell = Join-Path $vsPath 'Common7\Tools\Launch-VsDevShell.ps1'

    if (Test-Path $devShell) {
        return $devShell
    }
    return $null
}

function Initialize-MsvcEnvironment {
    Write-Host "Initializing MSVC environment..." -ForegroundColor Cyan

    $devShell = Find-VsDevShell
    if (-not $devShell) {
        throw "Visual Studio Build Tools not found. Install from: https://visualstudio.microsoft.com/downloads/"
    }

    # Import VS environment
    & $devShell -SkipAutomaticLocation -HostArch amd64 -Arch amd64

    # CRITICAL: Clear interfering environment variables IMMEDIATELY after VS setup
    # These can corrupt MSVC command line parsing
    @('CL', '_CL_', 'LINK', '_LINK_') | ForEach-Object {
        if (Get-Item "Env:$_" -ErrorAction SilentlyContinue) {
            Write-Host "  Clearing polluted env var: $_" -ForegroundColor Yellow
            Remove-Item "Env:$_" -ErrorAction SilentlyContinue
        }
    }

    # Verify cl.exe is available
    if (-not (Test-Command 'cl')) {
        throw "MSVC compiler (cl.exe) not found after initialization"
    }

    # CRITICAL: Find cl.exe absolute path and override CC/CXX
    # This prevents Strawberry Perl's GCC from being detected
    $clPath = (Get-Command cl.exe).Source
    Write-Host "  cl.exe: $clPath" -ForegroundColor Green

    # Find ninja.exe - prefer local installation
    $ninjaPath = $null
    $localNinja = Join-Path $env:USERPROFILE '.local\bin\ninja.exe'
    if (Test-Path $localNinja) {
        $ninjaPath = $localNinja
    } elseif (Test-Command 'ninja') {
        $ninjaPath = (Get-Command ninja.exe).Source
    }

    if ($ninjaPath) {
        Write-Host "  ninja: $ninjaPath" -ForegroundColor Green
    } else {
        Write-Host "  ninja: Not found (CMake may use Visual Studio generator)" -ForegroundColor Yellow
    }

    # Test cl.exe actually works (prevents later surprises)
    $testFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.c'
    "int main() { return 0; }" | Out-File -FilePath $testFile -Encoding ASCII
    $ErrorActionPreference = 'Continue'
    $null = & cl.exe /c $testFile /Fo"$env:TEMP\cltest.obj" 2>&1
    $clResult = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Remove-Item $testFile -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\cltest.obj" -ErrorAction SilentlyContinue

    if ($clResult -ne 0) {
        throw "MSVC cl.exe test compilation failed (exit code: $clResult)"
    }

    # SET EXPLICIT COMPILER PATHS - NO FALLBACKS
    # Override ALL environment variables that CMake/cc-rs might use
    $env:CC = $clPath
    $env:CXX = $clPath
    $env:CMAKE_C_COMPILER = $clPath
    $env:CMAKE_CXX_COMPILER = $clPath

    # Set CMAKE generator and make program explicitly
    if ($ninjaPath) {
        $env:CMAKE_GENERATOR = 'Ninja'
        $env:CMAKE_MAKE_PROGRAM = $ninjaPath
    } else {
        $env:CMAKE_GENERATOR = 'Visual Studio 17 2022'
    }

    # Clean stale CMake configurations that may have wrong compiler cached
    Clean-StaleCmakeConfigs

    Write-Host "  CC/CXX set to MSVC cl.exe (no fallbacks)" -ForegroundColor Green

    # cl.exe returns exit code 1 when run without arguments, so use cmd /c
    $clVersion = (& cmd /c "cl 2>&1" | Select-String "Version" | Select-Object -First 1).ToString().Trim()
    Write-Host "  MSVC: $clVersion" -ForegroundColor Green
}

function Clean-StaleCmakeConfigs {
    # Clean stale CMake configurations from llama-cpp-sys-2 build dirs
    # Must remove entire 'out' directory to ensure fresh CMake configuration
    $targetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { 'T:\RustCache\cargo-target' }
    $llamaDirs = Get-ChildItem (Join-Path $targetDir 'release\build') -Filter 'llama-cpp-sys-2-*' -Directory -ErrorAction SilentlyContinue

    foreach ($dir in $llamaDirs) {
        $outDir = Join-Path $dir.FullName 'out'
        if (Test-Path $outDir) {
            Write-Host "  Cleaning stale CMake: $outDir" -ForegroundColor Yellow
            Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-CudaAvailable {
    if (-not $script:CudaInfo -and (Get-Command Initialize-CudaEnvironment -ErrorAction SilentlyContinue)) {
        $script:CudaInfo = Initialize-CudaEnvironment -Quiet
    }

    $cudaPath = if ($script:CudaInfo -and $script:CudaInfo.Found) { $script:CudaInfo.CudaPath } else { $env:CUDA_PATH }
    if (-not $cudaPath) { return $false }

    $nvcc = if ($script:CudaInfo -and $script:CudaInfo.Nvcc) { $script:CudaInfo.Nvcc } else { Join-Path $cudaPath 'bin\nvcc.exe' }
    $include = Join-Path $cudaPath 'include\cuda_runtime.h'

    if (-not (Test-Path $nvcc)) { return $false }
    if (-not (Test-Path $include)) { return $false }

    $version = & $nvcc --version 2>&1 | Select-String 'release'
    Write-Host "  CUDA: $version" -ForegroundColor Green
    return $true
}

function Test-Prerequisites {
    Write-Host "`nChecking prerequisites..." -ForegroundColor Cyan

    $missing = @()

    # Rust
    if (Test-Command 'cargo') {
        $rustVersion = & rustc --version
        Write-Host "  Rust: $rustVersion" -ForegroundColor Green
    } else {
        $missing += 'Rust (cargo)'
    }

    # CMake
    if (Test-Command 'cmake') {
        $cmakeVersion = & cmake --version | Select-Object -First 1
        Write-Host "  CMake: $cmakeVersion" -ForegroundColor Green
    } else {
        $missing += 'CMake'
    }

    # Ninja
    if (Test-Command 'ninja') {
        $ninjaVersion = & ninja --version
        Write-Host "  Ninja: $ninjaVersion" -ForegroundColor Green
    } else {
        Write-Host "  Ninja: Not found (will use default generator)" -ForegroundColor Yellow
    }

    # CUDA (optional)
    if ($EnableCuda) {
        if (-not (Test-CudaAvailable)) {
            Write-Host "  CUDA: Not found (building CPU-only)" -ForegroundColor Yellow
            $script:EnableCuda = $false
        }
    }

    if ($missing.Count -gt 0) {
        throw "Missing prerequisites: $($missing -join ', ')"
    }

    Write-Host "Prerequisites OK`n" -ForegroundColor Green
}

#endregion

#region Build Functions

function Invoke-CleanBuild {
    Write-Host "Cleaning build directories..." -ForegroundColor Cyan

    $dirs = @(
        (Join-Path $ProjectRoot 'target'),
        (Join-Path $ProjectRoot 'build')
    )

    foreach ($dir in $dirs) {
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force
            Write-Host "  Removed: $dir" -ForegroundColor Yellow
        }
    }
}

function Build-LlamaCppBackend {
    Write-Host "`n=== Building llamacpp backend ===" -ForegroundColor Magenta

    # Initialize MSVC (sets CC, CXX, CMAKE_*, clears polluted env vars)
    Initialize-MsvcEnvironment

    # Initialize CUDA if enabled
    if ($EnableCuda) {
        if (Get-Command Initialize-CudaEnvironment -ErrorAction SilentlyContinue) {
            Write-Host "`nInitializing CUDA environment..." -ForegroundColor Cyan
            $script:CudaInfo = Initialize-CudaEnvironment
            if ($script:CudaInfo -and $script:CudaInfo.Found) {
                $env:LLAMA_CUDA = '1'
                $env:GGML_CUDA = 'ON'
            } else {
                Write-Host "  CUDA initialization failed, building CPU-only" -ForegroundColor Yellow
                $EnableCuda = $false
                $env:LLAMA_CUDA = '0'
                $env:GGML_CUDA = 'OFF'
            }
        } else {
            Write-Host "  CUDA helper not found, checking environment..." -ForegroundColor Yellow
            if ($env:CUDA_PATH -and (Test-Path "$env:CUDA_PATH\bin\nvcc.exe")) {
                $env:LLAMA_CUDA = '1'
                $env:GGML_CUDA = 'ON'
            } else {
                Write-Host "  CUDA not properly configured, building CPU-only" -ForegroundColor Yellow
                $EnableCuda = $false
                $env:LLAMA_CUDA = '0'
                $env:GGML_CUDA = 'OFF'
            }
        }
    } else {
        $env:LLAMA_CUDA = '0'
        $env:GGML_CUDA = 'OFF'
    }

    # Disable any OpenMP interference (can cause linker issues)
    $env:LLAMA_NO_OPENMP = '1'

    # Print configuration for debugging
    Write-Host "`nBuild configuration:" -ForegroundColor Cyan
    Write-Host "  CMAKE_GENERATOR:     $env:CMAKE_GENERATOR"
    Write-Host "  CMAKE_MAKE_PROGRAM:  $env:CMAKE_MAKE_PROGRAM"
    Write-Host "  CMAKE_C_COMPILER:    $env:CMAKE_C_COMPILER"
    Write-Host "  CMAKE_CXX_COMPILER:  $env:CMAKE_CXX_COMPILER"
    Write-Host "  LLAMA_CUDA:          $env:LLAMA_CUDA"
    Write-Host "  GGML_CUDA:           $env:GGML_CUDA"
    if ($env:CUDA_PATH) {
        Write-Host "  CUDA_PATH:           $env:CUDA_PATH"
    }
    Write-Host ""

    # Build features
    $features = @('llamacpp', 'ffi', 'server')
    if ($EnableCuda) {
        $features += 'cuda'
    }

    $featureString = $features -join ','
    Write-Host "Features: $featureString" -ForegroundColor Cyan

    # Cargo build
    $cargoArgs = @(
        'build',
        '--features', $featureString,
        '--lib'
    )

    if ($Configuration -eq 'Release') {
        $cargoArgs += '--release'
    }

    Write-Host "Running: cargo $($cargoArgs -join ' ')" -ForegroundColor Gray
    Push-Location $ProjectRoot
    try {
        & cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Cargo build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    Write-Host "llamacpp backend built successfully" -ForegroundColor Green
}

function Build-MistralRsBackend {
    Write-Host "`n=== Building mistralrs backend ===" -ForegroundColor Magenta

    $features = @('mistralrs-backend', 'ffi', 'server')
    $featureString = $features -join ','

    Write-Host "Features: $featureString" -ForegroundColor Cyan

    $cargoArgs = @(
        'build',
        '--features', $featureString,
        '--lib'
    )

    if ($Configuration -eq 'Release') {
        $cargoArgs += '--release'
    }

    Write-Host "Running: cargo $($cargoArgs -join ' ')" -ForegroundColor Gray
    Push-Location $ProjectRoot
    try {
        & cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Cargo build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    Write-Host "mistralrs backend built successfully" -ForegroundColor Green
}

function Copy-Artifacts {
    Write-Host "`nCopying artifacts..." -ForegroundColor Cyan

    $targetDir = if ($Configuration -eq 'Release') { 'release' } else { 'debug' }
    $sourceDir = Join-Path $ProjectRoot "target\$targetDir"

    # Check for custom target dir (CARGO_TARGET_DIR)
    if ($env:CARGO_TARGET_DIR) {
        $sourceDir = Join-Path $env:CARGO_TARGET_DIR $targetDir
    }

    # Ensure bin directory exists
    if (-not (Test-Path $script:BinDir)) {
        New-Item -ItemType Directory -Path $script:BinDir -Force | Out-Null
    }

    # Copy DLL
    $dllName = $script:Config.output.dll_name
    $dllSource = Join-Path $sourceDir $dllName

    if (Test-Path $dllSource) {
        Copy-Item $dllSource $script:BinDir -Force
        $size = (Get-Item (Join-Path $script:BinDir $dllName)).Length / 1MB
        Write-Host "  Copied: $dllName ($([math]::Round($size, 1)) MB)" -ForegroundColor Green
    } else {
        Write-Host "  Warning: $dllName not found at $dllSource" -ForegroundColor Yellow
    }

    # Copy PDB if exists (debug symbols)
    $pdbSource = Join-Path $sourceDir 'pcai_inference.pdb'
    if (Test-Path $pdbSource) {
        Copy-Item $pdbSource $script:BinDir -Force
        Write-Host "  Copied: pcai_inference.pdb" -ForegroundColor Green
    }
}

function Invoke-Tests {
    if ($SkipTests) {
        Write-Host "`nSkipping tests (--SkipTests)" -ForegroundColor Yellow
        return
    }

    Write-Host "`n=== Running tests ===" -ForegroundColor Magenta

    Push-Location $ProjectRoot
    try {
        & cargo test --no-default-features
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Some tests failed" -ForegroundColor Yellow
        } else {
            Write-Host "All tests passed" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

#endregion

#region Main

try {
    Write-Host @"

====================================================
           PCAI-INFERENCE BUILD SCRIPT
  Backend: $($Backend.PadRight(15)) Configuration: $Configuration
====================================================

"@ -ForegroundColor Cyan

    # Prerequisites
    Test-Prerequisites

    # Clean if requested
    if ($Clean) {
        Invoke-CleanBuild
    }

    # Build backends
    $buildStart = Get-Date

    switch ($Backend) {
        'llamacpp' {
            Build-LlamaCppBackend
        }
        'mistralrs' {
            Build-MistralRsBackend
        }
        'all' {
            # Build mistralrs first (simpler, validates Rust setup)
            Build-MistralRsBackend

            # Then attempt llamacpp (requires MSVC)
            try {
                Build-LlamaCppBackend
            } catch {
                Write-Host "`nNote: llamacpp build failed: $_" -ForegroundColor Yellow
                Write-Host "mistralrs backend is still available" -ForegroundColor Yellow
            }
        }
    }

    $buildDuration = (Get-Date) - $buildStart

    # Copy artifacts
    Copy-Artifacts

    # Run tests
    Invoke-Tests

    Write-Host @"

====================================================
  BUILD COMPLETE
  Duration: $("{0:mm\:ss}" -f $buildDuration)
  Artifacts: $script:BinDir
====================================================

"@ -ForegroundColor Green

} catch {
    Write-Host "`nBUILD FAILED: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}

#endregion
