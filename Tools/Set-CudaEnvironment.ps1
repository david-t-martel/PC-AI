<#
.SYNOPSIS
    Sets up CUDA environment variables for Rust/candle-core compilation.
.DESCRIPTION
    Configures CUDA_PATH and adds nvvm/bin to PATH for cicc compiler access.
#>
[CmdletBinding()]
param(
    [string]$CudaVersion = "v13.0"
)

$cudaBase = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\$CudaVersion"

if (-not (Test-Path $cudaBase)) {
    Write-Error "CUDA $CudaVersion not found at $cudaBase"
    exit 1
}

# Set CUDA_PATH
$currentCudaPath = [System.Environment]::GetEnvironmentVariable('CUDA_PATH', 'Machine')
if ($currentCudaPath -ne $cudaBase) {
    Write-Host "Setting CUDA_PATH to $cudaBase"
    [System.Environment]::SetEnvironmentVariable('CUDA_PATH', $cudaBase, 'Machine')
} else {
    Write-Host "CUDA_PATH already set to $cudaBase"
}

# Add CUDA bin to PATH for nvcc
$cudaBin = "$cudaBase\bin"
$currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')

if ($currentPath -notlike "*$cudaBin*") {
    Write-Host "Adding $cudaBin to system PATH"
    $currentPath = "$currentPath;$cudaBin"
    [System.Environment]::SetEnvironmentVariable('Path', $currentPath, 'Machine')
} else {
    Write-Host "CUDA bin already in PATH"
}

# Add nvvm/bin to PATH for cicc
$nvvmBin = "$cudaBase\nvvm\bin"

if ($currentPath -notlike "*$nvvmBin*") {
    Write-Host "Adding $nvvmBin to system PATH"
    $currentPath = "$currentPath;$nvvmBin"
    [System.Environment]::SetEnvironmentVariable('Path', $currentPath, 'Machine')
} else {
    Write-Host "nvvm/bin already in PATH"
}

# Add libnvvp to PATH
$libnvvp = "$cudaBase\libnvvp"
if ((Test-Path $libnvvp) -and ($currentPath -notlike "*$libnvvp*")) {
    Write-Host "Adding $libnvvp to system PATH"
    [System.Environment]::SetEnvironmentVariable('Path', "$currentPath;$libnvvp", 'Machine')
}

# Verify
Write-Host "`nVerification:"
Write-Host "  CUDA_PATH: $([System.Environment]::GetEnvironmentVariable('CUDA_PATH', 'Machine'))"
Write-Host "  cicc.exe exists: $(Test-Path "$nvvmBin\cicc.exe")"
Write-Host "  nvcc.exe exists: $(Test-Path "$cudaBase\bin\nvcc.exe")"

Write-Host "`nNote: You may need to restart your terminal for PATH changes to take effect."
