#!/bin/bash
# Deploy network monitor to Home Assistant Pi via git
# Run this on the HA Pi (via Terminal & SSH)

REPO_URL="https://github.com/rowbotik/network-monitor.git"
INSTALL_DIR="/config/network_monitor"

echo "========================================"
echo "Network Monitor - HA Pi Deploy"
echo "========================================"
echo ""

# Check if git is available
if ! command -v git &> /dev/null; then
    echo "Installing git..."
    apk add git
fi

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Updating existing install..."
    cd "$INSTALL_DIR"
    git pull
else
    echo "Cloning fresh..."
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo ""
echo "Installing..."
cd "$INSTALL_DIR"
chmod +x *.sh

echo ""
echo "Starting monitor..."
# Kill existing if running
pkill -f "network_monitor.sh" 2>/dev/null || true
sleep 1

# Start fresh
nohup "$INSTALL_DIR/network_monitor.sh" > "$INSTALL_DIR/output.log" 2>&1 &

echo ""
echo "✅ Monitor started!"
echo ""
echo "View logs:"
echo "  tail -f $INSTALL_DIR/output.log"
echo ""
echo "View drops:"
echo "  cat $INSTALL_DIR/drops.log"
echo ""
echo "Run analysis:"
echo "  bash $INSTALL_DIR/analyze.sh"
