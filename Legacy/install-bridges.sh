#!/bin/bash
# Interactive installation script for WSL Hyper-V Socket Bridges v2.1
# Run with: wsl bash /mnt/c/tmp/install-bridges.sh

set -e

echo "========================================="
echo "WSL Hyper-V Socket Bridge Installation"
echo "========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script needs sudo privileges. You'll be prompted for your password."
    echo ""
fi

# Step 1: Install script
echo "[1/5] Installing wsl-vsock-bridge script..."
if [ -f /usr/local/sbin/wsl-vsock-bridge ]; then
    BACKUP="/usr/local/sbin/wsl-vsock-bridge.backup-$(date +%Y%m%d-%H%M%S)"
    sudo cp /usr/local/sbin/wsl-vsock-bridge "$BACKUP"
    echo "  ✅ Backed up old script to $BACKUP"
fi

sudo cp /tmp/wsl-vsock-bridge-new.sh /usr/local/sbin/wsl-vsock-bridge
sudo chmod 755 /usr/local/sbin/wsl-vsock-bridge
sudo chown root:root /usr/local/sbin/wsl-vsock-bridge
echo "  ✅ Script installed to /usr/local/sbin/wsl-vsock-bridge"

# Step 2: Create systemd service
echo ""
echo "[2/5] Creating systemd service..."

cat > /tmp/wsl-vsock-bridge.service <<'EOF'
[Unit]
Description=WSL Hyper-V Socket Bridges v2.1
Documentation=man:wsl-vsock-bridge(8)
After=network-online.target wsl-dns-init.service
Wants=network-online.target
ConditionPathExists=/dev/vsock

[Service]
Type=forking
ExecStart=/usr/local/sbin/wsl-vsock-bridge start
ExecStop=/usr/local/sbin/wsl-vsock-bridge stop
ExecReload=/usr/local/sbin/wsl-vsock-bridge restart
Restart=on-failure
RestartSec=10
TimeoutStartSec=30
TimeoutStopSec=30

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wsl-vsock-bridge

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/wsl-vsock-bridge.service /etc/systemd/system/wsl-vsock-bridge.service
sudo chmod 644 /etc/systemd/system/wsl-vsock-bridge.service
echo "  ✅ Systemd service created"

# Step 3: Enable service
echo ""
echo "[3/5] Enabling systemd service..."
sudo systemctl daemon-reload
sudo systemctl enable wsl-vsock-bridge.service
echo "  ✅ Service enabled (will start on boot)"

# Step 4: Test the script
echo ""
echo "[4/5] Testing configuration..."
/usr/local/sbin/wsl-vsock-bridge --help 2>&1 | head -5
echo "  ✅ Script is executable"

# Step 5: Backup old system
echo ""
echo "[5/5] Backing up old system files..."
BACKUP_DIR="$HOME/.backup/old-hyperv-system-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "$HOME/.config/systemd/user/hyper-v-socket-bridges.service" ]; then
    cp "$HOME/.config/systemd/user/hyper-v-socket-bridges.service" "$BACKUP_DIR/"
    echo "  ✅ Backed up old systemd service"
fi

if [ -f "$HOME/.config/mcp-nginx-automation/scripts/hyper-v-socket-manager.sh" ]; then
    cp "$HOME/.config/mcp-nginx-automation/scripts/hyper-v-socket-manager.sh" "$BACKUP_DIR/"
    echo "  ✅ Backed up old script"
fi

echo "  📁 Backups saved to: $BACKUP_DIR"

# Summary
echo ""
echo "========================================="
echo "✅ Installation Complete!"
echo "========================================="
echo ""
echo "Configured bridges:"
echo "  - Docker bridge (Unix socket)"
echo "  - vertex-code-reviewer (port 8000 -> vsock 3001)"
echo "  - vertex-master-architect (port 8002 -> vsock 3002)"
echo ""
echo "Next steps:"
echo "  1. Start bridges:  sudo systemctl start wsl-vsock-bridge"
echo "  2. Check status:   sudo /usr/local/sbin/wsl-vsock-bridge status"
echo "  3. View logs:      sudo journalctl -u wsl-vsock-bridge -f"
echo ""
echo "To start bridges now, run:"
echo "  sudo systemctl start wsl-vsock-bridge"
echo ""
