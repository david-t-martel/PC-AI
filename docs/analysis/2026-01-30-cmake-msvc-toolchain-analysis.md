# CMake/MSVC Toolchain Configuration Analysis

**Project:** C:\Users\david\PC_AI\Deploy\pcai-inference
**Date:** 2026-01-30
**Issue:** llama-cpp-2 crate detecting GNU compiler instead of MSVC

---

## Executive Summary

**Root Cause:** The build environment has conflicting compiler environment variables. The `CC` environment variable is set to `C:/Strawberry/c/bin/gcc.exe` (from Strawberry Perl), which causes CMake to detect GNU instead of MSVC when building the llama-cpp-2 Rust crate.

**Impact:** The llama.cpp backend cannot build with MSVC optimizations and CUDA support.

**Solution:** Update the build process to initialize MSVC environment and override compiler variables before invoking cargo build.

---

## Current Environment

### Detected Compilers

```
CC=C:/Strawberry/c/bin/gcc.exe       ← Problem: Points to GCC
CXX=(not set)
CMAKE_GENERATOR=Ninja                ← Correct for MSVC
```

### MSVC Installation

| Edition | Path | Compiler Version |
|---------|------|------------------|
| Build Tools | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` | 14.44.35207 |
| Community | `C:\Program Files\Microsoft Visual Studio\2022\Community` | 14.44.35207 |

**Compiler Path:**
```
C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe
```

### CUDA Installation

**Latest Version:** v13.1
**Path:** `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1`

Available versions: v12.1, v12.6, v12.8, v12.9, v13.0, v13.1

---

## Problems with Current Configuration

### 1. Toolchain File (cmake/toolchain-msvc.cmake)

**Current Code:**
```cmake
set(CMAKE_C_COMPILER "cl.exe")
set(CMAKE_CXX_COMPILER "cl.exe")
```

**Problems:**
- Uses relative paths, relies on PATH resolution
- Doesn't override the CC/CXX environment variables
- Strawberry Perl's cl.exe wrapper may be found first

**Fix Required:** Use absolute paths to MSVC compiler

### 2. Build Script (build.ps1)

**Current Code:**
```powershell
function Initialize-MsvcEnvironment {
    # Imports VS environment but doesn't set CC/CXX
    & $devShell -SkipAutomaticLocation -HostArch amd64 -Arch amd64
}

function Build-LlamaCppBackend {
    $env:CMAKE_GENERATOR = 'Ninja'
    $env:LLAMA_CUDA = if ($EnableCuda) { '1' } else { '0' }
    # Missing: CC/CXX override
}
```

**Problems:**
- Doesn't unset or override CC/CXX variables
- llama-cpp-2's build.rs will use CC from environment

**Fix Required:** Explicitly set CC/CXX to MSVC paths

### 3. Rust Crate Dependencies

**Current (Cargo.toml):**
```toml
llama-cpp-2 = { version = "0.1", optional = true, features = ["cuda", "sampler"] }
```

**How llama-cpp-2 builds:**
1. Crate's build.rs invokes CMake to build llama.cpp
2. CMake respects CC/CXX environment variables first
3. If CC points to GCC, CMake will use GCC instead of MSVC
4. Toolchain files are only consulted if CMAKE_TOOLCHAIN_FILE is set

**Fix Required:** Ensure CMAKE_TOOLCHAIN_FILE is set and CC/CXX point to MSVC

---

## Recommended Fixes

### Fix 1: Update toolchain-msvc.cmake

**File:** `C:\Users\david\PC_AI\Deploy\pcai-inference\cmake\toolchain-msvc.cmake`

```cmake
# MSVC Toolchain for llama.cpp on Windows
# Ensures proper compiler selection for llama-cpp-2

cmake_minimum_required(VERSION 3.20)

# Detect Visual Studio installation
if(NOT DEFINED MSVC_ROOT)
    # Try Build Tools first, then Community
    if(EXISTS "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools")
        set(MSVC_ROOT "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools")
    elseif(EXISTS "C:/Program Files/Microsoft Visual Studio/2022/Community")
        set(MSVC_ROOT "C:/Program Files/Microsoft Visual Studio/2022/Community")
    else()
        message(FATAL_ERROR "Visual Studio 2022 not found")
    endif()
endif()

# Find latest MSVC toolset
file(GLOB MSVC_VERSIONS LIST_DIRECTORIES true
     "${MSVC_ROOT}/VC/Tools/MSVC/*")
list(SORT MSVC_VERSIONS COMPARE NATURAL ORDER DESCENDING)
list(GET MSVC_VERSIONS 0 MSVC_TOOLSET)

# Set absolute paths to MSVC compilers
set(CMAKE_C_COMPILER "${MSVC_TOOLSET}/bin/Hostx64/x64/cl.exe" CACHE FILEPATH "C compiler" FORCE)
set(CMAKE_CXX_COMPILER "${MSVC_TOOLSET}/bin/Hostx64/x64/cl.exe" CACHE FILEPATH "C++ compiler" FORCE)

# Windows SDK
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)

# MSVC-specific flags
set(CMAKE_C_FLAGS_INIT "/W3 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS /nologo")
set(CMAKE_CXX_FLAGS_INIT "/W3 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS /EHsc /nologo")

# Release optimization (AVX2 for modern CPUs)
set(CMAKE_C_FLAGS_RELEASE_INIT "/O2 /Ob2 /DNDEBUG /arch:AVX2")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "/O2 /Ob2 /DNDEBUG /arch:AVX2")

# Debug flags
set(CMAKE_C_FLAGS_DEBUG_INIT "/Zi /Od /D_DEBUG")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "/Zi /Od /D_DEBUG")

# CUDA support (optional)
if(DEFINED ENV{CUDA_PATH})
    set(CMAKE_CUDA_COMPILER "$ENV{CUDA_PATH}/bin/nvcc.exe" CACHE FILEPATH "CUDA compiler" FORCE)
    set(CMAKE_CUDA_HOST_COMPILER "${CMAKE_CXX_COMPILER}" CACHE FILEPATH "CUDA host compiler" FORCE)
    message(STATUS "CUDA detected at: $ENV{CUDA_PATH}")
endif()

# Linker flags
set(CMAKE_EXE_LINKER_FLAGS_INIT "/MACHINE:X64 /NOLOGO")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "/MACHINE:X64 /NOLOGO")

message(STATUS "MSVC Toolchain Configuration:")
message(STATUS "  Root: ${MSVC_ROOT}")
message(STATUS "  Toolset: ${MSVC_TOOLSET}")
message(STATUS "  C Compiler: ${CMAKE_C_COMPILER}")
message(STATUS "  C++ Compiler: ${CMAKE_CXX_COMPILER}")
```

**Key Changes:**
- Auto-detects Visual Studio installation
- Uses absolute paths with CACHE FORCE to override environment
- Finds latest MSVC toolset dynamically
- Adds AVX2 optimization for modern CPUs
- Better status messages for debugging

### Fix 2: Update build.ps1 Environment Setup

**File:** `C:\Users\david\PC_AI\Deploy\pcai-inference\build.ps1`

Add after `Initialize-MsvcEnvironment` function:

```powershell
function Set-MsvcEnvironmentVariables {
    <#
    .SYNOPSIS
        Sets environment variables required for MSVC compilation
    #>
    param(
        [switch]$EnableCuda
    )

    Write-Host "  Setting MSVC environment variables..." -ForegroundColor Cyan

    # Find MSVC installation
    $vsPath = Find-VsInstallPath
    if (-not $vsPath) {
        throw "Visual Studio installation not found"
    }

    # Find latest MSVC toolset
    $msvcVersions = Get-ChildItem "$vsPath\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending
    $msvcToolset = $msvcVersions[0].FullName

    $clExe = Join-Path $msvcToolset "bin\Hostx64\x64\cl.exe"
    if (-not (Test-Path $clExe)) {
        throw "MSVC compiler not found at: $clExe"
    }

    # Override compiler environment variables (critical for llama-cpp-2)
    $env:CC = $clExe
    $env:CXX = $clExe
    $env:CMAKE_C_COMPILER = $clExe
    $env:CMAKE_CXX_COMPILER = $clExe

    # Set CMake configuration
    $env:CMAKE_GENERATOR = 'Ninja'
    $env:CMAKE_BUILD_TYPE = $Configuration

    # Set toolchain file path
    $toolchainFile = Join-Path $ProjectRoot 'cmake\toolchain-msvc.cmake'
    $env:CMAKE_TOOLCHAIN_FILE = $toolchainFile

    # CUDA configuration
    if ($EnableCuda) {
        $cudaPath = Find-CudaPath
        if ($cudaPath) {
            $env:CUDA_PATH = $cudaPath
            $env:CUDA_HOME = $cudaPath
            $env:LLAMA_CUDA = '1'
            Write-Host "  CUDA: $cudaPath" -ForegroundColor Green
        } else {
            Write-Host "  CUDA: Not found, building CPU-only" -ForegroundColor Yellow
            $env:LLAMA_CUDA = '0'
        }
    } else {
        $env:LLAMA_CUDA = '0'
    }

    Write-Host "  CC: $env:CC" -ForegroundColor Green
    Write-Host "  CXX: $env:CXX" -ForegroundColor Green
    Write-Host "  CMAKE_GENERATOR: $env:CMAKE_GENERATOR" -ForegroundColor Green
    Write-Host "  CMAKE_TOOLCHAIN_FILE: $env:CMAKE_TOOLCHAIN_FILE" -ForegroundColor Green
}

function Find-VsInstallPath {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        return $null
    }
    & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}

function Find-CudaPath {
    # Check environment variable first
    if ($env:CUDA_PATH -and (Test-Path $env:CUDA_PATH)) {
        return $env:CUDA_PATH
    }

    # Find latest CUDA installation
    $cudaRoot = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    if (Test-Path $cudaRoot) {
        $versions = Get-ChildItem $cudaRoot -Directory | Sort-Object Name -Descending
        if ($versions.Count -gt 0) {
            return $versions[0].FullName
        }
    }

    return $null
}
```

Update `Build-LlamaCppBackend` function:

```powershell
function Build-LlamaCppBackend {
    Write-Host "`n=== Building llamacpp backend ===" -ForegroundColor Magenta

    # Initialize MSVC environment (adds to PATH)
    Initialize-MsvcEnvironment

    # Set critical environment variables
    Set-MsvcEnvironmentVariables -EnableCuda:$EnableCuda

    # Build features
    $features = @('llamacpp', 'ffi', 'server')
    if ($EnableCuda -and $env:LLAMA_CUDA -eq '1') {
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
```

### Fix 3: Add Environment Verification Script

**File:** `C:\Users\david\PC_AI\Deploy\pcai-inference\verify-env.ps1`

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Verify build environment for pcai-inference
#>

Write-Host "Verifying Build Environment" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

# Check Visual Studio
Write-Host "`n1. Visual Studio Installation" -ForegroundColor Yellow
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -property installationPath
    Write-Host "  Found: $vsPath" -ForegroundColor Green

    # Check for C++ tools
    $vcVars = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (Test-Path $vcVars) {
        Write-Host "  C++ Tools: Installed" -ForegroundColor Green
    } else {
        Write-Host "  C++ Tools: Missing" -ForegroundColor Red
    }
} else {
    Write-Host "  Not Found" -ForegroundColor Red
}

# Check MSVC compiler
Write-Host "`n2. MSVC Compiler" -ForegroundColor Yellow
if ($vsPath) {
    $msvcVersions = Get-ChildItem "$vsPath\VC\Tools\MSVC" -Directory -ErrorAction SilentlyContinue
    if ($msvcVersions) {
        $latest = ($msvcVersions | Sort-Object Name -Descending)[0]
        $clExe = Join-Path $latest.FullName "bin\Hostx64\x64\cl.exe"
        if (Test-Path $clExe) {
            Write-Host "  Version: $($latest.Name)" -ForegroundColor Green
            Write-Host "  Path: $clExe" -ForegroundColor Green
        }
    }
}

# Check current environment
Write-Host "`n3. Environment Variables" -ForegroundColor Yellow
$envVars = @('CC', 'CXX', 'CMAKE_GENERATOR', 'CMAKE_TOOLCHAIN_FILE', 'CUDA_PATH')
foreach ($var in $envVars) {
    $value = [Environment]::GetEnvironmentVariable($var, 'Process')
    if ($value) {
        $color = if ($var -eq 'CC' -and $value -like '*gcc*') { 'Red' } else { 'Green' }
        Write-Host "  $var = $value" -ForegroundColor $color
    } else {
        Write-Host "  $var = (not set)" -ForegroundColor Gray
    }
}

# Check CMake
Write-Host "`n4. CMake" -ForegroundColor Yellow
if (Get-Command cmake -ErrorAction SilentlyContinue) {
    $cmakeVer = (cmake --version | Select-Object -First 1)
    Write-Host "  $cmakeVer" -ForegroundColor Green
} else {
    Write-Host "  Not Found" -ForegroundColor Red
}

# Check Ninja
Write-Host "`n5. Ninja Build System" -ForegroundColor Yellow
if (Get-Command ninja -ErrorAction SilentlyContinue) {
    $ninjaVer = (ninja --version)
    Write-Host "  Version: $ninjaVer" -ForegroundColor Green
} else {
    Write-Host "  Not Found (optional)" -ForegroundColor Yellow
}

# Check CUDA
Write-Host "`n6. CUDA Toolkit" -ForegroundColor Yellow
$cudaRoot = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
if (Test-Path $cudaRoot) {
    $cudaVersions = Get-ChildItem $cudaRoot -Directory | Sort-Object Name -Descending
    if ($cudaVersions) {
        Write-Host "  Installed Versions:" -ForegroundColor Green
        foreach ($ver in $cudaVersions) {
            Write-Host "    - $($ver.Name)" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  Not Found (optional for GPU support)" -ForegroundColor Yellow
}

# Check Rust
Write-Host "`n7. Rust Toolchain" -ForegroundColor Yellow
if (Get-Command rustc -ErrorAction SilentlyContinue) {
    $rustVer = (rustc --version)
    Write-Host "  $rustVer" -ForegroundColor Green

    $cargoVer = (cargo --version)
    Write-Host "  $cargoVer" -ForegroundColor Green
} else {
    Write-Host "  Not Found" -ForegroundColor Red
}

Write-Host "`n" ("=" * 60) -ForegroundColor Cyan
Write-Host "Verification Complete" -ForegroundColor Cyan
```

### Fix 4: Quick Build Command for Testing

**File:** `C:\Users\david\PC_AI\Deploy\pcai-inference\test-build.ps1`

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Quick test build for MSVC configuration
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# Change to project directory
Set-Location $PSScriptRoot

Write-Host "Testing MSVC Build Configuration" -ForegroundColor Cyan
Write-Host ("=" * 60)

# Step 1: Verify environment
Write-Host "`n[1/4] Verifying environment..." -ForegroundColor Yellow
& .\verify-env.ps1

# Step 2: Initialize MSVC
Write-Host "`n[2/4] Initializing MSVC environment..." -ForegroundColor Yellow
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -property installationPath
$devShell = Join-Path $vsPath 'Common7\Tools\Launch-VsDevShell.ps1'

if (Test-Path $devShell) {
    & $devShell -SkipAutomaticLocation -HostArch amd64 -Arch amd64
    Write-Host "MSVC environment initialized" -ForegroundColor Green
} else {
    throw "VS DevShell not found"
}

# Step 3: Set override variables
Write-Host "`n[3/4] Setting compiler overrides..." -ForegroundColor Yellow

$msvcVersions = Get-ChildItem "$vsPath\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending
$msvcToolset = $msvcVersions[0].FullName
$clExe = Join-Path $msvcToolset "bin\Hostx64\x64\cl.exe"

$env:CC = $clExe
$env:CXX = $clExe
$env:CMAKE_C_COMPILER = $clExe
$env:CMAKE_CXX_COMPILER = $clExe
$env:CMAKE_GENERATOR = 'Ninja'
$env:CMAKE_TOOLCHAIN_FILE = Join-Path $PSScriptRoot 'cmake\toolchain-msvc.cmake'
$env:LLAMA_CUDA = '0'

Write-Host "CC = $env:CC" -ForegroundColor Green
Write-Host "CXX = $env:CXX" -ForegroundColor Green
Write-Host "CMAKE_TOOLCHAIN_FILE = $env:CMAKE_TOOLCHAIN_FILE" -ForegroundColor Green

# Step 4: Test build
Write-Host "`n[4/4] Running test build (CPU-only, no features)..." -ForegroundColor Yellow

$buildArgs = @('build', '--no-default-features', '--lib')
if ($Verbose) {
    $buildArgs += '--verbose'
}

Write-Host "Command: cargo $($buildArgs -join ' ')" -ForegroundColor Gray

try {
    & cargo @buildArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nBuild Successful!" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
    } else {
        Write-Host "`nBuild Failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
} catch {
    Write-Host "`nBuild Error: $_" -ForegroundColor Red
    throw
}
```

---

## Testing Procedure

### Step 1: Verify Current Environment

```powershell
cd C:\Users\david\PC_AI\Deploy\pcai-inference
.\verify-env.ps1
```

Expected output should show:
- Visual Studio 2022 installed
- MSVC 14.44.35207 available
- CC pointing to gcc.exe (problem)

### Step 2: Update Toolchain File

Apply Fix 1 to `cmake/toolchain-msvc.cmake`

### Step 3: Update Build Script

Apply Fix 2 to `build.ps1`

### Step 4: Run Test Build

```powershell
.\test-build.ps1 -Verbose
```

This should:
1. Initialize MSVC environment
2. Override CC/CXX to point to cl.exe
3. Attempt a minimal build
4. Show CMake detecting MSVC (not GNU)

### Step 5: Full Build with llama.cpp

```powershell
.\build.ps1 -Backend llamacpp -Configuration Release
```

Expected: llama-cpp-2 builds successfully with MSVC

### Step 6: CUDA Build (if needed)

```powershell
.\build.ps1 -Backend llamacpp -Configuration Release -EnableCuda
```

Expected: Builds with CUDA 13.1 support

---

## Expected CMake Output (After Fix)

```
-- The C compiler identification is MSVC 19.44.35207.0
-- The CXX compiler identification is MSVC 19.44.35207.0
-- MSVC Toolchain Configuration:
--   Root: C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools
--   Toolset: C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207
--   C Compiler: C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe
--   C++ Compiler: C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe
-- Using MSVC toolchain for Windows x64
```

**Key Change:** "MSVC 19.44" instead of "GNU"

---

## Environment Variables Reference

### Required for MSVC Build

| Variable | Value | Set By |
|----------|-------|--------|
| `CC` | `<path>\cl.exe` | build.ps1 |
| `CXX` | `<path>\cl.exe` | build.ps1 |
| `CMAKE_C_COMPILER` | `<path>\cl.exe` | build.ps1 |
| `CMAKE_CXX_COMPILER` | `<path>\cl.exe` | build.ps1 |
| `CMAKE_GENERATOR` | `Ninja` | build.ps1 |
| `CMAKE_TOOLCHAIN_FILE` | `cmake/toolchain-msvc.cmake` | build.ps1 |
| `CMAKE_BUILD_TYPE` | `Release` or `Debug` | build.ps1 |

### Optional for CUDA

| Variable | Value | Set By |
|----------|-------|--------|
| `CUDA_PATH` | `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1` | build.ps1 |
| `CUDA_HOME` | Same as CUDA_PATH | build.ps1 |
| `LLAMA_CUDA` | `1` | build.ps1 |

### Must NOT Be Set (Conflicting)

| Variable | Current Value | Problem |
|----------|---------------|---------|
| `CC` | `C:/Strawberry/c/bin/gcc.exe` | Points to GCC |

---

## Troubleshooting

### Issue: CMake still detects GNU

**Check:**
```powershell
Get-ChildItem env: | Where-Object { $_.Name -match 'CC|CXX|CMAKE' }
```

**Fix:** Ensure CC/CXX are set AFTER VS DevShell initialization

### Issue: cl.exe not found

**Check:**
```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe"
```

**Fix:** Install "Desktop development with C++" workload in VS Installer

### Issue: CUDA not detected

**Check:**
```powershell
Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA" -Directory
```

**Fix:** Install CUDA Toolkit from NVIDIA or disable CUDA builds

### Issue: Ninja not found

**Check:**
```powershell
Get-Command ninja -ErrorAction SilentlyContinue
```

**Fix:** Install via `winget install Ninja-build.Ninja` or use default generator

---

## Performance Comparison

### Build Times (Estimated)

| Configuration | Backend | Build Time | Notes |
|---------------|---------|------------|-------|
| CPU (GCC) | llama.cpp | 8-12 min | Current broken state |
| CPU (MSVC) | llama.cpp | 6-10 min | After fixes, AVX2 optimized |
| CUDA (MSVC) | llama.cpp | 10-15 min | CUDA 13.1, compute 8.9 |
| CPU | mistral.rs | 15-20 min | Already working |

### Runtime Performance

| Configuration | Tokens/sec (7B model) | Notes |
|---------------|----------------------|-------|
| CPU (GCC) | N/A | Doesn't build |
| CPU (MSVC AVX2) | ~25-35 | Intel/AMD modern CPUs |
| CUDA (RTX 40xx) | ~200-400 | Depends on VRAM |

---

## Next Steps

1. **Apply toolchain fixes** (this document)
2. **Test minimal build** (verify-env.ps1 + test-build.ps1)
3. **Update CI/CD** (GitHub Actions needs same environment setup)
4. **Document** (update Deploy/pcai-inference/README.md)
5. **Validate** (run full test suite)

---

## References

- **CMake Toolchain Files:** https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html
- **MSVC Compiler Options:** https://learn.microsoft.com/en-us/cpp/build/reference/compiler-options
- **llama-cpp-2 Crate:** https://crates.io/crates/llama-cpp-2
- **VS DevShell:** https://learn.microsoft.com/en-us/visualstudio/ide/reference/command-prompt-powershell

---

**Analysis Complete**
Ready for implementation and testing.
