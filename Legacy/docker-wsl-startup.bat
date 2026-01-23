@echo off
REM WSL and Docker Startup Script v2.0
REM Updated: 2026-01-11
REM Uses new consolidated Hyper-V socket bridge system

setlocal EnableDelayedExpansion

set "LOGFILE=C:\Scripts\Startup\docker-wsl-startup.log"
set "WSL_DISTRO=Ubuntu"
set "MAX_RETRIES=10"
set "RETRY_DELAY=10"
set "STARTUP_DELAY=20"
set "DOCKER_DESKTOP_EXE=C:\Program Files\Docker\Docker\Docker Desktop.exe"
set "DOCKER_READY_RETRIES=30"
set "DOCKER_READY_DELAY=5"

REM Log rotation - keep last 2000 lines
if exist "%LOGFILE%" (
    powershell -Command "Get-Content '%LOGFILE%' | Select-Object -Last 2000 | Set-Content '%LOGFILE%.tmp'; Move-Item -Force '%LOGFILE%.tmp' '%LOGFILE%'" 2>nul
)

call :log "============================================"
call :log "WSL Startup v2.0 - Starting..."
call :log "============================================"

REM Phase 0: Give Windows time to finish login/startup
call :log "Phase 0: Waiting %STARTUP_DELAY%s for system startup..."
timeout /t %STARTUP_DELAY% /nobreak >nul

REM Ensure LxssManager is running before WSL calls
call :log "Phase 1: Ensuring LxssManager service is running..."
sc query LxssManager | findstr /I "RUNNING" >nul
if %ERRORLEVEL% NEQ 0 (
    call :log "LxssManager not running, attempting to start..."
    sc start LxssManager >>"%LOGFILE%" 2>&1
)

REM Phase 2: Initialize WSL
call :log "Phase 2: Initializing WSL (%WSL_DISTRO%)..."
set "RETRY_COUNT=0"
:WSL_START_LOOP
wsl -d "%WSL_DISTRO%" --exec /bin/true >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :log "SUCCESS: WSL started"
    goto WSL_STARTED
)

set /a RETRY_COUNT+=1
if %RETRY_COUNT% LSS %MAX_RETRIES% (
    call :log "WARNING: WSL start attempt %RETRY_COUNT% failed, retrying in %RETRY_DELAY%s..."
    timeout /t %RETRY_DELAY% /nobreak >nul
    goto WSL_START_LOOP
)

call :log "ERROR: WSL failed to start after %MAX_RETRIES% attempts"
goto ERROR_EXIT

:WSL_STARTED

REM Phase 3: Initialize DNS (with fallback)
call :log "Phase 3: Initializing DNS..."
wsl -d "%WSL_DISTRO%" --exec sudo -n /usr/local/sbin/wsl-dns-init >>"%LOGFILE%" 2>&1
if %ERRORLEVEL% EQU 0 (
    call :log "SUCCESS: DNS initialized"
) else (
    call :log "WARNING: DNS initialization had issues (continuing)"
)

REM Phase 4: Start Hyper-V Socket Bridges
call :log "Phase 4: Starting Hyper-V socket bridges..."
wsl -d "%WSL_DISTRO%" --exec sudo -n /usr/local/sbin/wsl-vsock-bridge start >>"%LOGFILE%" 2>&1
if %ERRORLEVEL% EQU 0 (
    call :log "SUCCESS: Hyper-V bridges started"
) else (
    call :log "WARNING: Bridge startup had issues"
)

REM Phase 5: Start Docker Desktop after WSL is ready
call :log "Phase 5: Starting Docker Desktop (if not running)..."
tasklist /FI "IMAGENAME eq Docker Desktop.exe" | find /I "Docker Desktop.exe" >nul
if %ERRORLEVEL% NEQ 0 (
    call :log "Launching Docker Desktop..."
    start "" "%DOCKER_DESKTOP_EXE%"
) else (
    call :log "Docker Desktop already running"
)

REM Phase 6: Wait for Docker engine readiness
call :log "Phase 6: Waiting for Docker engine to become ready..."
set "DOCKER_RETRY_COUNT=0"
:DOCKER_READY_LOOP
docker info >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :log "SUCCESS: Docker engine is ready"
    goto STARTUP_SUCCESS
)
set /a DOCKER_RETRY_COUNT+=1
if %DOCKER_RETRY_COUNT% LSS %DOCKER_READY_RETRIES% (
    call :log "Waiting for Docker engine... attempt %DOCKER_RETRY_COUNT%/%DOCKER_READY_RETRIES%"
    timeout /t %DOCKER_READY_DELAY% /nobreak >nul
    goto DOCKER_READY_LOOP
)
call :log "WARNING: Docker engine not ready after %DOCKER_READY_RETRIES% attempts"

call :log "============================================"
call :log "Startup completed with WARNINGS"
call :log "============================================"
goto END

:STARTUP_SUCCESS
call :log "============================================"
call :log "Startup completed successfully"
call :log "============================================"
goto END

:ERROR_EXIT
call :log "============================================"
call :log "Startup completed with ERRORS"
call :log "============================================"
exit /b 1

:log
echo [%DATE% %TIME%] %~1 >> "%LOGFILE%"
goto :eof

:END
endlocal
exit /b 0
