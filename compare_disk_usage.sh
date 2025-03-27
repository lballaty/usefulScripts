#!/bin/bash

# -------------------------------------------------------
# Script Name: compare_disk_usage.sh
# Purpose:     Analyze disk usage and create a report
#              to help you decide what not to migrate.
# Usage:       Run on both source and target Macs.
#              Then compare the generated reports.
# -------------------------------------------------------

REPORT_DIR=~/disk_usage_report
mkdir -p "$REPORT_DIR"

HOSTNAME=$(hostname)
REPORT_FILE="$REPORT_DIR/disk_report_$HOSTNAME.txt"

echo "📍 Running disk usage scan on: $HOSTNAME"
echo "📅 Timestamp: $(date)" > "$REPORT_FILE"
echo "💾 Disk usage summary (for root /):" >> "$REPORT_FILE"
df -h / >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "📁 Disk usage in $HOME (top-level):" >> "$REPORT_FILE"
du -sh ~/* 2>/dev/null | sort -hr >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "📁 Top 10 largest directories within ~/Documents, ~/Downloads, ~/Movies, ~/Pictures (if they exist):" >> "$REPORT_FILE"

for folder in Documents Downloads Movies Pictures; do
  if [ -d ~/$folder ]; then
    echo "🔹 $folder:" >> "$REPORT_FILE"
    du -sh ~/$folder/* 2>/dev/null | sort -hr | head -n 10 >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi
done

echo "✅ Report saved to: $REPORT_FILE"
echo "📂 To compare, copy this file to your other Mac or share it for analysis."

