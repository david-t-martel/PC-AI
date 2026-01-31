#Requires -Version 5.1
<#
.SYNOPSIS
    Initializes CUDA environment variables for the current PowerShell session.

.DESCRIPTION
    Detects installed CUDA toolkits using a preferred version list and common
    environment variables, then sets CUDA_PATH/CUDA_HOME and updates PATH with
    CUDA bin and nvvm/bin. Intended for build and doc pipelines (non-destructive).

.PARAMETER PreferredVersions
    Ordered list of CUDA versions to probe under the standard Windows install path.

.PARAMETER CudaPath
    Explicit CUDA installation path to prefer over auto-detection.

.PARAMETER Quiet
    Suppress informational output (still returns a result object).
#>
[CmdletBinding()]
param(
    [string[]]$PreferredVersions = @('v13.1', 'v13.0', 'v12.6', 'v12.5'),
    [string]$CudaPath,
    [switch]$Quiet
)

function Add-ToPath {
    param([string]$PathSegment)
    if (-not $PathSegment) { return $false }
    if (-not (Test-Path $PathSegment)) { return $false }
    if ($env:PATH -notlike "*$PathSegment*") {
        $env:PATH = "$PathSegment;$env:PATH"
        return $true
    }
    return $false
}

function Add-ToEnvList {
    param(
        [string]$Name,
        [string]$Value
    )
    if (-not $Name -or -not $Value) { return $false }
    if (-not (Test-Path $Value)) { return $false }
    $item = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
    $current = if ($item) { $item.Value } else { $null }
    if ($current -notlike "*$Value*") {
        if ($current) {
            Set-Item -Path "Env:$Name" -Value "$Value;$current"
        } else {
            Set-Item -Path "Env:$Name" -Value "$Value"
        }
        return $true
    }
    return $false
}

function Get-ShortPath {
    param([string]$Path)
    if (-not $Path) { return $null }
    try {
        $short = & cmd /c "for %I in (\"$Path\") do @echo %~sI" 2>$null
        $short = $short | Select-Object -First 1
        if ($short) {
            $short = $short.Trim()
            if ($short -and (Test-Path $short)) { return $short }
        }
    } catch {
        return $null
    }
    return $null
}

function Get-CudaCandidates {
    param(
        [string[]]$PreferredVersions,
        [string]$CudaPath
    )
    $candidates = @()
    if ($CudaPath) { $candidates += $CudaPath }
    if ($env:CUDA_PATH) { $candidates += $env:CUDA_PATH }
    if ($env:CUDA_HOME) { $candidates += $env:CUDA_HOME }

    $envCandidates = Get-ChildItem Env:CUDA_PATH_V* -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Value }
    if ($envCandidates) { $candidates += $envCandidates }

    foreach ($ver in $PreferredVersions) {
        $candidates += "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\$ver"
    }

    return $candidates |
        Where-Object { $_ -and $_.Trim().Length -gt 0 } |
        Select-Object -Unique
}

function Initialize-CudaEnvironment {
    [CmdletBinding()]
    param(
        [string[]]$PreferredVersions = @('v13.1', 'v13.0', 'v12.6', 'v12.5'),
        [string]$CudaPath,
        [switch]$Quiet
    )

    $candidates = Get-CudaCandidates -PreferredVersions $PreferredVersions -CudaPath $CudaPath
    $selected = $null
    $reasons = @()

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) {
            $reasons += "Not found: $candidate"
            continue
        }

        $nvcc = Join-Path $candidate 'bin\nvcc.exe'
        $include = Join-Path $candidate 'include\cuda_runtime.h'

        if (-not (Test-Path $nvcc)) {
            $reasons += "nvcc missing: $candidate"
            continue
        }
        if (-not (Test-Path $include)) {
            $reasons += "cuda_runtime.h missing: $candidate"
            continue
        }

        $selected = $candidate
        break
    }

    if (-not $selected) {
        return [PSCustomObject]@{
            Found = $false
            CudaPath = $null
            Nvcc = $null
            Cicc = $null
            Include = $null
            PathUpdated = $false
            Notes = $reasons
        }
    }

    $shortPath = Get-ShortPath -Path $selected
    if ($shortPath -and ($shortPath -ne $selected)) {
        $selected = $shortPath
    }

    # SET EXPLICIT ENVIRONMENT VARIABLES (no fallbacks)
    $env:CUDA_PATH = $selected
    $env:CUDA_HOME = $selected
    $env:CUDA_DIR = $selected

    $pathUpdated = $false
    $pathUpdated = (Add-ToPath (Join-Path $selected 'bin')) -or $pathUpdated
    $pathUpdated = (Add-ToPath (Join-Path $selected 'nvvm\bin')) -or $pathUpdated
    $pathUpdated = (Add-ToPath (Join-Path $selected 'libnvvp')) -or $pathUpdated

    $includeDir = Join-Path $selected 'include'
    $libDir = Join-Path $selected 'lib\x64'
    $includeUpdated = Add-ToEnvList -Name 'INCLUDE' -Value $includeDir
    $libUpdated = Add-ToEnvList -Name 'LIB' -Value $libDir

    $nvccPath = Join-Path $selected 'bin\nvcc.exe'
    $ciccPath = Join-Path $selected 'nvvm\bin\cicc.exe'
    $includePath = Join-Path $selected 'include\cuda_runtime.h'
    $libPath = Join-Path $selected 'lib\x64'

    # Set CMake-specific CUDA variables (no fallbacks)
    $env:CMAKE_CUDA_COMPILER = ($nvccPath -replace '\\', '/')
    $env:CUDAToolkit_ROOT = ($selected -replace '\\', '/')

    # Set CUDA compute capabilities for common architectures
    # 75=Turing, 80=Ampere, 86=GA102, 89=Ada, 90=Hopper
    if (-not $env:CUDAARCHS) {
        $env:CUDAARCHS = "75;80;86;89"
    }

    $result = [PSCustomObject]@{
        Found = $true
        CudaPath = $selected
        Nvcc = $nvccPath
        Cicc = $ciccPath
        Include = $includePath
        Lib = $libPath
        PathUpdated = $pathUpdated
        IncludeUpdated = $includeUpdated
        LibUpdated = $libUpdated
        CudaArchs = $env:CUDAARCHS
        Notes = @()
    }

    if (-not $Quiet) {
        Write-Host "CUDA detected at: $selected" -ForegroundColor Green
        Write-Host "  nvcc:                 $nvccPath" -ForegroundColor DarkGray
        Write-Host "  cicc:                 $ciccPath" -ForegroundColor DarkGray
        Write-Host "  CMAKE_CUDA_COMPILER:  $nvccPath" -ForegroundColor DarkGray
        Write-Host "  CUDAARCHS:            $($env:CUDAARCHS)" -ForegroundColor DarkGray
    }

    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    Initialize-CudaEnvironment -PreferredVersions $PreferredVersions -CudaPath $CudaPath -Quiet:$Quiet
}
