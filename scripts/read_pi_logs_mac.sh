#!/usr/bin/env bash
# Read Pi logs from SD card on Mac. Boot logs need no sudo; root needs admin + Full Disk Access.
set -u

export PATH="/opt/homebrew/bin:/opt/homebrew/Cellar/e2tools/0.1.2/bin:$PATH"
BOOT_VOL="${1:-/Volumes/bootfs}"
FOUND=0

echo "========== Boot partition (FAT) =========="
if [[ -d "$BOOT_VOL/pi-ambient-synth/boot-logs" ]]; then
  shopt -s nullglob
  files=("$BOOT_VOL/pi-ambient-synth/boot-logs"/*)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "(boot-logs/ is empty — cloud-init first-boot script likely never ran or failed before logging)"
  else
    for f in "${files[@]}"; do
      [[ -f "$f" ]] || continue
      FOUND=1
      echo ""
      echo "--- $(basename "$f") ---"
      tail -100 "$f"
    done
  fi
else
  echo "(no boot-logs/ directory)"
fi

echo ""
echo "--- meta-data instance_id ---"
grep '^instance_id:' "$BOOT_VOL/meta-data" 2>/dev/null || true

echo ""
echo "--- user-data (first 20 lines) ---"
head -20 "$BOOT_VOL/user-data" 2>/dev/null || true

DISK="$(diskutil list external 2>/dev/null | awk '/Linux/ {print $NF; exit}')"
if [[ -z "$DISK" ]]; then
  echo ""
  echo "No Linux root partition found."
  exit 0
fi

DEV="/dev/r${DISK#*/}"
echo ""
echo "========== Root partition ($DISK) =========="
echo "If you see 'Operation not permitted', run this script in Terminal.app:"
echo "  System Settings → Privacy & Security → Full Disk Access → enable Terminal"
echo ""

for log in \
  /var/log/cloud-init-output.log \
  /var/log/cloud-init.log \
  /var/log/pi-ambient-synth-deploy.log \
  /var/log/pi-ambient-synth-eink.log \
  /var/lib/pi-ambient-synth/network.json \
  /var/lib/cloud/data/status.json; do
  echo "--- $log ---"
  if e2tail -n 60 "$DEV:$log" 2>/dev/null; then
    FOUND=1
  else
    echo "(unreadable)"
  fi
  echo ""
done

if [[ "$FOUND" -eq 0 ]]; then
  echo "No log content read. Use: sudo $0"
  exit 1
fi
