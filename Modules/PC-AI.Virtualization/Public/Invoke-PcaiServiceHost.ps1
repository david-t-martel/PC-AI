#Requires -Version 5.1

<#
.SYNOPSIS
    Starts the PC_AI inference service (Rust or legacy C# backend).

.DESCRIPTION
    Launches the pcai-inference Rust server or legacy C# service host.
    The Rust backend is preferred and provides dual-backend support
    (llamacpp and mistralrs) with GPU acceleration.

.PARAMETER Backend
    Backend to use: 'rust' (default), 'csharp' (legacy)

.PARAMETER Port
    HTTP server port. Default: 8080

.PARAMETER ModelPath
    Path to GGUF model file for native loading

.PARAMETER GpuLayers
    Number of layers to offload to GPU (-1 = auto)

.PARAMETER ServerArgs
    Additional arguments to pass to the server

.PARAMETER NoWait
    Start server in background without waiting

.EXAMPLE
    Invoke-PcaiServiceHost
    Starts the Rust inference server on default port

.EXAMPLE
    Invoke-PcaiServiceHost -ModelPath "C:\models\mistral-7b.gguf" -GpuLayers 35
    Starts server with specific model and GPU offloading

.EXAMPLE
    Invoke-PcaiServiceHost -Backend csharp -ServerArgs @('--mode', 'diagnostic')
    Starts legacy C# service host
#>
function Invoke-PcaiServiceHost {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('rust', 'csharp', 'auto')]
        [string]$Backend = 'auto',

        [Parameter()]
        [int]$Port = 8080,

        [Parameter()]
        [string]$ModelPath,

        [Parameter()]
        [int]$GpuLayers = -1,

        [Parameter()]
        [string[]]$ServerArgs,

        [Parameter()]
        [switch]$NoWait,

        # Legacy parameter for backward compatibility
        [Parameter()]
        [string]$HostPath
    )

    # Determine backend
    if ($Backend -eq 'auto') {
        # Check for Rust binary first
        $rustExePaths = @(
            'T:\RustCache\cargo-target\release\pcai-inference.exe',
            "$PSScriptRoot\..\..\..\Deploy\pcai-inference\target\release\pcai-inference.exe",
            "$env:USERPROFILE\PC_AI\Deploy\pcai-inference\target\release\pcai-inference.exe"
        )

        $rustExe = $rustExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($rustExe) {
            $Backend = 'rust'
        } else {
            $Backend = 'csharp'
        }
    }

    if ($Backend -eq 'rust') {
        return Start-RustInferenceServer -Port $Port -ModelPath $ModelPath -GpuLayers $GpuLayers -ServerArgs $ServerArgs -NoWait:$NoWait
    } else {
        return Start-CSharpServiceHost -HostPath $HostPath -ServerArgs $ServerArgs -NoWait:$NoWait
    }
}

function Start-RustInferenceServer {
    [CmdletBinding()]
    param(
        [int]$Port = 8080,
        [string]$ModelPath,
        [int]$GpuLayers = -1,
        [string[]]$ServerArgs,
        [switch]$NoWait
    )

    # Find Rust executable
    $rustExePaths = @(
        'T:\RustCache\cargo-target\release\pcai-inference.exe',
        "$PSScriptRoot\..\..\..\Deploy\pcai-inference\target\release\pcai-inference.exe",
        "$env:USERPROFILE\PC_AI\Deploy\pcai-inference\target\release\pcai-inference.exe"
    )

    $rustExe = $rustExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $rustExe) {
        throw @"
pcai-inference.exe not found. Build it with:

    cd Deploy\pcai-inference
    cargo build --release --features server,llamacpp

Or with mistralrs backend:
    cargo build --release --features server,mistralrs-backend
"@
    }

    # Build arguments
    $args = @('--port', $Port.ToString())

    if ($ModelPath) {
        $args += @('--model-path', $ModelPath)
    }

    if ($GpuLayers -ge 0) {
        $args += @('--gpu-layers', $GpuLayers.ToString())
    }

    if ($ServerArgs) {
        $args += $ServerArgs
    }

    Write-Verbose "Starting: $rustExe $($args -join ' ')"

    if ($NoWait) {
        $process = Start-Process -FilePath $rustExe -ArgumentList $args -PassThru -WindowStyle Hidden
        return [PSCustomObject]@{
            Backend   = 'rust'
            ExePath   = $rustExe
            Args      = $args
            ProcessId = $process.Id
            Port      = $Port
            Success   = $true
            Message   = "Server started in background (PID: $($process.Id))"
        }
    } else {
        # Run and capture output
        $output = & $rustExe @args 2>&1
        $exitCode = $LASTEXITCODE

        return [PSCustomObject]@{
            Backend  = 'rust'
            ExePath  = $rustExe
            Args     = $args
            ExitCode = $exitCode
            Output   = ($output | Out-String).Trim()
            Success  = ($exitCode -eq 0)
        }
    }
}

function Start-CSharpServiceHost {
    [CmdletBinding()]
    param(
        [string]$HostPath,
        [string[]]$ServerArgs,
        [switch]$NoWait
    )

    if (-not $HostPath) {
        $HostPath = 'C:\Users\david\PC_AI\Native\PcaiServiceHost\bin\Release\net8.0\PcaiServiceHost.dll'
    }

    if (-not (Test-Path $HostPath)) {
        throw "PcaiServiceHost not found at $HostPath. Build with: dotnet build -c Release"
    }

    $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue)?.Source
    if (-not $dotnet) {
        throw 'dotnet not found in PATH.'
    }

    Write-Verbose "Starting: dotnet $HostPath $($ServerArgs -join ' ')"

    if ($NoWait) {
        $process = Start-Process -FilePath $dotnet -ArgumentList @($HostPath) + $ServerArgs -PassThru -WindowStyle Hidden
        return [PSCustomObject]@{
            Backend   = 'csharp'
            HostPath  = $HostPath
            Args      = $ServerArgs
            ProcessId = $process.Id
            Success   = $true
            Message   = "Service host started in background (PID: $($process.Id))"
        }
    } else {
        $output = & $dotnet $HostPath @ServerArgs 2>&1
        $exitCode = $LASTEXITCODE

        return [PSCustomObject]@{
            Backend  = 'csharp'
            HostPath = $HostPath
            Args     = $ServerArgs
            ExitCode = $exitCode
            Output   = ($output | Out-String).Trim()
            Success  = ($exitCode -eq 0)
        }
    }
}
