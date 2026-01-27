<#
.SYNOPSIS
    Master build orchestration script for NukeNul hybrid Rust/C# project.

.DESCRIPTION
    This script handles the complete build pipeline:
    1. Validates toolchain requirements (Rust, .NET SDK)
    2. Builds Rust DLL in release mode
    3. Copies nuker_core.dll to C# project directory
    4. Builds C# CLI application
    5. Optionally publishes self-contained executable

.PARAMETER Configuration
    Build configuration: Debug or Release (default: Release)

.PARAMETER Publish
    Create self-contained executable with native AOT

.PARAMETER Clean
    Clean build artifacts before building

.PARAMETER SkipRust
    Skip Rust build (use existing DLL)

.PARAMETER SkipCSharp
    Skip C# build (Rust only)

.EXAMPLE
    .\build.ps1
    Standard release build

.EXAMPLE
    .\build.ps1 -Publish
    Build self-contained executable

.EXAMPLE
    .\build.ps1 -Clean -Configuration Debug
    Clean debug build
#>

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$Publish,
    [switch]$Clean,
    [switch]$SkipRust,
    [switch]$SkipCSharp
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Colors for output
$Colors = @{
    Success = 'Green'
    Error   = 'Red'
    Warning = 'Yellow'
    Info    = 'Cyan'
    Step    = 'Magenta'
}

function Write-BuildStep {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor $Colors.Step
}

function Write-BuildSuccess {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor $Colors.Success
}

function Write-BuildError {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor $Colors.Error
}

function Write-BuildInfo {
    param([string]$Message)
    Write-Host "[i] $Message" -ForegroundColor $Colors.Info
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# ============================================================================
# PHASE 1: PRE-FLIGHT CHECKS
# ============================================================================

Write-BuildStep "Phase 1: Pre-flight Checks"

# Validate project structure
$RootDir = $PSScriptRoot
$RustDir = Join-Path $RootDir "nuker_core"
$CSharpDir = $RootDir  # C# files are in root directory
$CargoToml = Join-Path $RustDir "Cargo.toml"
$CSharpProj = Join-Path $CSharpDir "NukeNul.csproj"

if (-not $SkipRust) {
    if (-not (Test-Path $RustDir)) {
        Write-BuildError "Rust project directory not found: $RustDir"
        Write-Host "`nExpected structure:" -ForegroundColor Yellow
        Write-Host "  nuker_core/Cargo.toml"
        Write-Host "  nuker_core/src/lib.rs"
        exit 1
    }

    if (-not (Test-Path $CargoToml)) {
        Write-BuildError "Cargo.toml not found: $CargoToml"
        exit 1
    }
}

if (-not $SkipCSharp) {
    if (-not (Test-Path $CSharpProj)) {
        Write-BuildError "NukeNul.csproj not found: $CSharpProj"
        Write-Host "`nExpected structure:" -ForegroundColor Yellow
        Write-Host "  NukeNul.csproj"
        Write-Host "  Program.cs"
        exit 1
    }
}

Write-BuildSuccess "Project structure validated"

# Check Rust toolchain
if (-not $SkipRust) {
    Write-BuildInfo "Checking Rust toolchain..."
    if (-not (Test-Command 'cargo')) {
        Write-BuildError "Cargo not found. Install Rust from https://rustup.rs/"
        exit 1
    }

    $CargoVersion = cargo --version
    Write-BuildSuccess "Rust toolchain found: $CargoVersion"
}

# Check .NET SDK
if (-not $SkipCSharp) {
    Write-BuildInfo "Checking .NET SDK..."
    if (-not (Test-Command 'dotnet')) {
        Write-BuildError ".NET SDK not found. Install from https://dotnet.microsoft.com/download"
        exit 1
    }

    $DotnetVersion = dotnet --version
    Write-BuildSuccess ".NET SDK found: v$DotnetVersion"
}

# ============================================================================
# PHASE 2: CLEAN (Optional)
# ============================================================================

if ($Clean) {
    Write-BuildStep "Phase 2: Clean Build Artifacts"

    if (-not $SkipRust) {
        Write-BuildInfo "Cleaning Rust artifacts..."
        Push-Location $RustDir
        try {
            cargo clean 2>&1 | Out-Null
            Write-BuildSuccess "Rust artifacts cleaned"
        }
        finally {
            Pop-Location
        }
    }

    if (-not $SkipCSharp) {
        Write-BuildInfo "Cleaning C# artifacts..."
        Push-Location $CSharpDir
        try {
            dotnet clean -c $Configuration --nologo --verbosity quiet 2>&1 | Out-Null

            # Remove bin/obj directories
            Get-ChildItem -Path . -Include bin,obj -Recurse -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            # Remove copied DLL
            Remove-Item "nuker_core.dll" -ErrorAction SilentlyContinue

            Write-BuildSuccess "C# artifacts cleaned"
        }
        finally {
            Pop-Location
        }
    }
}

# ============================================================================
# PHASE 3: BUILD RUST DLL
# ============================================================================

if (-not $SkipRust) {
    Write-BuildStep "Phase 3: Build Rust DLL"

    Push-Location $RustDir
    try {
        $RustConfig = if ($Configuration -eq 'Debug') { 'debug' } else { 'release' }
        $CargoArgs = @('build')
        if ($Configuration -eq 'Release') {
            $CargoArgs += '--release'
        }

        Write-BuildInfo "Building Rust DLL ($RustConfig mode)..."
        Write-Host "Command: cargo $($CargoArgs -join ' ')" -ForegroundColor DarkGray

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # Run cargo build with output
        $BuildOutput = & cargo $CargoArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-BuildError "Rust build failed"
            $BuildOutput | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            exit 1
        }

        $sw.Stop()

        # Locate the built DLL
        $DllPath = Join-Path $RustDir "target\$RustConfig\nuker_core.dll"
        if (-not (Test-Path $DllPath)) {
            Write-BuildError "Built DLL not found: $DllPath"
            exit 1
        }

        $DllSize = [math]::Round((Get-Item $DllPath).Length / 1KB, 2)
        Write-BuildSuccess "Rust DLL built: nuker_core.dll ($DllSize KB) in $($sw.Elapsed.TotalSeconds)s"

        # Copy DLL to C# project directory
        if (-not $SkipCSharp) {
            Write-BuildInfo "Copying DLL to C# project..."
            $DestDll = Join-Path $CSharpDir "nuker_core.dll"
            Copy-Item $DllPath $DestDll -Force
            Write-BuildSuccess "DLL copied to: $DestDll"
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-BuildStep "Phase 3: Build Rust DLL [SKIPPED]"
}

# ============================================================================
# PHASE 4: BUILD C# CLI
# ============================================================================

if (-not $SkipCSharp) {
    Write-BuildStep "Phase 4: Build C# CLI Application"

    Push-Location $CSharpDir
    try {
        # Verify DLL exists
        $DllInCSharpDir = Join-Path $CSharpDir "nuker_core.dll"
        if (-not (Test-Path $DllInCSharpDir)) {
            Write-BuildError "nuker_core.dll not found in C# directory. Run without -SkipRust first."
            exit 1
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        if ($Publish) {
            Write-BuildInfo "Publishing self-contained executable..."

            # Self-contained publish for Windows x64
            $PublishArgs = @(
                'publish'
                '-c', $Configuration
                '-r', 'win-x64'
                '--self-contained', 'true'
                '-p:PublishSingleFile=true'
                '-p:IncludeNativeLibrariesForSelfExtract=true'
                '-p:EnableCompressionInSingleFile=true'
                '--nologo'
            )

            Write-Host "Command: dotnet $($PublishArgs -join ' ')" -ForegroundColor DarkGray

            $PublishOutput = & dotnet $PublishArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildError "C# publish failed"
                $PublishOutput | ForEach-Object { Write-Host $_ -ForegroundColor Red }
                exit 1
            }

            $sw.Stop()

            # Locate published executable
            $PublishDir = Join-Path $CSharpDir "bin\$Configuration\net8.0\win-x64\publish"
            $ExePath = Join-Path $PublishDir "NukeNul.exe"

            if (Test-Path $ExePath) {
                $ExeSize = [math]::Round((Get-Item $ExePath).Length / 1MB, 2)
                Write-BuildSuccess "Self-contained executable published: NukeNul.exe ($ExeSize MB) in $($sw.Elapsed.TotalSeconds)s"
                Write-BuildInfo "Location: $PublishDir"
            }
            else {
                Write-BuildError "Published executable not found: $ExePath"
                exit 1
            }
        }
        else {
            Write-BuildInfo "Building C# application (framework-dependent)..."

            $BuildArgs = @(
                'build'
                '-c', $Configuration
                '--nologo'
            )

            Write-Host "Command: dotnet $($BuildArgs -join ' ')" -ForegroundColor DarkGray

            $BuildOutput = & dotnet $BuildArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildError "C# build failed"
                $BuildOutput | ForEach-Object { Write-Host $_ -ForegroundColor Red }
                exit 1
            }

            $sw.Stop()

            # Locate built executable
            $BuildDir = Join-Path $CSharpDir "bin\$Configuration\net8.0\win-x64"
            $ExePath = Join-Path $BuildDir "NukeNul.exe"

            if (Test-Path $ExePath) {
                $ExeSize = [math]::Round((Get-Item $ExePath).Length / 1KB, 2)
                Write-BuildSuccess "C# application built: NukeNul.exe ($ExeSize KB) in $($sw.Elapsed.TotalSeconds)s"
                Write-BuildInfo "Location: $BuildDir"

                # Ensure DLL is in output directory
                $OutputDll = Join-Path $BuildDir "nuker_core.dll"
                if (-not (Test-Path $OutputDll)) {
                    Copy-Item $DllInCSharpDir $OutputDll -Force
                    Write-BuildInfo "nuker_core.dll copied to output directory"
                }
            }
            else {
                Write-BuildError "Built executable not found: $ExePath"
                exit 1
            }
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-BuildStep "Phase 4: Build C# CLI [SKIPPED]"
}

# ============================================================================
# PHASE 5: BUILD SUMMARY
# ============================================================================

Write-BuildStep "Phase 5: Build Summary"

Write-Host ""
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Artifacts:" -ForegroundColor Cyan

if (-not $SkipRust) {
    $RustConfig = if ($Configuration -eq 'Debug') { 'debug' } else { 'release' }
    $RustDll = Join-Path $RustDir "target\$RustConfig\nuker_core.dll"
    Write-Host "  [Rust]   $RustDll"
}

if (-not $SkipCSharp) {
    if ($Publish) {
        $ExeDir = Join-Path $CSharpDir "bin\$Configuration\net8.0\win-x64\publish"
    }
    else {
        $ExeDir = Join-Path $CSharpDir "bin\$Configuration\net8.0\win-x64"
    }

    $ExePath = Join-Path $ExeDir "NukeNul.exe"
    Write-Host "  [C#]     $ExePath"
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run tests:      .\test.ps1"
Write-Host "  2. Quick test:     cd bin\$Configuration\net8.0\win-x64 ; .\NukeNul.exe ."
Write-Host "  3. Install:        Copy NukeNul.exe to a PATH location"
Write-Host ""
