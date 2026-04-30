#!/bin/bash

echo "=== ISO to USB Burner Script (macOS) ==="

# Prompt for ISO file path
read -p "Enter the full path to your ISO file: " ISO_PATH

# Check if file exists
if [ ! -f "$ISO_PATH" ]; then
  echo "❌ ISO file not found at: $ISO_PATH"
  exit 1
fi

# Prompt for disk identifier
diskutil list
read -p "Enter the disk identifier (e.g., disk2) of your USB drive: " DISK_ID
DISK_PATH="/dev/$DISK_ID"
RAW_DISK_PATH="/dev/r$DISK_ID"

# Unmount disk
echo "🔄 Unmounting $DISK_PATH..."
diskutil unmountDisk "$DISK_PATH"

# Convert ISO to IMG
IMG_PATH="${ISO_PATH%.*}.img"
echo "🔁 Converting ISO to IMG..."
hdiutil convert -format UDRW -o "$IMG_PATH" "$ISO_PATH"

# dd command to write image
echo "⚠️ Writing to USB at $RAW_DISK_PATH — this will erase it!"
read -p "Are you sure? Type 'YES' to continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "❌ Aborted."
  exit 1
fi

echo "📝 Writing image..."
sudo dd if="${IMG_PATH}.dmg" of="$RAW_DISK_PATH" bs=1m status=progress conv=sync

# Eject the disk
echo "⏏️ Ejecting $DISK_PATH..."
diskutil eject "$DISK_PATH"

echo "✅ Done! You can now remove the USB drive."
