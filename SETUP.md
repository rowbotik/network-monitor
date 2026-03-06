# Network Monitor - Quick Setup for Home Assistant

## Option 1: Terminal & SSH Web UI (Easiest)

1. Open Home Assistant
2. Go to **Settings → Add-ons → Terminal & SSH**
3. Click **Open Web UI**
4. Paste these commands one at a time:

```bash
# Create directory
mkdir -p /config/network_monitor

# Create the monitor script (copy the full network_monitor.sh content)
cat > /config/network_monitor/monitor.sh << 'ENDSCRIPT'
#!/bin/bash
LOG_DIR="/config/network_monitor"
LOG_FILE="$LOG_DIR/network.log"
HICCUP_FILE="$LOG_DIR/hiccups.log"
DROP_FILE="$LOG_DIR/drops.log"
mkdir -p "$LOG_DIR"

LAST_ROUTER_STATE="up"
DROP_START_TIME=""

check_host() {
    ping -c 1 -W 2 "$1" >/dev/null 2>&1
}

get_latency() {
    local r=$(ping -c 1 -W 2 "$1" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/')
    echo "${r:-timeout}"
}

if [ ! -f "$LOG_FILE" ]; then
    echo "timestamp,router,google,cloudflare,router_state,google_state" > "$LOG_FILE"
fi

echo "Starting monitor at $(date)"

while true; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    h=$(date +%H)
    m=$(date +%M)
    
    if { [ "$h" -eq 11 ] && [ "$m" -ge 45 ]; } || { [ "$h" -eq 12 ] && [ "$m" -le 15 ]; }; then
        NW="🕛"; S=1
    else
        NW=""; S=5
    fi
    
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
    
    if check_host "8.8.8.8"; then GS="up"; g=$(get_latency "8.8.8.8")
    else GS="down"; g="timeout"; fi
    
    c=$(get_latency "1.1.1.1")
    
    echo "$ts,$r,$g,$c,$RS,$GS" >> "$LOG_FILE"
    
    ri="${r%.*}"
    if [ "$r" != "timeout" ] && [ "$ri" -gt 100 ] 2>/dev/null; then
        echo "$ts,router,$r" >> "$HICCUP_FILE"
        ST="SLOW"
    elif [ "$r" = "timeout" ]; then ST="DOWN"
    else ST="OK"; fi
    
    echo "[$ts] $NW R:${r}ms G:${g}ms [$RS/$GS] ($ST)"
    sleep $S
done
ENDSCRIPT

chmod +x /config/network_monitor/monitor.sh

# Start the monitor
nohup /config/network_monitor/monitor.sh > /config/network_monitor/output.log 2>&1 &

echo "Monitor started (PID: $!)"
sleep 2
tail /config/network_monitor/output.log
```

## Option 2: Samba Share

If you have the Samba add-on:
1. Mount `\\homeassistant.local\config` on your Mac
2. Create `network_monitor/` folder
3. Copy `network_monitor.sh` from this folder
4. In Terminal & SSH: `nohup /config/network_monitor/network_monitor.sh &`

## Viewing Results

In Terminal & SSH:
```bash
# Live monitor output
tail -f /config/network_monitor/output.log

# View hiccups (slow pings)
cat /config/network_monitor/hiccups.log

# View drops (full disconnections)
cat /config/network_monitor/drops.log

# Run analysis script
bash /config/network_monitor/analyze.sh

# Count hiccups by hour
cut -d',' -f1 /config/network_monitor/hiccups.log | cut -d' ' -f2 | cut -d':' -f1 | sort | uniq -c

# See noon events specifically
grep '12:' /config/network_monitor/hiccups.log

# Check if drops happen at noon
grep '12:' /config/network_monitor/drops.log
```

## Stop/Restart

```bash
# Find and stop
ps aux | grep monitor.sh
kill <PID>

# Restart
nohup /config/network_monitor/monitor.sh > /config/network_monitor/output.log 2>&1 &
```

## HA Sensors (Optional)

Add to `configuration.yaml`:

```yaml
command_line:
  - sensor:
      name: Network Router Latency
      command: "tail -1 /config/network_monitor/network.log | cut -d',' -f2"
      unit_of_measurement: "ms"
      scan_interval: 10
      
  - sensor:
      name: Network Hiccups Today
      command: "grep $(date +%Y-%m-%d) /config/network_monitor/hiccups.log | wc -l"
      scan_interval: 60
```
