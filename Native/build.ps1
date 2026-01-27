<#
.SYNOPSIS
    Master build orchestration script for PC_AI native Rust/C# hybrid project.

.DESCRIPTION
    This script handles the complete build pipeline:
    1. Pre-flight: Validates toolchain requirements (Rust, .NET SDK)
    2. Clean: Optionally removes build artifacts
    3. Rust: Builds Rust workspace in release mode
    4. C#: Builds C# P/Invoke wrapper
    5. Summary: Reports build results and artifact locations

.PARAMETER Configuration
    Build configuration: Debug or Release (default: Release)

.PARAMETER Clean
    Clean build artifacts before building

.PARAMETER SkipRust
    Skip Rust build (use existing DLLs)

.PARAMETER SkipCSharp
    Skip C# build (Rust only)

.PARAMETER Test
    Run tests after building

.PARAMETER Verbose
    Show detailed build output

.EXAMPLE
    .\build.ps1
    Standard release build

.EXAMPLE
    .\build.ps1 -Clean -Test
    Clean build with tests

.EXAMPLE
    .\build.ps1 -Configuration Debug -Verbose
    Debug build with verbose output
#>

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$Clean,
    [switch]$SkipRust,
    [switch]$SkipCSharp,
    [switch]$Test,
    [switch]$Coverage,
    [switch]$PreFlight,
    [switch]$Docs,
    [switch]$DocsBuild
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Import CargoTools for build optimization
if (Get-Module -ListAvailable CargoTools) {
    if (-not (Get-Module CargoTools)) {
        Import-Module CargoTools -ErrorAction SilentlyContinue
    }
} else {
    Write-Warning 'CargoTools module not found. Build optimizations (sccache) will be disabled.'
}

# Colors for output
$Colors = @{
    Success = 'Green'
    Error   = 'Red'
    Warning = 'Yellow'
    Info    = 'Cyan'
    Step    = 'Magenta'
    Dim     = 'DarkGray'
}

# Build timing
$BuildStart = [System.Diagnostics.Stopwatch]::StartNew()
$BuildStartDateTime = [DateTime]::Now

function Write-BuildStep {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor $Colors.Step
}

function Write-BuildSuccess {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor $Colors.Success
}

function Write-BuildError {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor $Colors.Error
}

function Write-BuildInfo {
    param([string]$Message)
    Write-Host "  [i] $Message" -ForegroundColor $Colors.Info
}

function Write-BuildWarning {
    param([string]$Message)
    Write-Host "  [?] $Message" -ForegroundColor $Colors.Warning
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-ArtifactIntegrity {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [DateTime]$StartTime
    )
    if (-not (Test-Path $Path)) {
        Write-BuildError "Artifact missing: $Path"
        return $false
    }
    $item = Get-Item $Path
    if ($item.LastWriteTime -lt $StartTime) {
        Write-BuildError "Artifact is stale: $Path (Modified: $($item.LastWriteTime), Build Start: $StartTime)"
        return $false
    }
    return $true
}

# ============================================================================
# PHASE 1: PRE-FLIGHT CHECKS
# ============================================================================

if ($PreFlight) {
    Write-BuildStep 'Phase 1: Pre-flight Checks (Test.ps1)'
    $TestScript = Join-Path (Split-Path $PSScriptRoot) 'Test.ps1'
    if (Test-Path $TestScript) {
        & $TestScript
        if ($LASTEXITCODE -ne 0) {
            Write-BuildError 'Pre-flight checks failed'
            exit 1
        }
    } else {
        Write-BuildWarning "Test.ps1 not found at $TestScript"
    }
}

Write-BuildStep 'Phase 1: Build Environment Checks'

# ============================================================================
# VERSIONING
# ============================================================================
try {
    $GitVersion = git describe --tags --always --dirty 2>$null
    if (-not $GitVersion) { $GitVersion = '0.0.0-dev' }
} catch {
    $GitVersion = '0.0.0-dev'
}
$env:PCAI_BUILD_VERSION = $GitVersion
Write-BuildInfo "Build Version: $GitVersion"

# Optimization (Sccache) - Handled by CargoTools wrapper
# Start-SccacheServer | Out-Null
Write-BuildInfo 'Build acceleration via CargoTools enabled'

# Validate project structure
$RootDir = $PSScriptRoot
$RustWorkspace = Join-Path $RootDir 'pcai_core'
$CSharpDir = Join-Path $RootDir 'PcaiNative'
$BinDir = Join-Path (Split-Path $RootDir) 'bin'

# Ensure bin directory exists
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    Write-BuildInfo "Created bin directory: $BinDir"
}

if (-not $SkipRust) {
    if (-not (Test-Path $RustWorkspace)) {
        Write-BuildError "Rust workspace not found: $RustWorkspace"
        exit 1
    }

    $CargoToml = Join-Path $RustWorkspace 'Cargo.toml'
    if (-not (Test-Path $CargoToml)) {
        Write-BuildError "Cargo.toml not found: $CargoToml"
        exit 1
    }

    Write-BuildSuccess 'Rust workspace found'

    # Check Rust toolchain
    Write-BuildInfo 'Checking Rust toolchain...'
    if (-not (Test-Command 'cargo')) {
        Write-BuildError 'Cargo not found. Install Rust from https://rustup.rs/'
        exit 1
    }

    $CargoVersion = & cargo --version 2>&1
    Write-BuildSuccess "Rust: $CargoVersion"
}

if (-not $SkipCSharp) {
    Write-BuildInfo 'Checking .NET SDK...'
    if (-not (Test-Command 'dotnet')) {
        Write-BuildError '.NET SDK not found. Install from https://dotnet.microsoft.com/download'
        exit 1
    }

    $DotnetVersion = & dotnet --version 2>&1
    Write-BuildSuccess ".NET SDK: v$DotnetVersion"
}

# ============================================================================
# PHASE 2: CLEAN (Optional)
# ============================================================================

if ($Clean) {
    Write-BuildStep 'Phase 2: Clean Build Artifacts'

    if (-not $SkipRust) {
        Write-BuildInfo 'Cleaning Rust artifacts...'
        Push-Location $RustWorkspace
        try {
            & cargo clean 2>&1 | Out-Null
            Write-BuildSuccess 'Rust artifacts cleaned'
        } finally {
            Pop-Location
        }
    }

    if (-not $SkipCSharp -and (Test-Path $CSharpDir)) {
        Write-BuildInfo 'Cleaning C# artifacts...'
        Push-Location $CSharpDir
        try {
            & dotnet clean -c $Configuration --nologo --verbosity quiet 2>&1 | Out-Null
            Get-ChildItem -Path . -Include bin, obj -Recurse -Directory -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-BuildSuccess 'C# artifacts cleaned'
        } finally {
            Pop-Location
        }
    }

    # Clean bin directory DLLs
    Write-BuildInfo 'Cleaning output directory...'
    Get-ChildItem -Path $BinDir -Filter 'pcai_*.dll' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $BinDir -Filter 'PcaiNative.*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-BuildSuccess 'Output directory cleaned'
} else {
    Write-BuildStep 'Phase 2: Clean [SKIPPED]'
}

# Standardize cargo invocation
$CargoCmd = "cargo"
Write-BuildInfo "Using cargo wrapper"

# ============================================================================
# PHASE 3: BUILD RUST WORKSPACE
# ============================================================================

$RustDlls = @()
$StagedArtifacts = @()

if (-not $SkipRust) {
    Write-BuildStep 'Phase 3: Build Rust Workspace'

    # Purge stale DLLs from bin to prevent false success
    Write-BuildInfo 'Purging stale DLLs from staging...'
    Get-ChildItem -Path $BinDir -Filter 'pcai_*.dll' -ErrorAction SilentlyContinue | Remove-Item -Force

    Push-Location $RustWorkspace
    try {
        $RustConfig = if ($Configuration -eq 'Debug') { 'debug' } else { 'release' }
        # Standardize arguments for the CargoTools wrapper
        # --no-route ensures we build locally without WSL/Docker interference
        $CargoArgs = @('build', '--workspace', '--no-route')

        # Add optimal job count if available
        if (Get-Command Get-OptimalBuildJobs -ErrorAction SilentlyContinue) {
            $Jobs = Get-OptimalBuildJobs
            $CargoArgs += '--jobs', $Jobs
            Write-BuildInfo "Using $Jobs parallel build jobs"
        }

        if ($Configuration -eq 'Release') {
            $CargoArgs += '--release'
        }

        Write-BuildInfo "Building Rust workspace ($RustConfig mode)..."
        Write-BuildInfo "Arguments: $($CargoArgs -join ' ')"
        Write-Host "    cargo $($CargoArgs -join ' ')" -ForegroundColor $Colors.Dim

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        # Trace-Command -Name ParameterBinding -Expression { cargo @CargoArgs } -PSHost
        $BuildOutput = & cargo @CargoArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-BuildError 'Rust build failed'
            $BuildOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            exit 1
        }

        $sw.Stop()

        # Find built DLLs - check user's cargo config for custom target-dir
        $CargoConfigPath = Join-Path $env:USERPROFILE '.cargo\config.toml'
        $TargetDir = $null
        if (Test-Path $CargoConfigPath) {
            $CargoConfig = Get-Content $CargoConfigPath -Raw
            if ($CargoConfig -match 'target-dir\s*=\s*"([^"]+)"') {
                $TargetDir = Join-Path $Matches[1] $RustConfig
            }
        }
        if (-not $TargetDir -or -not (Test-Path $TargetDir)) {
            $TargetDir = Join-Path $RustWorkspace "target\$RustConfig"
        }
        Write-BuildInfo "Looking for DLLs in: $TargetDir"
        $DllFiles = Get-ChildItem -Path $TargetDir -Filter '*.dll' -ErrorAction SilentlyContinue

        foreach ($dll in $DllFiles) {
            if ($dll.Name -like 'pcai_*.dll') {
                $RustDlls += $dll
                $DllSize = [math]::Round($dll.Length / 1KB, 2)
                Write-BuildSuccess "$($dll.Name) ($DllSize KB)"

                # Copy to bin directory
                Copy-Item $dll.FullName $BinDir -Force

                # Verify staging integrity
                $stagedPath = Join-Path $BinDir $dll.Name
                if (Test-ArtifactIntegrity -Path $stagedPath -StartTime ($BuildStartDateTime)) {
                    $StagedArtifacts += $stagedPath
                    Write-BuildInfo "  -> Verified staging: $stagedPath"
                } else {
                    exit 1
                }
            }
        }

        if ($RustDlls.Count -eq 0) {
            Write-BuildWarning 'No PCAI DLLs found in target directory'
        }

        Write-BuildSuccess "Rust build completed in $([math]::Round($sw.Elapsed.TotalSeconds, 2))s"
    } finally {
        Pop-Location
    }
} else {
    Write-BuildStep 'Phase 3: Build Rust [SKIPPED]'
}

# ============================================================================
# PHASE 4: BUILD C# WRAPPER
# ============================================================================

if (-not $SkipCSharp) {
    Write-BuildStep 'Phase 4: Build C# Wrapper'

    # Purge stale wrapper from bin
    Write-BuildInfo 'Purging stale C# wrapper from staging...'
    Get-ChildItem -Path $BinDir -Filter 'PcaiNative.*' -ErrorAction SilentlyContinue | Remove-Item -Force

    if (-not (Test-Path $CSharpDir)) {
        Write-BuildWarning "C# project not found: $CSharpDir"
        Write-BuildInfo 'Creating placeholder C# project structure...'

        New-Item -ItemType Directory -Path $CSharpDir -Force | Out-Null
        Write-BuildInfo 'C# project directory created. See Phase 5 for next steps.'
    } else {
        Push-Location $CSharpDir
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            # Copy Rust DLLs to C# project
            foreach ($dll in $RustDlls) {
                $destPath = Join-Path $CSharpDir $dll.Name
                Copy-Item $dll.FullName $destPath -Force
                Write-BuildInfo "Staged $($dll.Name) for C# build"
            }

            $BuildArgs = @('build', '-c', $Configuration, '--nologo')
            Write-Host "    dotnet $($BuildArgs -join ' ')" -ForegroundColor $Colors.Dim

            $BuildOutput = & dotnet @BuildArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildError 'C# build failed'
                $BuildOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                exit 1
            }

            $sw.Stop()

            # Find and copy output
            $OutputDir = Join-Path $CSharpDir "bin\$Configuration\net8.0\win-x64"
            if (Test-Path $OutputDir) {
                Get-ChildItem -Path $OutputDir -Filter 'PcaiNative.*' -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $destPath = Join-Path $BinDir $_.Name
                        Copy-Item $_.FullName $destPath -Force
                        if (Test-ArtifactIntegrity -Path $destPath -StartTime $BuildStartDateTime) {
                            $StagedArtifacts += $destPath
                            Write-BuildSuccess "$($_.Name) (Staged & Verified)"
                        } else {
                            exit 1
                        }
                    }
            }

            Write-BuildSuccess "C# build completed in $([math]::Round($sw.Elapsed.TotalSeconds, 2))s"
        } finally {
            Pop-Location
        }
    }
} else {
    Write-BuildStep 'Phase 4: Build C# [SKIPPED]'
}

# ============================================================================
# PHASE 5: RUN TESTS (Optional)
# ============================================================================

if ($Test) {
    Write-BuildStep 'Phase 5: Run Tests'

    if (-not $SkipRust) {
        Write-BuildInfo 'Running Rust tests...'
        Push-Location $RustWorkspace
        try {
            if ($Coverage) {
                # Ensure cargo-llvm-cov is installed
                if (-not (Get-Command cargo-llvm-cov -ErrorAction SilentlyContinue)) {
                    Write-BuildInfo 'Installing cargo-llvm-cov...'
                    cargo install cargo-llvm-cov
                }

                Write-BuildInfo 'Generating Rust code coverage (LCOV)...'
                $TestOutput = & cargo llvm-cov --workspace --lcov --output-path coverage.lcov 2>&1
            } else {
                $TestOutput = & cargo test --workspace 2>&1
            }
            if ($LASTEXITCODE -ne 0) {
                Write-BuildError 'Rust tests failed'
                $TestOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            } else {
                Write-BuildSuccess 'Rust tests passed'
            }
        } finally {
            Pop-Location
        }
    }

    if (-not $SkipCSharp -and (Test-Path (Join-Path $CSharpDir '*.csproj'))) {
        Write-BuildInfo 'Running C# tests...'
        Push-Location $CSharpDir
        try {

            $DotNetTestArgs = @('test', '--nologo', '--verbosity', 'quiet')
            if ($Coverage) {
                $DotNetTestArgs += '--collect:"XPlat Code Coverage"'
                Write-BuildInfo 'Enabled C# code coverage collection'
            }
            $TestOutput = & dotnet @DotNetTestArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildWarning 'C# tests not configured or failed'
            } else {
                Write-BuildSuccess 'C# tests passed'
            }
        } finally {
            Pop-Location
        }
    }
} else {
    Write-BuildStep 'Phase 5: Run Tests [SKIPPED]'
}

# ============================================================================
# PHASE 6: ARTIFACT INTEGRITY & VERSION VERIFICATION
# ============================================================================

Write-BuildStep 'Phase 6: Artifact Integrity Verification'

$WrapperPath = Join-Path $BinDir 'PcaiNative.dll'
if ($StagedArtifacts -contains $WrapperPath) {
    Write-BuildInfo "Verifying version parity and module availability for $GitVersion..."
    try {
        # Use a separate process to avoid locking the DLLs
        $CheckScript = @"
            `$ErrorActionPreference = 'Stop'
            try {
                Add-Type -Path '$WrapperPath'
                `$results = @{}

                # Check Core
                if ([PcaiNative.PcaiCore]::IsAvailable) {
                    `$ver = [PcaiNative.PcaiCore]::Version
                    if (`$ver -eq '$GitVersion') {
                        `$results.Core = "OK (`$ver)"
                    } else {
                        throw "Core version mismatch: Expected $GitVersion, got `$ver"
                    }
                } else {
                    throw "PcaiCore not available after build"
                }

                # Check Search
                try {
                    `$searchVer = [PcaiNative.PcaiSearch]::Version
                    if (`$searchVer -match '$GitVersion') {
                        `$results.Search = "OK (`$searchVer)"
                    } else {
                        throw "Search version mismatch: Expected $GitVersion, got `$searchVer"
                    }
                } catch {
                    throw "Search module failed verification: `$_"
                }

                `$results | ConvertTo-Json
                exit 0
            } catch {
                Write-Error `$_
                exit 1
            }
"@
        $VerifyResult = pwsh -NoProfile -Command $CheckScript 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-BuildSuccess "Integrity verification PASSED: $GitVersion"
            $VerifyResult | Out-String | Write-BuildInfo
        } else {
            Write-BuildError "Integrity verification FAILED (Exit Code: $LASTEXITCODE)"
            $VerifyResult | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            exit 1
        }
    } catch {
        Write-BuildWarning "Could not perform automated verification: $_"
    }
} else {
    Write-BuildWarning 'Staging incomplete - skipping integrity verification'
}

# ============================================================================
# PHASE 7: DOCUMENTATION GENERATION
# ============================================================================

if ($Docs) {
    Write-BuildStep 'Phase 7: Documentation Generation'
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $DocScript = Join-Path $RepoRoot 'Tools\generate-auto-docs.ps1'
    if (Test-Path $DocScript) {
        $args = @(
            '-RepoRoot', $RepoRoot,
            '-IncludeAstGrep',
            '-IncludePowerShell',
            '-IncludeCSharp',
            '-IncludeRust'
        )
        if ($DocsBuild) { $args += '-BuildDocs' }
        & $DocScript @args
    } else {
        Write-BuildWarning "Documentation script not found: $DocScript"
    }
}

# ============================================================================
# PHASE 8: BUILD SUMMARY
# ============================================================================

$BuildStart.Stop()

# Stop sccache server to flush stats
if (Get-Command Stop-SccacheServer -ErrorAction SilentlyContinue) {
    Stop-SccacheServer
}

Write-BuildStep 'Phase 8: Build Summary'

Write-Host ''
Write-Host '  Build completed successfully!' -ForegroundColor Green
Write-Host "  Total time: $([math]::Round($BuildStart.Elapsed.TotalSeconds, 2)) seconds" -ForegroundColor Cyan
Write-Host ''

Write-Host '  Artifacts:' -ForegroundColor Cyan
$BinContents = Get-ChildItem -Path $BinDir -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like 'pcai_*' -or $_.Name -like 'PcaiNative*'
}
if ($BinContents) {
    foreach ($item in $BinContents) {
        $size = if ($item.PSIsContainer) { 'DIR' } else { "$([math]::Round($item.Length / 1KB, 2)) KB" }
        Write-Host "    $($item.Name.PadRight(30)) $size" -ForegroundColor White
    }
} else {
    Write-Host '    (no artifacts found)' -ForegroundColor Yellow
}

Write-Host ''
Write-Host "  Output directory: $BinDir" -ForegroundColor DarkGray
Write-Host ''

Write-Host '  Next steps:' -ForegroundColor Yellow
Write-Host '    1. Run tests:        .\build.ps1 -Test' -ForegroundColor DarkGray
Write-Host '    2. Pester tests:     ..\Tests\Integration\FFI.Core.Tests.ps1' -ForegroundColor DarkGray
Write-Host '    3. Import module:    Import-Module ..\Modules\PC-AI.Acceleration' -ForegroundColor DarkGray
Write-Host ''
