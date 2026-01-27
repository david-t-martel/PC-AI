#Requires -Version 5.1
<#+
.SYNOPSIS
    Installs and enables the PC_AI VSock bridge in WSL.
#>
function Install-WSLVsockBridge {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Distribution = 'Ubuntu',

        [Parameter()]
        [string]$BridgeScriptPath = 'C:\Users\david\PC_AI\Tools\pcai-vsock-bridge.sh',

        [Parameter()]
        [string]$ServiceFilePath = 'C:\Users\david\PC_AI\Tools\pcai-vsock-bridge.service',

        [Parameter()]
        [string]$ConfigPath = 'C:\Users\david\PC_AI\Config\vsock-bridges.conf',

        [Parameter()]
        [switch]$EnableService = $true,

        [Parameter()]
        [switch]$StartService = $true
    )

    $result = [PSCustomObject]@{
        Distribution = $Distribution
        ScriptInstalled = $false
        ServiceInstalled = $false
        ConfigInstalled = $false
        SocatInstalled = $false
        ServiceEnabled = $false
        ServiceStarted = $false
        Errors = @()
    }

    try {
        if (-not (Test-Path $BridgeScriptPath)) { throw "Bridge script not found: $BridgeScriptPath" }
        if (-not (Test-Path $ServiceFilePath)) { throw "Service file not found: $ServiceFilePath" }
        if (-not (Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }

        # Ensure systemd enabled
        Enable-WSLSystemd -Distribution $Distribution -RestartWSL | Out-Null

        # Ensure distro is up
        & wsl -d $Distribution -- echo "WSL up" 2>$null | Out-Null

        # Install socat if missing
        $socatCheck = wsl -d $Distribution -- bash -lc "command -v socat >/dev/null 2>&1" 2>$null
        if ($LASTEXITCODE -ne 0) {
            wsl -d $Distribution -- bash -lc "sudo apt-get update && sudo apt-get install -y socat" | Out-Null
        }
        $socatCheck = wsl -d $Distribution -- bash -lc "command -v socat >/dev/null 2>&1" 2>$null
        if ($LASTEXITCODE -eq 0) { $result.SocatInstalled = $true }

        # Copy bridge script
        $bridgeWslPath = '/usr/local/bin/pcai-vsock-bridge'
        wsl -d $Distribution -- bash -lc "sudo cp /mnt/c/Users/david/PC_AI/Tools/pcai-vsock-bridge.sh $bridgeWslPath && sudo chmod 755 $bridgeWslPath" | Out-Null
        $result.ScriptInstalled = $true

        # Copy config
        wsl -d $Distribution -- bash -lc "sudo mkdir -p /etc/pcai && sudo cp /mnt/c/Users/david/PC_AI/Config/vsock-bridges.conf /etc/pcai/vsock-bridges.conf" | Out-Null
        $result.ConfigInstalled = $true

        # Copy systemd service
        wsl -d $Distribution -- bash -lc "sudo cp /mnt/c/Users/david/PC_AI/Tools/pcai-vsock-bridge.service /etc/systemd/system/pcai-vsock-bridge.service" | Out-Null
        wsl -d $Distribution -- bash -lc "sudo systemctl daemon-reload" | Out-Null
        $result.ServiceInstalled = $true

        if ($EnableService) {
            wsl -d $Distribution -- bash -lc "sudo systemctl enable pcai-vsock-bridge" | Out-Null
            $result.ServiceEnabled = $true
        }

        if ($StartService) {
            wsl -d $Distribution -- bash -lc "sudo systemctl restart pcai-vsock-bridge" | Out-Null
            $result.ServiceStarted = $true
        }
    }
    catch {
        $result.Errors += $_.Exception.Message
    }

    return $result
}
