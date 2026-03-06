#!/bin/bash
# Network Monitor Analysis - Single File
# Paste into File Editor as /config/network_monitor/analyze.sh
# Run: bash /config/network_monitor/analyze.sh

LOG_DIR="/config/network_monitor"
HICCUP_FILE="$LOG_DIR/hiccups.log"
DROP_FILE="$LOG_DIR/drops.log"

echo "=========================================="
echo "Network Hiccup Analysis"
echo "=========================================="
echo ""

echo "Total Events:"
[ -f "$HICCUP_FILE" ] && echo "  Hiccups: $(wc -l < "$HICCUP_FILE")" || echo "  No hiccups yet"
[ -f "$DROP_FILE" ] && [ -s "$DROP_FILE" ] && echo "  Drops: $(wc -l < "$DROP_FILE")" || echo "  No drops yet (good!)"
echo ""

if [ -f "$HICCUP_FILE" ]; then
    echo "Events by Hour:"
    echo "Hour | Count"
    echo "-----|------"
    for hour in $(seq 0 23); do
        count=$(grep "T$(printf "%02d" $hour):" "$HICCUP_FILE" 2>/dev/null | wc -l)
        [ $count -gt 0 ] && printf "%02d:00 | %5d\n" $hour $count
    done
    echo ""
    
    echo "🕛 NOON ANALYSIS (11:00-13:00):"
    noon=$(grep -E "T1[12]:" "$HICCUP_FILE" 2>/dev/null | wc -l)
    total=$(wc -l < "$HICCUP_FILE")
    [ $total -gt 0 ] && pct=$((noon * 100 / total)) || pct=0
    echo "Noon events: $noon / $total ($pct%)"
    [ $pct -gt 30 ] && echo "⚠️  STRONG noon pattern!"
    [ $pct -gt 15 ] && [ $pct -le 30 ] && echo "⚠️  Moderate noon pattern"
    grep -E "T1[12]:" "$HICCUP_FILE" 2>/dev/null | tail -5
    echo ""
fi

if [ -f "$DROP_FILE" ] && [ -s "$DROP_FILE" ]; then
    echo "🚨 DROPS:"
    echo "Timestamp          | Target | Duration"
    while IFS=',' read -r ts target dur; do printf "%-18s | %-6s | %ss\n" "$ts" "$target" "$dur"; done < "$DROP_FILE"
    avg=$(awk -F',' '{sum+=$3; c++} END {if(c>0) printf "%.1f", sum/c}' "$DROP_FILE")
    echo "Average drop: ${avg}s"
    noon_drops=$(grep -c "T12:" "$DROP_FILE" 2>/dev/null || echo 0)
    [ "$noon_drops" -gt 2 ] && echo "🕛 NOON DROP PATTERN - Likely ISP maintenance!"
fi
