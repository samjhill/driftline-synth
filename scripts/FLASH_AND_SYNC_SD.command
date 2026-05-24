#!/bin/bash
# Double-click in Finder (or: open scripts/FLASH_AND_SYNC_SD.command)
# Flashes Raspberry Pi OS Lite to an external SD card and syncs Pi Ambient Synth.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

echo "=== Pi Ambient Synth — flash + sync ==="
diskutil list external physical
echo ""
read -p "Enter disk number to ERASE (e.g. 4 for disk4): " N
DISK="disk${N}"

if [[ ! -b "/dev/$DISK" ]]; then
  echo "ERROR: /dev/$DISK not found"
  read -p "Press Enter to close..."
  exit 1
fi

diskutil info "/dev/$DISK" | grep -E "Device / Media Name|Disk Size|Mount Point"
echo ""
echo "WARNING: ERASES ALL DATA on /dev/$DISK"
read -p "Type YES to continue: " OK
[[ "$OK" == YES ]] || exit 1

export FLASH_SKIP_CONFIRM=1
export FLASH_USE_SYNC=1
bash "$ROOT/scripts/flash_sd_mac.sh" "$DISK"

echo ""
echo "SD card is ready. Eject safely, insert into Pi, power on."
echo "First boot: ~10–20 min (e-ink may show BOOT / INSTALL steps)."
echo "SSH: ssh pi@raspberrypi.local  (password: raspberry — change it)"
read -p "Press Enter to close..."
