# Network Monitor Setup for Home Assistant Pi

## Quick Install

1. **SSH into your HA Pi** (or use Terminal & SSH add-on in HA)

2. **Create directory and copy files:**
```bash
mkdir -p /config/network_monitor
cp network_monitor.py /config/network_monitor/
cp network-monitor.service /etc/systemd/system/
```

3. **Install speedtest-cli (optional but recommended):**
```bash
pip3 install speedtest-cli
```

4. **Start the service:**
```bash
systemctl daemon-reload
systemctl enable network-monitor
systemctl start network-monitor
```

5. **Check status:**
```bash
systemctl status network-monitor
tail -f /config/network_monitor/monitor.log
```

## What It Monitors

- **Ping every 5 seconds** to:
  - Your router (192.168.68.1) - local network issues
  - Google DNS (8.8.8.8) - internet connectivity
  - Cloudflare DNS (1.1.1.1) - alternative path

- **Speed test every hour** - bandwidth issues

- **Detects hiccups** when:
  - Latency > 100ms
  - Packet loss > 1%

## Output Files

- `/config/network_monitor/network_log.csv` - All measurements
- `/config/network_monitor/hiccups.jsonl` - Just the hiccups
- `/config/network_monitor/monitor.log` - Service log

## Home Assistant Integration

Add to `configuration.yaml`:

```yaml
sensor:
  - platform: file
    name: Network Hiccup Count
    file_path: /config/network_monitor/hiccups.jsonl
    value_template: "{{ value.split('\n') | select() | list | length }}"
    
  - platform: command_line
    name: Last Network Hiccup
    command: "tail -1 /config/network_monitor/hiccups.jsonl 2>/dev/null || echo '{}'"
    value_template: >
      {% set data = value_json %}
      {{ data.timestamp | default('None') }}
    json_attributes:
      - target
      - latency
      - packet_loss
```

## Analyzing Results

After a day or two, check patterns:

```bash
# Count hiccups by hour (find patterns)
grep -o 'T[0-9][0-9]:' /config/network_monitor/hiccups.jsonl | sort | uniq -c

# See worst latency spikes
sort -t',' -k3 -nr /config/network_monitor/network_log.csv | head -20

# Check if it's always the same target
awk -F',' '{print $2}' /config/network_monitor/network_log.csv | grep -v target | sort | uniq -c
```

## Troubleshooting

**Service won't start:**
```bash
journalctl -u network-monitor -n 50
```

**Permission issues:**
Make sure the script is executable:
```bash
chmod +x /config/network_monitor/network_monitor.py
```

**Router IP wrong?**
Edit `network_monitor.py` and change `192.168.68.1` to your actual router IP.
