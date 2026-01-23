#!/bin/bash
# WSL Hyper-V Socket Bridge Manager v2.1
# Production-ready Hyper-V socket bridges with health checks
# Replaces old mcp-nginx-automation system with cleaner architecture

set -uo pipefail

LOG_FILE="/var/log/wsl-vsock-bridge.log"
PID_DIR="/var/run/wsl-vsock"
NETWORK_STATE="/var/run/wsl-network-state"
DOCKER_SOCKET="/var/run/docker.sock"
DOCKER_BRIDGE_SOCKET="/var/run/docker-bridge.sock"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if network is healthy before starting bridges
check_network_health() {
    log "Checking network health before starting socket bridges..."
    
    # Test basic connectivity
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log "ERROR: No IP connectivity - refusing to start socket bridges"
        return 1
    fi
    
    if ! ping -c 1 -W 3 google.com >/dev/null 2>&1; then
        log "ERROR: No DNS resolution - refusing to start socket bridges"
        return 1
    fi
    
    log "✅ Network is healthy, safe to start socket bridges"
    return 0
}

# Start Docker bridge (Unix socket to Unix socket)
start_docker_bridge() {
    local name="docker-bridge"
    local pid_file="$PID_DIR/${name}.pid"
    
    # Check if already running
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            log "Docker bridge already running (PID: $pid)"
            return 0
        fi
        rm -f "$pid_file"
    fi
    
    # Check if Docker daemon socket exists
    if [ ! -S "$DOCKER_SOCKET" ]; then
        log "WARNING: Docker socket $DOCKER_SOCKET not found - skipping Docker bridge"
        return 1
    fi
    
    log "Starting Docker bridge: $DOCKER_BRIDGE_SOCKET -> $DOCKER_SOCKET"
    
    # Remove old bridge socket if exists
    rm -f "$DOCKER_BRIDGE_SOCKET"
    
    # Start socat to bridge Docker socket
    socat \
        UNIX-LISTEN:$DOCKER_BRIDGE_SOCKET,fork,reuseaddr,unlink-early,mode=666 \
        UNIX-CONNECT:$DOCKER_SOCKET \
        >/dev/null 2>&1 &
    
    local socat_pid=$!
    
    # Verify it started
    sleep 1
    if ! kill -0 "$socat_pid" 2>/dev/null; then
        log "ERROR: Failed to start Docker bridge"
        return 1
    fi
    
    echo "$socat_pid" > "$pid_file"
    log "✅ Docker bridge started (PID: $socat_pid)"
    
    # Set proper permissions
    chmod 666 "$DOCKER_BRIDGE_SOCKET" 2>/dev/null || true
    
    return 0
}

# Start a single TCP socket bridge
start_bridge() {
    local name="$1"
    local local_port="$2"
    local vsock_port="$3"
    local pid_file="$PID_DIR/${name}.pid"
    
    # Check if already running
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            log "Bridge $name already running (PID: $pid)"
            return 0
        fi
        rm -f "$pid_file"
    fi
    
    log "Starting bridge: $name (localhost:$local_port -> vsock:2:$vsock_port)"
    
    # Start socat in background
    socat \
        TCP-LISTEN:$local_port,fork,reuseaddr,bind=127.0.0.1 \
        VSOCK-CONNECT:2:$vsock_port \
        >/dev/null 2>&1 &
    
    local socat_pid=$!
    
    # Verify it started
    sleep 1
    if ! kill -0 "$socat_pid" 2>/dev/null; then
        log "ERROR: Failed to start bridge $name"
        return 1
    fi
    
    echo "$socat_pid" > "$pid_file"
    log "✅ Bridge $name started (PID: $socat_pid)"
    return 0
}

# Stop a bridge
stop_bridge() {
    local name="$1"
    local pid_file="$PID_DIR/${name}.pid"
    
    if [ ! -f "$pid_file" ]; then
        log "Bridge $name not running"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
        log "Stopping bridge $name (PID: $pid)..."
        kill -TERM "$pid" 2>/dev/null
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null
        fi
        log "Bridge $name stopped"
    fi
    
    rm -f "$pid_file"
    return 0
}

# Start all bridges
start_all() {
    log "========================================"
    log "Starting WSL Hyper-V Socket Bridges v2.1"
    log "========================================"
    
    # CRITICAL: Check network health first
    if ! check_network_health; then
        log "ABORT: Network not healthy, bridges NOT started"
        return 1
    fi
    
    mkdir -p "$PID_DIR"
    
    # Start Docker bridge first (if Docker is installed)
    local docker_started=0
    if command -v docker >/dev/null 2>&1; then
        if start_docker_bridge; then
            docker_started=1
        fi
    else
        log "Docker not installed - skipping Docker bridge"
    fi
    
    # Define TCP bridges (name:local_port:vsock_port)
    # These are the bridges that were active in the old system
    local bridges=(
        "vertex-code-reviewer:8000:3001"
        "vertex-master-architect:8002:3002"
    )
    
    local started=0
    local failed=0
    for bridge_config in "${bridges[@]}"; do
        IFS=':' read -r name port vsock <<< "$bridge_config"
        if start_bridge "$name" "$port" "$vsock"; then
            ((started++))
        else
            ((failed++))
        fi
    done
    
    log "========================================"
    log "Startup complete: $((docker_started + started)) bridges started, $failed failed"
    log "========================================"
    return 0
}

# Stop all bridges
stop_all() {
    log "Stopping all socket bridges..."
    
    if [ ! -d "$PID_DIR" ]; then
        log "No bridges running"
        return 0
    fi
    
    local stopped=0
    for pid_file in "$PID_DIR"/*.pid; do
        [ -f "$pid_file" ] || continue
        local name=$(basename "$pid_file" .pid)
        if stop_bridge "$name"; then
            ((stopped++))
        fi
    done
    
    # Clean up Docker bridge socket
    rm -f "$DOCKER_BRIDGE_SOCKET"
    
    log "Stopped $stopped bridge(s)"
    return 0
}

# Show status
status() {
    echo "WSL Hyper-V Socket Bridge Status v2.1"
    echo "====================================="
    echo ""
    
    if [ ! -d "$PID_DIR" ] || [ -z "$(ls -A "$PID_DIR" 2>/dev/null)" ]; then
        echo "No bridges running"
        return 0
    fi
    
    local running=0
    local stopped=0
    
    for pid_file in "$PID_DIR"/*.pid; do
        [ -f "$pid_file" ] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "✅ $name: RUNNING (PID: $pid)"
            ((running++))
        else
            echo "❌ $name: STOPPED (stale PID file)"
            ((stopped++))
        fi
    done
    
    echo ""
    echo "Summary: $running running, $stopped stopped"
    
    # Show Docker bridge socket status
    if [ -S "$DOCKER_BRIDGE_SOCKET" ]; then
        echo "Docker bridge socket: ✅ $DOCKER_BRIDGE_SOCKET"
    fi
}

# Main
case "${1:-}" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 2
        start_all
        ;;
    status)
        status
        ;;
    *)
        echo "WSL Hyper-V Socket Bridge Manager v2.1"
        echo "Usage: $0 {start|stop|restart|status}"
        echo ""
        echo "Configured bridges:"
        echo "  - Docker bridge (Unix socket)"
        echo "  - vertex-code-reviewer (port 8000 -> vsock 3001)"
        echo "  - vertex-master-architect (port 8002 -> vsock 3002)"
        echo ""
        echo "Logs: $LOG_FILE"
        exit 1
        ;;
esac
