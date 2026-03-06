#!/bin/bash
# Analyze network logs for patterns
# Run this after collecting data for a few days

LOG_DIR="/config/network_monitor"
HICCUP_FILE="$LOG_DIR/hiccups.log"
DROP_FILE="$LOG_DIR/drops.log"

echo "=========================================="
echo "Network Hiccup Analysis"
echo "=========================================="
echo ""

# Count total hiccups
echo "Total Events:"
if [ -f "$HICCUP_FILE" ]; then
    echo "  Hiccups (slow): $(wc -l < "$HICCUP_FILE")"
else
    echo "  No hiccup log yet"
fi

if [ -f "$DROP_FILE" ]; then
    echo "  Drops (disconnected): $(wc -l < "$DROP_FILE")"
else
    echo "  No drop log yet"
fi
echo ""

# Analyze by hour
echo "Events by Hour:"
if [ -f "$HICCUP_FILE" ]; then
    echo ""
    echo "Hour | Count | Visual"
    echo "-----|-------|-------"
    for hour in $(seq 0 23); do
        count=$(grep "T$(printf "%02d" $hour):" "$HICCUP_FILE" 2>/dev/null | wc -l)
        if [ $count -gt 0 ]; then
            bar=$(printf '%*s' "$count" '' | tr ' ' '█')
            printf "%02d:00 | %5d | %s\n" $hour $count "$bar"
        fi
    done
fi
echo ""

# Noon analysis (11:00-13:00)
echo "🕛 NOON ANALYSIS (11:00-13:00):"
echo "--------------------------------"
if [ -f "$HICCUP_FILE" ]; then
    noon_count=$(grep -E "T1[12]:" "$HICCUP_FILE" 2>/dev/null | wc -l)
    total_count=$(wc -l < "$HICCUP_FILE")
    if [ $total_count -gt 0 ]; then
        pct=$((noon_count * 100 / total_count))
        echo "Noon events: $noon_count / $total_count ($pct%)"
        
        if [ $pct -gt 30 ]; then
            echo "⚠️  STRONG noon pattern detected!"
        elif [ $pct -gt 15 ]; then
            echo "⚠️  Moderate noon pattern"
        else
            echo "✓ No significant noon pattern"
        fi
    fi
    
    # Show noon events with details
    echo ""
    echo "Noon events:"
    grep -E "T1[12]:" "$HICCUP_FILE" 2>/dev/null | tail -10
fi
echo ""

# Drop analysis
echo "🚨 CONNECTION DROPS:"
echo "--------------------"
if [ -f "$DROP_FILE" ] && [ -s "$DROP_FILE" ]; then
    echo "Timestamp          | Target | Duration"
    echo "-------------------|--------|----------"
    while IFS=',' read -r timestamp target duration; do
        printf "%-18s | %-6s | %ss\n" "$timestamp" "$target" "$duration"
    done < "$DROP_FILE"
    
    # Average drop duration
    avg_drop=$(awk -F',' '{sum+=$3; count++} END {if(count>0) printf "%.1f", sum/count}' "$DROP_FILE")
    echo ""
    echo "Average drop duration: ${avg_drop}s"
    
    # Longest drop
    longest=$(awk -F',' 'BEGIN{max=0} {if($3>max) max=$3} END {print max}' "$DROP_FILE")
    echo "Longest drop: ${longest}s"
else
    echo "No drops recorded yet (good!)"
fi
echo ""

# Recommendations
echo "=========================================="
echo "Recommendations"
echo "=========================================="

if [ -f "$DROP_FILE" ] && [ -s "$DROP_FILE" ]; then
    noon_drops=$(grep -c "T12:" "$DROP_FILE" 2>/dev/null || echo 0)
    if [ "$noon_drops" -gt 2 ]; then
        echo ""
        echo "🕛 NOON DROP PATTERN DETECTED"
        echo "-----------------------------"
        echo "Your network consistently drops at noon."
        echo ""
        echo "Most likely causes:"
        echo "  1. ISP maintenance window (very common at 12:00)"
        echo "     → Call your ISP, ask about maintenance schedules"
        echo ""
        echo "  2. Router/modem rebooting (firmware updates?)"
        echo "     → Check router logs at 12:00"
        echo "     → Look for scheduled reboots in router settings"
        echo ""
        echo "  3. DHCP lease renewal causing disconnect"
        echo "     → Check if lease time aligns with 24h at noon"
        echo ""
        echo "  4. Power grid fluctuation (lunch hour load)"
        echo "     → Try UPS on router/modem"
        echo ""
    fi
fi

echo ""
echo "To check router logs, visit: http://192.168.68.1"
echo "Look for events around 12:00:00"
