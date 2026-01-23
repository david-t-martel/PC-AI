# ============================================================================
# WSL and Docker Health Check Script
# Comprehensive health verification and auto-recovery
# ============================================================================

param(
    [switch]$AutoRecover,
    [switch]$Verbose,
    [switch]$Quick
)

$ErrorActionPreference = "Continue"

# Status tracking
$script:HealthStatus = @{
    WSL = "Unknown"
    Docker = "Unknown"
    HyperVBridges = "Unknown"
    Network = "Unknown"
    OverallHealth = "Unknown"
}

$script:Issues = @()

function Write-Status {
    param([string]$Component, [string]$Status, [string]$Message)

    $color = switch ($Status) {
        "OK" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "White" }
    }

    $symbol = switch ($Status) {
        "OK" { "[OK]" }
        "Warning" { "[!!]" }
        "Error" { "[XX]" }
        default { "[??]" }
    }

    Write-Host "$symbol " -ForegroundColor $color -NoNewline
    Write-Host "$Component`: " -NoNewline
    Write-Host $Message -ForegroundColor $color

    $script:HealthStatus[$Component] = $Status
}

function Test-WSL {
    Write-Host "`n=== WSL Health Check ===" -ForegroundColor Cyan

    # Check if WSL is running
    $wslList = wsl -l -v 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Status "WSL" "Error" "WSL command failed"
        $script:Issues += "WSL not responding"
        return $false
    }

    # Check Ubuntu distro
    $ubuntuRunning = $wslList | Select-String "Ubuntu.*Running"
    if (-not $ubuntuRunning) {
        Write-Status "WSL" "Warning" "Ubuntu distro not running"
        $script:Issues += "Ubuntu WSL not running"

        if ($AutoRecover) {
            Write-Host "  Attempting to start Ubuntu..." -ForegroundColor Yellow
            wsl -d Ubuntu -- echo "Started" 2>&1 | Out-Null
            Start-Sleep -Seconds 3
            $ubuntuRunning = (wsl -l -v 2>&1) | Select-String "Ubuntu.*Running"
            if ($ubuntuRunning) {
                Write-Status "WSL" "OK" "Ubuntu started successfully"
                return $true
            }
        }
        return $false
    }

    Write-Status "WSL" "OK" "Ubuntu is running"

    # Check systemd
    $systemdStatus = wsl -d Ubuntu -- systemctl is-system-running 2>&1
    if ($systemdStatus -match "running|degraded") {
        if ($Verbose) { Write-Host "  Systemd status: $systemdStatus" -ForegroundColor Gray }
    } else {
        Write-Status "WSL" "Warning" "Systemd not fully operational: $systemdStatus"
    }

    return $true
}

function Test-Docker {
    Write-Host "`n=== Docker Health Check ===" -ForegroundColor Cyan

    # Check Docker service in WSL
    $dockerActive = wsl -d Ubuntu -- systemctl is-active docker 2>&1
    if ($dockerActive -ne "active") {
        Write-Status "Docker" "Error" "Docker service not active ($dockerActive)"
        $script:Issues += "Docker service not running"

        if ($AutoRecover) {
            Write-Host "  Attempting to start Docker..." -ForegroundColor Yellow
            wsl -d Ubuntu -- sudo systemctl start docker 2>&1 | Out-Null
            Start-Sleep -Seconds 5
            $dockerActive = wsl -d Ubuntu -- systemctl is-active docker 2>&1
            if ($dockerActive -eq "active") {
                Write-Status "Docker" "OK" "Docker started successfully"
            } else {
                return $false
            }
        } else {
            return $false
        }
    } else {
        Write-Status "Docker" "OK" "Docker service is active"
    }

    # Check Docker daemon connectivity
    $dockerInfo = wsl -d Ubuntu -- docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Docker" "Warning" "Docker daemon not responding"
        $script:Issues += "Docker daemon connectivity issue"
        return $false
    }

    # Get container stats
    $containers = wsl -d Ubuntu -- docker ps -q 2>&1
    $containerCount = ($containers | Measure-Object -Line).Lines
    if ($Verbose) { Write-Host "  Running containers: $containerCount" -ForegroundColor Gray }

    # Check Docker socket
    $dockerSocket = wsl -d Ubuntu -- ls -la /var/run/docker.sock 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($Verbose) { Write-Host "  Docker socket: OK" -ForegroundColor Gray }
    } else {
        Write-Status "Docker" "Warning" "Docker socket not found"
    }

    return $true
}

function Test-HyperVBridges {
    Write-Host "`n=== Hyper-V Socket Bridges ===" -ForegroundColor Cyan

    # Check user service
    $bridgeActive = wsl -d Ubuntu -- systemctl --user is-active hyper-v-socket-bridges 2>&1
    if ($bridgeActive -notmatch "active|exited") {
        Write-Status "HyperVBridges" "Error" "Bridge service not active ($bridgeActive)"
        $script:Issues += "Hyper-V bridges not running"

        if ($AutoRecover) {
            Write-Host "  Attempting to start bridges..." -ForegroundColor Yellow
            wsl -d Ubuntu -- systemctl --user start hyper-v-socket-bridges 2>&1 | Out-Null
            Start-Sleep -Seconds 3
            $bridgeActive = wsl -d Ubuntu -- systemctl --user is-active hyper-v-socket-bridges 2>&1
            if ($bridgeActive -match "active|exited") {
                Write-Status "HyperVBridges" "OK" "Bridges started successfully"
            } else {
                return $false
            }
        } else {
            return $false
        }
    } else {
        Write-Status "HyperVBridges" "OK" "Bridge service is active"
    }

    # Check socat processes
    $socatCount = wsl -d Ubuntu -- pgrep -c socat 2>&1
    if ($socatCount -gt 0) {
        if ($Verbose) { Write-Host "  Active socat bridges: $socatCount" -ForegroundColor Gray }
    } else {
        Write-Status "HyperVBridges" "Warning" "No socat processes found"
        $script:Issues += "No active socat bridges"
    }

    # Check MCP Docker socket
    $mcpSocket = wsl -d Ubuntu -- ls -la ~/.config/mcp-nginx-automation/sockets/docker.sock 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($Verbose) { Write-Host "  MCP Docker socket: OK" -ForegroundColor Gray }
    } else {
        Write-Status "HyperVBridges" "Warning" "MCP Docker socket not found"
    }

    return $true
}

function Test-Network {
    if ($Quick) { return $true }

    Write-Host "`n=== Network Connectivity ===" -ForegroundColor Cyan

    # Test DNS from WSL
    $dnsTest = wsl -d Ubuntu -- nslookup google.com 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Network" "OK" "DNS resolution working"
    } else {
        Write-Status "Network" "Error" "DNS resolution failed"
        $script:Issues += "DNS resolution failing"
        return $false
    }

    # Test external connectivity
    $pingTest = wsl -d Ubuntu -- ping -c 1 -W 2 8.8.8.8 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($Verbose) { Write-Host "  External connectivity: OK" -ForegroundColor Gray }
    } else {
        Write-Status "Network" "Warning" "External connectivity issues"
    }

    return $true
}

function Show-Summary {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "HEALTH CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    $allOK = $true
    foreach ($key in $script:HealthStatus.Keys) {
        if ($key -eq "OverallHealth") { continue }
        $status = $script:HealthStatus[$key]
        if ($status -ne "OK" -and $status -ne "Unknown") {
            $allOK = $false
        }
    }

    if ($allOK -and $script:Issues.Count -eq 0) {
        Write-Host "`nOVERALL STATUS: " -NoNewline
        Write-Host "HEALTHY" -ForegroundColor Green
        $script:HealthStatus["OverallHealth"] = "Healthy"
    } elseif ($script:Issues.Count -gt 0) {
        Write-Host "`nOVERALL STATUS: " -NoNewline
        Write-Host "ISSUES DETECTED" -ForegroundColor Yellow
        Write-Host "`nIssues found:" -ForegroundColor Yellow
        foreach ($issue in $script:Issues) {
            Write-Host "  - $issue" -ForegroundColor Yellow
        }
        $script:HealthStatus["OverallHealth"] = "Degraded"

        if (-not $AutoRecover) {
            Write-Host "`nRun with -AutoRecover to attempt automatic fixes" -ForegroundColor Cyan
        }
    }

    Write-Host ""
}

# Main execution
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "WSL & Docker Health Check" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($AutoRecover) { Write-Host "Mode: Auto-Recovery Enabled" -ForegroundColor Green }
if ($Quick) { Write-Host "Mode: Quick Check" -ForegroundColor Yellow }

Test-WSL | Out-Null
Test-Docker | Out-Null
Test-HyperVBridges | Out-Null
Test-Network | Out-Null

Show-Summary

# Return exit code based on health
if ($script:HealthStatus["OverallHealth"] -eq "Healthy") {
    exit 0
} else {
    exit 1
}
