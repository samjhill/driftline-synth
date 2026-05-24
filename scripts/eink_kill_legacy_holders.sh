#!/usr/bin/env bash
# Stop/mask ALL prior-project holders of the Waveshare HAT (GhostRoll, ingest, system waveshare).
# Does not disable pi-ambient-synth-midi (audio).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() {
  echo "$(date -Iseconds) [eink_kill_legacy] $*" | tee -a "$LOG" >/dev/null
}

log "start"

LIB="$ROOT/scripts/lib_disable_ghostroll.sh"
if [[ -f "$LIB" ]]; then
  # shellcheck source=lib_disable_ghostroll.sh
  source "$LIB"
  disable_ghostroll_autostart
fi

# Force null-mask (mask can fail if unit file is broken but service was only disabled).
mask_unit() {
  local u=$1
  sudo systemctl stop "$u" 2>/dev/null || true
  sudo systemctl disable "$u" 2>/dev/null || true
  if ! sudo systemctl mask "$u" 2>/dev/null; then
    sudo ln -sf /dev/null "/etc/systemd/system/$u" 2>/dev/null || true
  fi
  log "masked $u"
}

for u in ghostroll-eink.service ghostroll-watch.service ghostroll-wifi-setup.service; do
  if systemctl list-unit-files "$u" &>/dev/null; then
    mask_unit "$u"
  fi
done

while read -r u _; do
  [[ "$u" =~ (ghostroll|ingest|eink|epaper|e-paper) ]] || continue
  [[ "$u" =~ pi-ambient-synth ]] && continue
  [[ "$u" =~ \.(service|timer|socket|path)$ ]] || continue
  mask_unit "$u"
done < <(systemctl list-unit-files --no-pager --no-legend 2>/dev/null || true)

log "kill processes"
pkill -9 -f ghostroll 2>/dev/null || true
pkill -9 -f '/home/pi/ghostroll' 2>/dev/null || true
pkill -9 -f ghostroll-eink-waveshare 2>/dev/null || true
pkill -9 -f '/usr/local/sbin/ghostroll' 2>/dev/null || true
pkill -9 -f '/usr/local/bin/ghostroll' 2>/dev/null || true
# Stray refreshes (not MIDI)
pkill -9 -f 'show_status\.py|boot_display\.sh|eink_boot_sequence|eink_official_minimal' 2>/dev/null || true
sleep 1

sudo rm -rf /usr/local/lib/python3.*/dist-packages/waveshare_epd 2>/dev/null || true
sudo rm -f /usr/local/sbin/ghostroll-eink-waveshare213v4.py 2>/dev/null || true

rm -f /home/pi/.lgd-* /tmp/pi-ambient-synth-eink.lock 2>/dev/null || true

log "GPIO/SPI holders after kill"
timeout 3 sudo fuser -v /dev/spidev0.0 2>/dev/null || echo "(none)"

log "done"
