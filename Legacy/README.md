# Legacy Scripts Reference

This directory contains reference scripts discovered from various locations that informed the PC_AI framework. These scripts are preserved for reference but their functionality has been incorporated into the main modules.

## Scripts Included

### WSL/Docker Startup and Health

| Script | Original Location | Purpose |
|--------|-------------------|---------|
| `wsl-vsock-bridge-configured.sh` | `C:\tmp\` | VSock bridge manager with health checks, socat TCP/Unix bridges |
| `install-bridges.sh` | `C:\tmp\` | Systemd service installer for VSock bridges |
| `docker-wsl-startup.bat` | `C:\scripts\Startup\` | Windows startup script with retry logic and phased initialization |
| `wsl-docker-health-check.ps1` | `C:\scripts\Startup\` | Comprehensive WSL/Docker health check with auto-recovery |
| `create-startup-task.ps1` | `C:\scripts\Startup\` | Creates Windows scheduled task for WSL/Docker startup |

## Functionality Migration

### Incorporated into PC-AI.Virtualization Module

- `Get-WSLEnvironmentHealth` - Comprehensive health check combining patterns from:
  - `wsl-docker-health-check.ps1` (health check structure, auto-recovery)
  - `wsl-vsock-bridge-configured.sh` (bridge status checking)

### Patterns Used

1. **Phased Startup** (from `docker-wsl-startup.bat`)
   - LxssManager service check
   - WSL initialization with retry
   - DNS initialization
   - Socket bridge startup
   - Docker Desktop launch with readiness wait

2. **Health Monitoring** (from `wsl-docker-health-check.ps1`)
   - WSL distro running state
   - Systemd operational status
   - Docker service active state
   - Docker daemon connectivity
   - Socat process enumeration
   - Network DNS/ping tests

3. **VSock Bridge Management** (from `wsl-vsock-bridge-configured.sh`)
   - Network health pre-check before bridges
   - PID file management
   - Graceful start/stop/restart
   - Status reporting with process verification

## Usage Notes

These scripts remain functional in their original locations. To use the consolidated functionality:

```powershell
Import-Module PC-AI.Virtualization
Get-WSLEnvironmentHealth -AutoRecover
```

## Date Archived

2026-01-23
