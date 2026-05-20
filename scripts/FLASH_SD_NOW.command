#!/bin/bash
# Double-click or run in Terminal.app to flash Raspberry Pi OS Lite to SD card.
# Requires admin password. Target: external disk named bootfs's parent (disk5).
set -euo pipefail

IMG="$HOME/Library/Caches/pi-ambient-synth/2026-04-21-raspios-trixie-arm64-lite.img"
IMG_XZ="$IMG.xz"
URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-04-21/2026-04-21-raspios-trixie-arm64-lite.img.xz"
SHA="4cd31df026fd82243805a326dc0cafd7383f7e3d30c9413e7044d507aae281e2"

echo "=== Pi Ambient Synth — SD Card Flasher ==="
echo ""
diskutil list external physical
echo ""
read -p "Enter disk number to ERASE (e.g. 5 for disk5): " N
DISK="disk${N}"
rdisk="r${DISK}"

if [[ ! -b "/dev/$DISK" ]]; then
  echo "ERROR: /dev/$DISK not found"
  exit 1
fi

diskutil info "/dev/$DISK" | grep -E "Device / Media Name|Disk Size|Mount Point"
echo ""
echo "WARNING: This will ERASE ALL DATA on /dev/$DISK"
read -p "Type YES to flash: " OK
[[ "$OK" == "YES" ]] || exit 1

mkdir -p "$(dirname "$IMG")"
[[ -f "$IMG_XZ" ]] || curl -L -o "$IMG_XZ" "$URL"
echo "$SHA  $IMG_XZ" | shasum -a 256 -c -
[[ -f "$IMG" ]] || xz -dk "$IMG_XZ"

diskutil unmountDisk force "/dev/$DISK"
echo "Flashing (5–15 min)..."
sudo dd if="$IMG" of="/dev/$rdisk" bs=4m conv=sync
sync
diskutil eject "/dev/$DISK"

echo ""
echo "Done. Re-insert card, then run configure_boot.sh or re-mount bootfs."
read -p "Press Enter to configure boot partition when it reappears..."
for i in {1..60}; do
  for v in /Volumes/bootfs /Volumes/boot; do
    if [[ -d "$v" ]]; then
      touch "$v/ssh"
      grep -q 'dtparam=spi=on' "$v/config.txt" 2>/dev/null || echo 'dtparam=spi=on' >> "$v/config.txt"
      SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
      rsync -a --exclude .venv --exclude .git "$SCRIPT_DIR/../" "$v/pi-ambient-synth/"
      echo "Configured $v"
      diskutil eject "$v"
      exit 0
    fi
  done
  sleep 2
done
echo "Mount boot volume manually and copy pi-ambient-synth from this repo."
