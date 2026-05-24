#!/usr/bin/env bash
# Purge prior-project e-ink holders (GhostRoll, ingest, system waveshare) then leave GPIO free.
# Default: safe for manual isolation — does not disable synth boot e-ink units.
# Aggressive (--aggressive or EINK_PURGE_AGGRESSIVE=1): also stop/disable synth display units.
# Does not stop pi-ambient-synth-midi (audio).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
AGGRESSIVE=0
for arg in "$@"; do
  case "$arg" in
    --aggressive) AGGRESSIVE=1 ;;
  esac
done
[[ "${EINK_PURGE_AGGRESSIVE:-0}" == "1" ]] && AGGRESSIVE=1

PREPARE="$ROOT/scripts/eink_prepare_boot.sh"
if [[ -x "$PREPARE" ]]; then
  INSTALL_DIR="$ROOT" bash "$PREPARE"
else
  LIB="$ROOT/scripts/lib_disable_ghostroll.sh"
  # shellcheck source=lib_disable_ghostroll.sh
  source "$LIB"
  disable_ghostroll_autostart
fi

echo "=== Purge legacy e-ink projects $(date -Iseconds) aggressive=$AGGRESSIVE ==="

echo "==> Mask any ingest / display / ghost units (non-ambient)"
while read -r u _; do
  [[ "$u" =~ (ghostroll|ingest|eink|epaper|e-paper) ]] || continue
  [[ "$u" =~ pi-ambient ]] && continue
  [[ "$u" =~ \.(service|timer|socket|path)$ ]] || continue
  sudo systemctl stop "$u" 2>/dev/null || true
  sudo systemctl disable "$u" 2>/dev/null || true
  sudo systemctl mask "$u" 2>/dev/null || true
  echo "    masked $u"
done < <(systemctl list-unit-files --no-pager --no-legend 2>/dev/null || true)

if [[ "$AGGRESSIVE" == "1" ]]; then
  echo "==> Stop Pi Ambient display units (not MIDI)"
  sudo systemctl stop pi-ambient-synth pi-ambient-synth-monitor \
    pi-ambient-synth-audio-display pi-ambient-synth-boot-display \
    pi-ambient-synth-network-announce pi-ambient-synth-eink-patch \
    pi-ambient-synth-eink-prepare 2>/dev/null || true
  sudo systemctl disable pi-ambient-synth-audio-display pi-ambient-synth-boot-display \
    pi-ambient-synth-eink-patch 2>/dev/null || true
  sudo systemctl mask pi-ambient-synth-audio-display 2>/dev/null || true
  pkill -f show_status 2>/dev/null || true
  pkill -f boot_display 2>/dev/null || true
  pkill -f 'pi-ambient-synth/src/main' 2>/dev/null || true
  sleep 2
else
  echo "==> Synth boot e-ink units left enabled (use --aggressive to stop them)"
fi

echo "==> Kill stray legacy processes"
pkill -f ghostroll 2>/dev/null || true
pkill -f ingest 2>/dev/null || true
pkill -f '/home/pi/ghostroll' 2>/dev/null || true

echo "==> GPIO/SPI holders"
sudo fuser -v /dev/gpiomem /dev/spidev0.0 /dev/spidev0.1 2>/dev/null || echo "(none)"

echo "==> Remaining suspects"
ps aux | grep -iE 'ghostroll|ingest|show_status|boot_display|eink|waveshare' | grep -v grep || echo "(none)"

rm -f /tmp/pi-ambient-synth-eink.lock
echo ""
if [[ "$AGGRESSIVE" == "1" ]]; then
  echo "PURGE_DONE (aggressive) — recommend: sudo reboot"
  echo "Re-enable boot e-ink: $ROOT/scripts/eink_enable_boot_units.sh"
else
  echo "PURGE_DONE — reboot optional; boot path uses eink_prepare_boot + systemd units"
fi
echo "Hardware check: cd $ROOT && .venv/bin/python scripts/eink_official_minimal_test.py epd2in13_V4"
