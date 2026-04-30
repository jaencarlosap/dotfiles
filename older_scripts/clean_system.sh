#!/bin/bash

# Check if the script is run with sudo
if [ "$(id -u)" != "0" ]; then
  echo "Please run this script as root using 'sudo'."
  exit 1
fi

echo "Starting cache cleaning and DNS flushing process..."

# Measure initial disk usage
INITIAL_SPACE=$(df -h / | grep '/' | awk '{print $4}')

# 1. Clear user-level caches
echo "Clearing user-level caches..."
rm -rf ~/Library/Caches/*
rm -rf ~/Library/Application\ Support/CrashReporter/*
rm -rf ~/Library/Containers/*/Data/Library/Caches/*
rm -rf ~/Library/Logs/*

# 2. Clear system caches
echo "Clearing system-level caches..."
rm -rf /Library/Caches/*
rm -rf /System/Library/Caches/*
rm -rf /private/var/folders/*

# 3. Flush DNS cache
echo "Flushing DNS cache..."
dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# 4. Remove temporary files
echo "Removing temporary files..."
rm -rf /private/tmp/*

# 5. Clear logs
echo "Clearing logs..."
rm -rf /private/var/log/*

# Measure final disk usage
FINAL_SPACE=$(df -h / | grep '/' | awk '{print $4}')

# Calculate space freed
SPACE_FREED=$(echo "$INITIAL_SPACE - $FINAL_SPACE" | bc)

echo "-------------------------------------------"
echo "Cleaning process completed successfully!"
echo "Initial Free Space: $INITIAL_SPACE"
echo "Final Free Space: $FINAL_SPACE"
echo "Space Freed Up: $SPACE_FREED"
echo "-------------------------------------------"
