#!/bin/bash
# PC_AI WSL Hyper-V Socket Bridge Manager
# Configurable VSock bridges with health checks

set -uo pipefail

LOG_FILE="/var/log/pcai-vsock-bridge.log"
PID_DIR="/var/run/pcai-vsock"
DOCKER_SOCKET="/var/run/docker.sock"
DOCKER_BRIDGE_SOCKET="/var/run/docker-bridge.sock"
CONFIG_FILE="/etc/pcai/vsock-bridges.conf"
FALLBACK_CONFIG="/mnt/c/Users/david/PC_AI/Config/vsock-bridges.conf"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

read_bridges() {
    local file="$CONFIG_FILE"
    if [ ! -f "$file" ] && [ -f "$FALLBACK_CONFIG" ]; then
        file="$FALLBACK_CONFIG"
    fi

    if [ ! -f "$file" ]; then
        log "WARNING: No VSock bridge config found at $CONFIG_FILE or $FALLBACK_CONFIG"
        return 1
    fi

    BRIDGES=()
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip comments
        line="${line%%#*}"
        # Strip Windows CR if present
        line="${line//$'\r'/}"
        # Trim whitespace
        line="$(echo "$line" | xargs)"
        [ -z "$line" ] && continue

        if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+)$ ]]; then
            BRIDGES+=("$line")
        else
            log "WARNING: Skipping invalid bridge entry: $line"
        fi
    done < "$file"

    log "Using VSock bridge config: $file"
    return 0
}

check_network_health() {
    log "Checking network health before starting socket bridges..."
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log "ERROR: No IP connectivity - refusing to start socket bridges"
        return 1
    fi
    if ! ping -c 1 -W 3 google.com >/dev/null 2>&1; then
        log "ERROR: No DNS resolution - refusing to start socket bridges"
        return 1
    fi
    log "OK: Network is healthy"
    return 0
}

start_docker_bridge() {
    local name="docker-bridge"
    local pid_file="$PID_DIR/${name}.pid"

    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            log "Docker bridge already running (PID: $pid)"
            return 0
        fi
        rm -f "$pid_file"
    fi

    if [ ! -S "$DOCKER_SOCKET" ]; then
        log "WARNING: Docker socket $DOCKER_SOCKET not found - skipping Docker bridge"
        return 1
    fi

    log "Starting Docker bridge: $DOCKER_BRIDGE_SOCKET -> $DOCKER_SOCKET"
    rm -f "$DOCKER_BRIDGE_SOCKET"

    socat \
        UNIX-LISTEN:$DOCKER_BRIDGE_SOCKET,fork,reuseaddr,unlink-early,mode=666 \
        UNIX-CONNECT:$DOCKER_SOCKET \
        >/dev/null 2>&1 &

    local socat_pid=$!
    sleep 1
    if ! kill -0 "$socat_pid" 2>/dev/null; then
        log "ERROR: Failed to start Docker bridge"
        return 1
    fi

    echo "$socat_pid" > "$pid_file"
    chmod 666 "$DOCKER_BRIDGE_SOCKET" 2>/dev/null || true
    log "OK: Docker bridge started (PID: $socat_pid)"
    return 0
}

start_bridge() {
    local name="$1"
    local local_port="$2"
    local vsock_port="$3"
    local pid_file="$PID_DIR/${name}.pid"

    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            log "Bridge $name already running (PID: $pid)"
            return 0
        fi
        rm -f "$pid_file"
    fi

    log "Starting bridge: $name (localhost:$local_port -> vsock:2:$vsock_port)"

    socat \
        TCP-LISTEN:$local_port,fork,reuseaddr,bind=127.0.0.1 \
        VSOCK-CONNECT:2:$vsock_port \
        >/dev/null 2>&1 &

    local socat_pid=$!
    sleep 1
    if ! kill -0 "$socat_pid" 2>/dev/null; then
        log "ERROR: Failed to start bridge $name"
        return 1
    fi

    echo "$socat_pid" > "$pid_file"
    log "OK: Bridge $name started (PID: $socat_pid)"
    return 0
}

stop_bridge() {
    local name="$1"
    local pid_file="$PID_DIR/${name}.pid"

    if [ ! -f "$pid_file" ]; then
        log "Bridge $name not running"
        return 0
    fi

    local pid
    pid=$(cat "$pid_file")
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

start_all() {
    log "========================================"
    log "Starting PC_AI VSock Bridges"
    log "========================================"

    if ! check_network_health; then
        log "ABORT: Network not healthy, bridges NOT started"
        return 1
    fi

    mkdir -p "$PID_DIR"

    local docker_started=0
    if command -v docker >/dev/null 2>&1; then
        if start_docker_bridge; then
            docker_started=1
        fi
    else
        log "Docker not installed - skipping Docker bridge"
    fi

    if ! read_bridges; then
        log "No bridge config loaded"
    fi

    local started=0
    local failed=0
    for bridge_config in "${BRIDGES[@]:-}"; do
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

stop_all() {
    log "Stopping all socket bridges..."

    if [ ! -d "$PID_DIR" ]; then
        log "No bridges running"
        return 0
    fi

    local stopped=0
    for pid_file in "$PID_DIR"/*.pid; do
        [ -f "$pid_file" ] || continue
        local name
        name=$(basename "$pid_file" .pid)
        if stop_bridge "$name"; then
            ((stopped++))
        fi
    done

    rm -f "$DOCKER_BRIDGE_SOCKET"
    log "Stopped $stopped bridge(s)"
    return 0
}

status() {
    echo "PC_AI VSock Bridge Status"
    echo "=========================="
    echo ""

    if [ ! -d "$PID_DIR" ] || [ -z "$(ls -A "$PID_DIR" 2>/dev/null)" ]; then
        echo "No bridges running"
    else
        local running=0
        local stopped=0
        for pid_file in "$PID_DIR"/*.pid; do
            [ -f "$pid_file" ] || continue
            local name
            name=$(basename "$pid_file" .pid)
            local pid
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                echo "OK  $name: RUNNING (PID: $pid)"
                ((running++))
            else
                echo "ERR $name: STOPPED (stale PID file)"
                ((stopped++))
            fi
        done
        echo ""
        echo "Summary: $running running, $stopped stopped"
    fi

    if [ -S "$DOCKER_BRIDGE_SOCKET" ]; then
        echo "Docker bridge socket: OK $DOCKER_BRIDGE_SOCKET"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        echo "Config: $CONFIG_FILE"
    elif [ -f "$FALLBACK_CONFIG" ]; then
        echo "Config: $FALLBACK_CONFIG"
    else
        echo "Config: not found"
    fi
}

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
        echo "PC_AI VSock Bridge Manager"
        echo "Usage: $0 {start|stop|restart|status}"
        echo ""
        echo "Config file: $CONFIG_FILE (fallback: $FALLBACK_CONFIG)"
        exit 1
        ;;
esac
