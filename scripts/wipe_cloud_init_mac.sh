#!/usr/bin/env bash
# Force cloud-init to re-run first-boot on next Pi boot (clears cached state on root FS).
# Requires admin + Full Disk Access in Terminal.app.
set -euo pipefail

export PATH="/opt/homebrew/Cellar/e2tools/0.1.2/bin:$PATH"

DISK="$(diskutil list external 2>/dev/null | awk '/Linux/ {print $NF; exit}')"
if [[ -z "$DISK" ]]; then
  echo "ERROR: No Linux root partition on external SD"
  exit 1
fi

DEV="/dev/r${DISK#*/}"
echo "Wiping cloud-init cache on $DEV (next boot will re-run user-data)..."
for p in \
  /var/lib/cloud/instances \
  /var/lib/cloud/instance-id \
  /var/lib/cloud/data \
  /var/lib/cloud/sem \
  /var/lib/cloud/scripts \
  /var/lib/cloud/seed; do
  e2rm -r "$DEV:$p" 2>/dev/null && echo "  removed $p" || true
done
for p in \
  /var/lib/pi-ambient-synth/boot-sentinel-done \
  /var/lib/pi-ambient-synth/autobringup-done \
  /var/lib/pi-ambient-synth/eink-boot-shown \
  /var/lib/pi-ambient-synth/firstboot-light-done \
  /var/lib/pi-ambient-synth/firstboot-heavy-done; do
  e2rm "$DEV:$p" 2>/dev/null && echo "  removed $p" || true
done
echo "Done. Re-sync boot partition if needed, then boot Pi."
