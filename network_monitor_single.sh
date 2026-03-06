#!/bin/bash
# Network Monitor - Single File Version
# Paste this entire file into File Editor as /config/network_monitor.sh
# Then run: chmod +x /config/network_monitor.sh && nohup /config/network_monitor.sh &

LOG_DIR="/config/network_monitor"
LOG_FILE="$LOG_DIR/network.log"
HICCUP_FILE="$LOG_DIR/hiccups.log"
DROP_FILE="$LOG_DIR/drops.log"
mkdir -p "$LOG_DIR"

LAST_ROUTER_STATE="up"
DROP_START_TIME=""

check_host() { ping -c 1 -W 2 "$1" >/dev/null 2>&1; }
get_latency() { local r=$(ping -c 1 -W 2 "$1" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/'); echo "${r:-timeout}"; }

if [ ! -f "$LOG_FILE" ]; then echo "timestamp,router,google,cloudflare,router_state,google_state" > "$LOG_FILE"; fi

echo "Starting network monitor at $(date)"
echo "Logs: $LOG_FILE"
echo "Hiccups: $HICCUP_FILE"
echo "Drops: $DROP_FILE"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    h=$(date +%H); m=$(date +%M)
    if { [ "$h" -eq 11 ] && [ "$m" -ge 45 ]; } || { [ "$h" -eq 12 ] && [ "$m" -le 15 ]; }; then NW="🕛"; S=1; else NW=""; S=5; fi
    if check_host "192.168.68.1"; then
        RS="up"; r=$(get_latency "192.168.68.1")
        if [ "$LAST_ROUTER_STATE" = "down" ] && [ -n "$DROP_START_TIME" ]; then
            dur=$(( $(date +%s) - DROP_START_TIME ))
            echo "$ts,router,$dur" >> "$DROP_FILE"
            echo "[$ts] 🚨 DROP RECOVERED after ${dur}s"
        fi
        LAST_ROUTER_STATE="up"; DROP_START_TIME=""
    else
        RS="down"; r="timeout"
        if [ "$LAST_ROUTER_STATE" = "up" ]; then
            DROP_START_TIME=$(date +%s)
            echo "[$ts] 🚨 DROP DETECTED!"
        fi
        LAST_ROUTER_STATE="down"
    fi
    if check_host "8.8.8.8"; then GS="up"; g=$(get_latency "8.8.8.8"); else GS="down"; g="timeout"; fi
    c=$(get_latency "1.1.1.1")
    echo "$ts,$r,$g,$c,$RS,$GS" >> "$LOG_FILE"
    ri="${r%.*}"
    if [ "$r" != "timeout" ] && [ "$ri" -gt 100 ] 2>/dev/null; then
        echo "$ts,router,$r" >> "$HICCUP_FILE"; ST="SLOW"
    elif [ "$r" = "timeout" ]; then ST="DOWN"
    else ST="OK"; fi
    echo "[$ts] $NW R:${r}ms G:${g}ms [$RS/$GS] ($ST)"
    sleep $S
done
