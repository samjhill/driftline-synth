#!/usr/bin/env bash
# Free the Waveshare 2.13" HAT for Pi Ambient Synth (stops GhostRoll / other holders).
#   curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/free_eink_for_ambient.sh" | bash
set -euo pipefail

LIB="$(dirname "${BASH_SOURCE[0]:-$0}")/lib_disable_ghostroll.sh"
if [[ ! -f "$LIB" ]]; then
  LIB="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/lib_disable_ghostroll.sh" -o "$LIB"
  trap 'rm -f "$LIB"' EXIT
fi
# shellcheck source=lib_disable_ghostroll.sh
source "$LIB"

echo "=== Free e-ink for Pi Ambient Synth ==="
disable_ghostroll_autostart
sleep 2

echo "==> Stopping Pi Ambient Synth e-ink users..."
sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-deploy.service 2>/dev/null || true
sudo systemctl stop pi-ambient-synth 2>/dev/null || true
sudo pkill -f 'show_status\.py|boot_display\.sh' 2>/dev/null || true
sleep 2

echo "==> Optional: remove system waveshare (use vendor/ in pi-ambient-synth instead)"
if [[ "${REMOVE_SYSTEM_WAVESHARE:-0}" == "1" ]]; then
  sudo rm -rf /usr/local/lib/python3.*/dist-packages/waveshare_epd 2>/dev/null || true
  sudo rm -f /usr/local/sbin/ghostroll-eink-waveshare213v4.py 2>/dev/null || true
  echo "    removed system waveshare + ghostroll e-ink helper"
else
  echo "    skipped (set REMOVE_SYSTEM_WAVESHARE=1 to delete /usr/local waveshare)"
fi

echo "==> Remaining GPIO-related processes:"
ps aux | grep -E 'ghostroll|waveshare|show_status|boot_display|pi-ambient-synth/src/main' \
  | grep -v grep || echo "    (none)"
echo ""
echo "Done. Test display as user pi:"
echo "  cd /home/pi/pi-ambient-synth"
echo "  SKIP_SYNC=1 EINK_FORCE=1 ./scripts/boot_display.sh ready \"Test\" \"e-ink free\" \"\""
echo ""
echo "GhostRoll will not start on boot until you unmask/enable it again."
