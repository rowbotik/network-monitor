#!/usr/bin/env python3
"""
Network Monitor for Home Assistant Pi
Monitors ping latency, packet loss, and speed tests
Logs to CSV and reports to Home Assistant
"""

import subprocess
import time
import json
import csv
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
import statistics
import threading
import queue

# Configuration
CONFIG = {
    "ping_targets": [
        {"name": "router", "host": "192.168.68.1", "interval": 5},  # Your router
        {"name": "google_dns", "host": "8.8.8.8", "interval": 5},
        {"name": "cloudflare_dns", "host": "1.1.1.1", "interval": 5},
    ],
    "speed_test_interval_minutes": 60,
    "log_dir": "/config/network_monitor",
    "csv_file": "/config/network_monitor/network_log.csv",
    "hiccup_threshold_ms": 100,  # Latency spike considered a hiccup
    "packet_loss_threshold": 1,  # % packet loss to alert
    "ha_webhook_url": None,  # Set to HA webhook for alerts
    "time_patterns": {
        "enabled": True,
        "check_interval_hours": 24,  # Generate report every 24h
        "suspicious_hours": [12],  # Your suspected noon issue
    },
    "noon_watch": {
        "enabled": True,
        "window_minutes": 30,  # Watch 11:45-12:15
        "intensive_interval": 1,  # Ping every 1 second during window
    },
}

class NetworkMonitor:
    def __init__(self):
        self.running = False
        self.results_queue = queue.Queue()
        self.hiccups = []
        self.ensure_dirs()
        
    def ensure_dirs(self):
        Path(CONFIG["log_dir"]).mkdir(parents=True, exist_ok=True)
        
    def init_csv(self):
        if not os.path.exists(CONFIG["csv_file"]):
            with open(CONFIG["csv_file"], 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow([
                    'timestamp', 'target', 'latency_ms', 'packet_loss_pct',
                    'jitter_ms', 'hiccup_detected', 'speed_down_mbps', 
                    'speed_up_mbps', 'speed_ping_ms'
                ])
    
    def ping(self, host, count=10):
        """Run ping and return stats"""
        try:
            result = subprocess.run(
                ['ping', '-c', str(count), '-i', '0.2', host],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            lines = result.stdout.split('\n')
            latencies = []
            
            for line in lines:
                if 'time=' in line:
                    try:
                        time_part = line.split('time=')[1].split()[0]
                        latencies.append(float(time_part.replace('ms', '')))
                    except (IndexError, ValueError):
                        continue
            
            # Parse summary
            transmitted, received = count, 0
            for line in lines:
                if 'packets transmitted' in line:
                    parts = line.split(',')
                    transmitted = int(parts[0].split()[0])
                    received = int(parts[1].split()[0])
                    break
            
            packet_loss = ((transmitted - received) / transmitted) * 100 if transmitted > 0 else 0
            
            if latencies:
                avg_latency = statistics.mean(latencies)
                jitter = statistics.stdev(latencies) if len(latencies) > 1 else 0
                return {
                    'latency': avg_latency,
                    'packet_loss': packet_loss,
                    'jitter': jitter,
                    'success': True
                }
            else:
                return {'latency': None, 'packet_loss': 100, 'jitter': 0, 'success': False}
                
        except subprocess.TimeoutExpired:
            return {'latency': None, 'packet_loss': 100, 'jitter': 0, 'success': False}
        except Exception as e:
            return {'latency': None, 'packet_loss': 100, 'jitter': 0, 'success': False, 'error': str(e)}
    
    def speed_test(self):
        """Run speedtest-cli if available"""
        try:
            result = subprocess.run(
                ['speedtest-cli', '--json'],
                capture_output=True,
                text=True,
                timeout=120
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                return {
                    'download': data.get('download', 0) / 1_000_000,  # Convert to Mbps
                    'upload': data.get('upload', 0) / 1_000_000,
                    'ping': data.get('ping', 0)
                }
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            pass
        return None
    
    def detect_hiccup(self, target_name, latency, packet_loss):
        """Detect network hiccups based on thresholds"""
        is_hiccup = False
        
        if latency and latency > CONFIG["hiccup_threshold_ms"]:
            is_hiccup = True
        if packet_loss > CONFIG["packet_loss_threshold"]:
            is_hiccup = True
            
        if is_hiccup:
            hiccup = {
                'timestamp': datetime.now().isoformat(),
                'target': target_name,
                'latency': latency,
                'packet_loss': packet_loss
            }
            self.hiccups.append(hiccup)
            self.log_hiccup(hiccup)
            
        return is_hiccup
    
    def log_hiccup(self, hiccup):
        """Log hiccup to separate file for easy analysis"""
        hiccup_file = os.path.join(CONFIG["log_dir"], "hiccups.jsonl")
        with open(hiccup_file, 'a') as f:
            f.write(json.dumps(hiccup) + '\n')
    
    def log_to_csv(self, row):
        """Append row to CSV log"""
        with open(CONFIG["csv_file"], 'a', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(row)
    
    def is_noon_watch_active(self):
        """Check if we're in the noon watch window"""
        if not CONFIG.get("noon_watch", {}).get("enabled"):
            return False
        now = datetime.now()
        window = CONFIG["noon_watch"]["window_minutes"]
        # Check if within window minutes of noon (12:00)
        noon_today = now.replace(hour=12, minute=0, second=0, microsecond=0)
        diff = abs((now - noon_today).total_seconds())
        return diff <= (window * 60)

    def monitor_target(self, target):
        """Monitor a single target continuously"""
        while self.running:
            start_time = time.time()

            # Use intensive interval during noon watch
            if self.is_noon_watch_active():
                interval = CONFIG["noon_watch"]["intensive_interval"]
                ping_count = 5  # More samples during watch
            else:
                interval = target['interval']
                ping_count = 10

            result = self.ping(target['host'], count=ping_count)
            timestamp = datetime.now().isoformat()

            is_hiccup = self.detect_hiccup(target['name'], result.get('latency'), result.get('packet_loss', 0))

            row = [
                timestamp,
                target['name'],
                result.get('latency'),
                result.get('packet_loss', 0),
                result.get('jitter', 0),
                is_hiccup,
                None, None, None  # Speed test columns
            ]

            self.log_to_csv(row)

            # Print status with noon watch indicator
            status = "HICCUP!" if is_hiccup else "OK"
            latency_str = f"{result['latency']:.1f}ms" if result.get('latency') else "TIMEOUT"
            noon_indicator = "🕛" if self.is_noon_watch_active() else ""
            print(f"[{timestamp}] {noon_indicator} {target['name']}: {latency_str} ({status})")

            # Sleep until next interval
            elapsed = time.time() - start_time
            sleep_time = max(0, interval - elapsed)
            time.sleep(sleep_time)
    
    def speed_test_loop(self):
        """Run periodic speed tests"""
        while self.running:
            print(f"[{datetime.now().isoformat()}] Running speed test...")
            result = self.speed_test()
            
            if result:
                timestamp = datetime.now().isoformat()
                row = [
                    timestamp,
                    'speedtest',
                    None, None, None, None,
                    result['download'],
                    result['upload'],
                    result['ping']
                ]
                self.log_to_csv(row)
                print(f"  Download: {result['download']:.1f} Mbps, Upload: {result['upload']:.1f} Mbps, Ping: {result['ping']:.1f}ms")
            else:
                print("  Speed test failed or not available")
            
            # Sleep for interval
            time.sleep(CONFIG["speed_test_interval_minutes"] * 60)
    
    def generate_report(self):
        """Generate daily/periodic report"""
        if not self.hiccups:
            return "No hiccups detected in this period."
        
        report = []
        report.append(f"Network Hiccup Report ({len(self.hiccups)} events)")
        report.append("=" * 50)
        
        # Group by target
        by_target = {}
        for h in self.hiccups:
            by_target.setdefault(h['target'], []).append(h)
        
        for target, events in by_target.items():
            report.append(f"\n{target}: {len(events)} hiccups")
            latencies = [e['latency'] for e in events if e['latency']]
            if latencies:
                report.append(f"  Avg latency during hiccups: {statistics.mean(latencies):.1f}ms")
        
        # Time pattern analysis
        if CONFIG["time_patterns"]["enabled"]:
            report.append("\n" + "=" * 50)
            report.append("TIME PATTERN ANALYSIS")
            report.append("=" * 50)
            
            # Hiccups by hour
            by_hour = {}
            for h in self.hiccups:
                hour = datetime.fromisoformat(h['timestamp']).hour
                by_hour[hour] = by_hour.get(hour, 0) + 1
            
            if by_hour:
                report.append("\nHiccups by hour of day:")
                for hour in sorted(by_hour.keys()):
                    bar = "█" * by_hour[hour]
                    report.append(f"  {hour:02d}:00 - {by_hour[hour]:3d} {bar}")
                
                # Check suspicious hours
                suspicious = CONFIG["time_patterns"]["suspicious_hours"]
                report.append(f"\nSuspicious hours ({suspicious}):")
                for hour in suspicious:
                    count = by_hour.get(hour, 0)
                    pct = (count / len(self.hiccups)) * 100 if self.hiccups else 0
                    status = "⚠️ HIGH" if pct > 20 else "OK"
                    report.append(f"  {hour:02d}:00 - {count} hiccups ({pct:.1f}%) {status}")
        
        return '\n'.join(report)
    
    def start(self):
        """Start all monitoring threads"""
        self.init_csv()
        self.running = True
        
        print(f"Starting Network Monitor at {datetime.now().isoformat()}")
        print(f"Logging to: {CONFIG['csv_file']}")
        print(f"Monitoring targets: {[t['name'] for t in CONFIG['ping_targets']]}")
        print("Press Ctrl+C to stop\n")
        
        threads = []
        
        # Start ping monitors
        for target in CONFIG['ping_targets']:
            t = threading.Thread(target=self.monitor_target, args=(target,), daemon=True)
            t.start()
            threads.append(t)
        
        # Start speed test thread
        speed_thread = threading.Thread(target=self.speed_test_loop, daemon=True)
        speed_thread.start()
        threads.append(speed_thread)
        
        # Start pattern analysis thread
        if CONFIG["time_patterns"]["enabled"]:
            pattern_thread = threading.Thread(target=self.pattern_analysis_loop, daemon=True)
            pattern_thread.start()
            threads.append(pattern_thread)
        
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nStopping...")
            self.running = False
            print(self.generate_report())
    
    def pattern_analysis_loop(self):
        """Run periodic pattern analysis and save reports"""
        interval = CONFIG["time_patterns"]["check_interval_hours"] * 3600
        
        while self.running:
            time.sleep(interval)
            
            if not self.hiccups:
                continue
            
            report = self.generate_report()
            report_file = os.path.join(CONFIG["log_dir"], 
                f"pattern_report_{datetime.now().strftime('%Y%m%d_%H%M')}.txt")
            
            with open(report_file, 'w') as f:
                f.write(report)
            
            print(f"\n[Pattern Report Saved] {report_file}")
            
            # Check for noon pattern specifically
            noon_hiccups = [h for h in self.hiccups 
                          if datetime.fromisoformat(h['timestamp']).hour == 12]
            if len(noon_hiccups) >= 3:
                print(f"\n🕛 NOON PATTERN DETECTED: {len(noon_hiccups)} hiccups at 12:00!")
                print("Possible causes:")
                print("  - ISP maintenance window")
                print("  - Scheduled backups/uploads")
                print("  - Thermal issues (peak sun)")
                print("  - Power grid load (lunch hour)")

if __name__ == '__main__':
    monitor = NetworkMonitor()
    monitor.start()
