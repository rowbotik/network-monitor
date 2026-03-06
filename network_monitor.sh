#!/bin/bash
# Network Monitor for Home Assistant
# Detects connection drops, not just latency spikes

LOG_DIR="/config/network_monitor"
LOG_FILE="$LOG_DIR/network.log"
HICCUP_FILE="$LOG_DIR/hiccups.log"
DROP_FILE="$LOG_DIR/drops.log"

# Create log directory
mkdir -p "$LOG_DIR"

# Track connection state
LAST_ROUTER_STATE="up"
LAST_GOOGLE_STATE="up"
DROP_START_TIME=""

# Function to check if host is reachable (returns 0 = up, 1 = down)
check_host() {
    local host=$1
    ping -c 1 -W 2 "$host" > /dev/null 2>&1
    return $?
}

# Function to get latency
get_latency() {
    local host=$1
    local result=$(ping -c 1 -W 2 "$host" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/')
    if [ -z "$result" ]; then
        echo "timeout"
    else
        echo "$result"
    fi
}

# Function to log hiccup (high latency)
log_hiccup() {
    local target=$1
    local latency=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$target,$latency" >> "$HICCUP_FILE"
}

# Function to log drop (connection lost)
log_drop() {
    local target=$1
    local duration=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp,$target,$duration" >> "$DROP_FILE"
    
    # Also log to hiccups for unified view
    echo "$timestamp,$target,DROP_${duration}s" >> "$HICCUP_FILE"
}

# Main monitoring loop
echo "Starting network monitor at $(date)"
echo "Logs: $LOG_FILE"
echo "Hiccups: $HICCUP_FILE"
echo "Drops: $DROP_FILE"
echo "Press Ctrl+C to stop"
echo ""

# Header for log files
if [ ! -f "$LOG_FILE" ]; then
    echo "timestamp,router,google,cloudflare,router_state,google_state" > "$LOG_FILE"
fi

while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    hour=$(date +%H)
    min=$(date +%M)
    
    # Check if it's noon watch time (11:45-12:15)
    if { [ "$hour" -eq 11 ] && [ "$min" -ge 45 ]; } || { [ "$hour" -eq 12 ] && [ "$min" -le 15 ]; }; then
        NOON_WATCH="🕛"
        SLEEP=1
    else
        NOON_WATCH=""
        SLEEP=5
    fi
    
    # Check connectivity (fast check)
    if check_host "192.168.68.1"; then
        ROUTER_STATE="up"
        router=$(get_latency "192.168.68.1")
        
        # Detect drop recovery
        if [ "$LAST_ROUTER_STATE" = "down" ] && [ -n "$DROP_START_TIME" ]; then
            DROP_END=$(date +%s)
            DROP_DURATION=$((DROP_END - DROP_START_TIME))
            log_drop "router" "$DROP_DURATION"
            echo "[$timestamp] 🚨 ROUTER DROP RECOVERED after ${DROP_DURATION}s"
        fi
        LAST_ROUTER_STATE="up"
        DROP_START_TIME=""
    else
        ROUTER_STATE="down"
        router="timeout"
        
        # Detect drop start
        if [ "$LAST_ROUTER_STATE" = "up" ]; then
            DROP_START_TIME=$(date +%s)
            echo "[$timestamp] 🚨 ROUTER DROP DETECTED!"
        fi
        LAST_ROUTER_STATE="down"
    fi
    
    # Check Google DNS
    if check_host "8.8.8.8"; then
        GOOGLE_STATE="up"
        google=$(get_latency "8.8.8.8")
    else
        GOOGLE_STATE="down"
        google="timeout"
    fi
    
    # Check Cloudflare
    if check_host "1.1.1.1"; then
        cloudflare=$(get_latency "1.1.1.1")
    else
        cloudflare="timeout"
    fi
    
    # Log to CSV
    echo "$timestamp,$router,$google,$cloudflare,$ROUTER_STATE,$GOOGLE_STATE" >> "$LOG_FILE"
    
    # Detect hiccups (>100ms but still connected)
    router_int="${router%.*}"
    if [ "$router" != "timeout" ] && [ "$router_int" -gt 100 ] 2>/dev/null; then
        log_hiccup "router" "$router"
        STATUS="SLOW"
    elif [ "$router" = "timeout" ]; then
        STATUS="DOWN"
    else
        STATUS="OK"
    fi
    
    # Print status
    echo "[$timestamp] $NOON_WATCH Router:${router}ms Google:${google}ms [${ROUTER_STATE}/${GOOGLE_STATE}] ($STATUS)"
    
    sleep $SLEEP
done
