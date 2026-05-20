#!/usr/bin/env bash
# Flash Raspberry Pi OS Lite to SD card on macOS and configure for Pi Ambient Synth.
set -euo pipefail

DISK="${1:-}"
IMG_XZ_URL="${IMG_XZ_URL:-https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-04-21/2026-04-21-raspios-trixie-arm64-lite.img.xz}"
IMG_SHA256="${IMG_SHA256:-4cd31df026fd82243805a326dc0cafd7383f7e3d30c9413e7044d507aae281e2}"
CACHE_DIR="${CACHE_DIR:-$HOME/Library/Caches/pi-ambient-synth}"
IMG_XZ="$CACHE_DIR/2026-04-21-raspios-trixie-arm64-lite.img.xz"
IMG="$CACHE_DIR/2026-04-21-raspios-trixie-arm64-lite.img"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "$DISK" ]]; then
  echo "Usage: $0 diskN   (e.g. disk5 — NOT disk5s1)"
  echo ""
  diskutil list | grep -E "external|disk[0-9]+"
  exit 1
fi

if [[ "$DISK" == *s* ]]; then
  echo "ERROR: Pass the whole disk (e.g. disk5), not a partition (disk5s1)."
  exit 1
fi

echo "Target: /dev/$DISK"
diskutil info "/dev/$DISK" | grep -E "Device / Media Name|Disk Size|Protocol"
read -r -p "This ERASES /dev/$DISK. Type YES to continue: " confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }

mkdir -p "$CACHE_DIR"
if [[ ! -f "$IMG_XZ" ]]; then
  echo "Downloading Raspberry Pi OS Lite (~551 MB)..."
  curl -L --progress-bar -o "$IMG_XZ" "$IMG_XZ_URL"
fi

echo "Verifying SHA256..."
echo "$IMG_SHA256  $IMG_XZ" | shasum -a 256 -c -

if [[ ! -f "$IMG" ]]; then
  echo "Decompressing image..."
  xz -dk "$IMG_XZ"
fi

echo "Unmounting /dev/$DISK..."
diskutil unmountDisk force "/dev/$DISK"

echo "Writing image (sudo required)..."
sudo dd if="$IMG" of="/dev/r$DISK" bs=4m conv=sync status=progress

sync
diskutil eject "/dev/$DISK"
sleep 3

echo "Waiting for boot partition..."
for i in {1..30}; do
  if [[ -d /Volumes/bootfs ]] || [[ -d /Volumes/boot ]]; then
    break
  fi
  sleep 1
done

BOOT=""
for v in /Volumes/bootfs /Volumes/boot /Volumes/firmware; do
  [[ -d "$v" ]] && BOOT="$v" && break
done

if [[ -z "$BOOT" ]]; then
  echo "Flash complete. Re-insert card or mount boot volume, then run:"
  echo "  $0 --configure-only /Volumes/bootfs"
  exit 0
fi

configure_boot() {
  local b="$1"
  echo "Configuring $b for Pi Ambient Synth..."
  touch "$b/ssh"
  if ! grep -q '^dtparam=spi=on' "$b/config.txt" 2>/dev/null; then
    echo "dtparam=spi=on" >> "$b/config.txt"
  fi
  mkdir -p "$b/pi-ambient-synth"
  rsync -a --exclude .venv --exclude .git --exclude state --exclude __pycache__ \
    "$ROOT/" "$b/pi-ambient-synth/"
  cat > "$b/pi-ambient-synth-firstboot.sh" << 'FB'
#!/bin/bash
set -e
MARKER=/var/lib/pi-ambient-synth-firstboot-done
[[ -f "$MARKER" ]] && exit 0
SRC=/boot/firmware/pi-ambient-synth
[[ -d "$SRC" ]] || SRC=/boot/pi-ambient-synth
[[ -d "$SRC" ]] || exit 0
id -u pi &>/dev/null || useradd -m -s /bin/bash pi 2>/dev/null || true
install -d -o pi -g pi /home/pi/pi-ambient-synth
rsync -a "$SRC/" /home/pi/pi-ambient-synth/
chown -R pi:pi /home/pi/pi-ambient-synth
sudo -u pi bash -lc 'cd /home/pi/pi-ambient-synth && ./install.sh' || true
touch "$MARKER"
FB
  chmod +x "$b/pi-ambient-synth-firstboot.sh"
  if [[ -f "$b/cmdline.txt" ]] && ! grep -q pi-ambient-synth-firstboot "$b/cmdline.txt"; then
    sed -i '' 's/$/ systemd.run\/boot\/pi-ambient-synth-firstboot.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.service/' "$b/cmdline.txt" 2>/dev/null || true
  fi
  echo "Done. Boot partition configured at $b"
}

if [[ "${2:-}" == "--configure-only" ]] && [[ -n "${3:-}" ]]; then
  configure_boot "$3"
else
  [[ -n "$BOOT" ]] && configure_boot "$BOOT"
fi

echo ""
echo "SD card ready. Insert into Pi, power on, wait for first-boot install (~10–20 min)."
echo "Then: ssh pi@<hostname>.local  (default password — change on first login)"
