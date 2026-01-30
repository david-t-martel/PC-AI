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

# Configure CUDA environment for GPU-accelerated builds
$cudaVersions = @('v13.1', 'v13.0', 'v12.6', 'v12.5')
$cudaBase = $null
foreach ($ver in $cudaVersions) {
    $candidatePath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\$ver"
    if (Test-Path $candidatePath) {
        $cudaBase = $candidatePath
        break
    }
}

if ($cudaBase) {
    # Set CUDA_PATH for cudarc/bindgen_cuda
    $env:CUDA_PATH = $cudaBase

    # Add CUDA bin to PATH for nvcc
    $cudaBin = "$cudaBase\bin"
    if ($env:PATH -notlike "*$cudaBin*") {
        $env:PATH = "$cudaBin;$env:PATH"
    }

    # Add nvvm/bin to PATH for cicc (CUDA intermediate compiler)
    $nvvmBin = "$cudaBase\nvvm\bin"
    if ((Test-Path $nvvmBin) -and ($env:PATH -notlike "*$nvvmBin*")) {
        $env:PATH = "$nvvmBin;$env:PATH"
    }
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
        [DateTime]$StartTime,
        [switch]$AllowStale
    )
    if (-not (Test-Path $Path)) {
        Write-BuildError "Artifact missing: $Path"
        return $false
    }
    $item = Get-Item $Path
    if ($item.LastWriteTime -lt $StartTime) {
        if ($AllowStale) {
            Write-BuildWarning "Artifact is stale (allowed): $Path (Modified: $($item.LastWriteTime), Build Start: $StartTime)"
            return $true
        }
        Write-BuildError "Artifact is stale: $Path (Modified: $($item.LastWriteTime), Build Start: $StartTime)"
        return $false
    }
    return $true
}

function Resolve-CargoTargetDir {
    if ($env:CARGO_TARGET_DIR) { return $env:CARGO_TARGET_DIR }
    $cargoConfigPath = Join-Path $env:USERPROFILE '.cargo\config.toml'
    if (Test-Path $cargoConfigPath) {
        $cargoConfig = Get-Content $cargoConfigPath -Raw
        if ($cargoConfig -match 'target-dir\s*=\s*"([^"]+)"') {
            return $Matches[1]
        }
    }
    return $null
}

function Resolve-CargoOutputDir {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigName,
        [Parameter(Mandatory)]
        [string]$WorkspacePath
    )
    $targetDir = Resolve-CargoTargetDir
    if ($targetDir) { return (Join-Path $targetDir $ConfigName) }
    return (Join-Path $WorkspacePath "target\\$ConfigName")
}

function Resolve-RustDocRoot {
    param(
        [Parameter(Mandatory)]
        [string]$WorkspacePath
    )
    $targetDir = Resolve-CargoTargetDir
    $docRoot = if ($targetDir) { Join-Path $targetDir 'doc' } else { Join-Path $WorkspacePath 'target\\doc' }
    if (Test-Path $docRoot) { return $docRoot }
    return $null
}

function Invoke-RoboCopy {
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination,
        [string[]]$Arguments = @('/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS')
    )
    if (-not (Test-Path $Source)) { return $false }
    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    & robocopy $Source $Destination @Arguments | Out-Null
    return ($LASTEXITCODE -le 7)
}

function Get-DotNetOutputDir {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$Configuration
    )
    $projectDir = Split-Path $ProjectPath
    $projectName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)
    $binRoot = Join-Path $projectDir "bin\\$Configuration"
    if (-not (Test-Path $binRoot)) { return $null }

    $candidates = Get-ChildItem -Path $binRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-Path (Join-Path $_.FullName "$projectName.exe")) -or
            (Test-Path (Join-Path $_.FullName "$projectName.dll"))
        } | Sort-Object LastWriteTime -Descending

    if ($candidates) { return $candidates[0].FullName }
    return $null
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
$CSharpRoot = Split-Path $CSharpDir
$BinDir = Join-Path (Split-Path $RootDir) 'bin'
$CSharpProjects = Get-ChildItem -Path $CSharpRoot -Filter '*.csproj' -Recurse -ErrorAction SilentlyContinue

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

        $TargetDir = Resolve-CargoOutputDir -ConfigName $RustConfig -WorkspacePath $RustWorkspace
        Write-BuildInfo "Looking for DLLs in: $TargetDir"
        $DllFiles = Get-ChildItem -Path $TargetDir -Filter '*.dll' -ErrorAction SilentlyContinue
        $ExeFiles = Get-ChildItem -Path $TargetDir -Filter '*.exe' -ErrorAction SilentlyContinue

        foreach ($dll in $DllFiles) {
            if ($dll.Name -like 'pcai_*.dll') {
                $RustDlls += $dll
                $DllSize = [math]::Round($dll.Length / 1KB, 2)
                Write-BuildSuccess "$($dll.Name) ($DllSize KB)"

                # Copy to bin directory
                Copy-Item $dll.FullName $BinDir -Force

                # Verify staging integrity
                $stagedPath = Join-Path $BinDir $dll.Name
                if (Test-ArtifactIntegrity -Path $stagedPath -StartTime ($BuildStartDateTime) -AllowStale) {
                    $StagedArtifacts += $stagedPath
                    Write-BuildInfo "  -> Verified staging: $stagedPath"
                } else {
                    exit 1
                }
            }
        }

        if ($ExeFiles.Count -gt 0) {
            $RustAppDir = Join-Path $BinDir 'apps\\rust'
            if (-not (Test-Path $RustAppDir)) {
                New-Item -ItemType Directory -Path $RustAppDir -Force | Out-Null
            }
            foreach ($exe in $ExeFiles) {
                if ($exe.LastWriteTime -lt $BuildStartDateTime) {
                    Write-BuildWarning "Skipping stale exe from shared cache: $($exe.Name)"
                    continue
                }
                $destPath = Join-Path $RustAppDir $exe.Name
                Copy-Item $exe.FullName $destPath -Force
                if (Test-ArtifactIntegrity -Path $destPath -StartTime $BuildStartDateTime -AllowStale) {
                    $StagedArtifacts += $destPath
                    Write-BuildSuccess "$($exe.Name) (Staged)"
                }
            }
        }

        if ($RustDlls.Count -eq 0) {
            Write-BuildWarning 'No PCAI DLLs found in target directory'
        }

        # Deploy pcai_fs.dll to .NET runtime folder
        Write-BuildInfo 'Deploying pcai_fs.dll to .NET runtime folder...'
        $fsDll = Get-ChildItem -Path $TargetDir -Filter 'pcai_fs.dll' -ErrorAction SilentlyContinue
        if ($fsDll) {
            $nativeDir = Join-Path $CSharpDir 'runtimes\win-x64\native'
            if (-not (Test-Path $nativeDir)) {
                New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null
                Write-BuildInfo "  Created runtime directory: $nativeDir"
            }
            Copy-Item $fsDll.FullName $nativeDir -Force
            $deployedPath = Join-Path $nativeDir $fsDll.Name
            if (Test-ArtifactIntegrity -Path $deployedPath -StartTime $BuildStartDateTime -AllowStale) {
                Write-BuildSuccess "  Deployed pcai_fs.dll to runtime folder"
            } else {
                Write-BuildWarning "  pcai_fs.dll deployment verification failed"
            }
        } else {
            Write-BuildWarning "  pcai_fs.dll not found in target directory"
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
        $primaryProject = Join-Path $CSharpDir 'PcaiNative.csproj'
        if (-not (Test-Path $primaryProject) -and $CSharpProjects) {
            $primaryProject = $CSharpProjects[0].FullName
        }

        if ($primaryProject -and (Test-Path $primaryProject)) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            # Copy Rust DLLs to C# project
            foreach ($dll in $RustDlls) {
                $destPath = Join-Path $CSharpDir $dll.Name
                Copy-Item $dll.FullName $destPath -Force
                Write-BuildInfo "Staged $($dll.Name) for C# build"
            }

            $BuildArgs = @('build', $primaryProject, '-c', $Configuration, '--nologo')
            Write-Host "    dotnet $($BuildArgs -join ' ')" -ForegroundColor $Colors.Dim

            $BuildOutput = & dotnet @BuildArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildError 'C# build failed'
                $BuildOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                exit 1
            }

            $sw.Stop()

            $outputDir = Get-DotNetOutputDir -ProjectPath $primaryProject -Configuration $Configuration
            if ($outputDir) {
                Get-ChildItem -Path $outputDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like 'PcaiNative.*' } |
                    ForEach-Object {
                        $destPath = Join-Path $BinDir $_.Name
                        Copy-Item $_.FullName $destPath -Force
                        if (Test-ArtifactIntegrity -Path $destPath -StartTime $BuildStartDateTime -AllowStale) {
                            $StagedArtifacts += $destPath
                            Write-BuildSuccess "$($_.Name) (Staged & Verified)"
                        } else {
                            exit 1
                        }
                    }
            }

            Write-BuildSuccess "C# build completed in $([math]::Round($sw.Elapsed.TotalSeconds, 2))s"
        }

        $otherProjects = @($CSharpProjects | Where-Object { $_.FullName -ne $primaryProject })
        foreach ($proj in $otherProjects) {
            $projName = [System.IO.Path]::GetFileNameWithoutExtension($proj.FullName)
            Write-BuildInfo "Building C# project: $projName"
            $BuildArgs = @('build', $proj.FullName, '-c', $Configuration, '--nologo')
            Write-Host "    dotnet $($BuildArgs -join ' ')" -ForegroundColor $Colors.Dim
            $BuildOutput = & dotnet @BuildArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildWarning "C# build failed: $projName"
                continue
            }

            $outputDir = Get-DotNetOutputDir -ProjectPath $proj.FullName -Configuration $Configuration
            if ($outputDir) {
                $stageDir = Join-Path $BinDir "apps\\$projName"
                if (-not (Test-Path $stageDir)) {
                    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
                }
                Get-ChildItem -Path $outputDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in @('.exe', '.dll', '.pdb', '.deps.json', '.runtimeconfig.json', '.json', '.xml') } |
                    ForEach-Object {
                        $destPath = Join-Path $stageDir $_.Name
                        Copy-Item $_.FullName $destPath -Force
                        if (Test-ArtifactIntegrity -Path $destPath -StartTime $BuildStartDateTime -AllowStale) {
                            $StagedArtifacts += $destPath
                        }
                    }
                Write-BuildSuccess "$projName output staged to $stageDir"
            }
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

    if ($DocsBuild) {
        $DocsRoot = Join-Path $RepoRoot 'Docs\\Generated'
        $RustDocsDest = Join-Path $DocsRoot 'Rust'
        $CSharpDocsDest = Join-Path $DocsRoot 'CSharp'

        $rustDocRoot = Resolve-RustDocRoot -WorkspacePath $RustWorkspace
        if ($rustDocRoot) {
            if (Invoke-RoboCopy -Source $rustDocRoot -Destination $RustDocsDest -Arguments @('/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS')) {
                Write-BuildSuccess "Rust docs staged to: $RustDocsDest"
            } else {
                Write-BuildWarning "Failed to stage Rust docs from: $rustDocRoot"
            }
        } else {
            Write-BuildWarning 'Rust docs not found for staging'
        }

        foreach ($proj in $CSharpProjects) {
            $projName = [System.IO.Path]::GetFileNameWithoutExtension($proj.FullName)
            $outputDir = Get-DotNetOutputDir -ProjectPath $proj.FullName -Configuration $Configuration
            if (-not $outputDir) { continue }

            $xmlDocs = Get-ChildItem -Path $outputDir -Filter '*.xml' -File -ErrorAction SilentlyContinue
            if ($xmlDocs.Count -gt 0) {
                $destDir = Join-Path $CSharpDocsDest $projName
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                foreach ($doc in $xmlDocs) {
                    Copy-Item $doc.FullName (Join-Path $destDir $doc.Name) -Force
                }
                Write-BuildSuccess "C# docs staged to: $destDir"
            }
        }
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
if ($DocsBuild) {
    $DocsRoot = Join-Path (Split-Path $RootDir) 'Docs\\Generated'
    Write-Host "    4. Docs output:      $DocsRoot" -ForegroundColor DarkGray
}
Write-Host ''
