#!/usr/bin/env bash
# Diagnose e-ink / GPIO conflicts (GhostRoll, ingest, parallel display jobs).
#   bash ~/pi-ambient-synth/scripts/diagnose_eink_gpio.sh
set -euo pipefail

INSTALL="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
LOCK="${EINK_LOCK_FILE:-/tmp/pi-ambient-synth-eink.lock}"
LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}"

echo "=== E-ink / GPIO diagnostics ==="
echo "User: $(id -un)  UID=$(id -u)  HOME=${HOME:-<unset>}  cwd=$(pwd)"
echo "INSTALL_DIR=$INSTALL  EINK_LOCK=$LOCK"
echo ""

echo "--- SPI enabled? ---"
if ls /dev/spidev* >/dev/null 2>&1; then
  ls -l /dev/spidev*
else
  echo "NO — enable SPI: sudo raspi-config nonint do_spi 0"
fi
echo ""

echo "--- Groups (pi should include gpio, spi) ---"
groups pi 2>/dev/null || groups
echo ""

echo "--- E-ink lock ---"
if [[ -f "$LOCK" ]]; then
  echo "lock file exists: $LOCK"
  if command -v fuser >/dev/null; then
    fuser -v "$LOCK" 2>/dev/null || echo "(fuser: none)"
  fi
else
  echo "lock file absent: $LOCK"
fi
echo ""

echo "--- GhostRoll / ingest processes ---"
ps aux | grep -iE 'ghostroll|ingest' | grep -v grep || echo "(none)"
echo ""

echo "--- show_status.py / boot_display / eink_show processes ---"
ps aux | grep -E 'show_status\.py|boot_display\.sh|eink_show_patch|test_eink\.py|refresh_eink' \
  | grep -v grep || echo "(none)"
while read -r line; do
  [[ -z "$line" ]] && continue
  pid="$(echo "$line" | awk '{print $2}')"
  user="$(echo "$line" | awk '{print $1}')"
  echo "  pid=$pid user=$user cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}')"
done < <(
  ps aux | grep -E 'show_status\.py|boot_display\.sh|eink_show_patch' | grep -v grep || true
)
echo ""

echo "--- Processes on SPI/GPIO (best-effort) ---"
if command -v fuser >/dev/null; then
  for dev in /dev/spidev0.0 /dev/spidev0.1 /dev/gpiochip0; do
    if [[ -e "$dev" ]]; then
      echo "$dev:"
      fuser -v "$dev" 2>/dev/null || echo "  (none)"
    fi
  done
else
  echo "(fuser not installed)"
fi
echo ""

echo "--- systemd: e-ink / display / GhostRoll / ambient ---"
systemctl list-units --all --no-pager 2>/dev/null | grep -iE \
  'ghostroll|ingest|eink|display|pi-ambient-synth|pi-ambient-jack|supercollider|flues' || echo "(none matched)"
echo ""

for u in \
  pi-ambient-synth \
  pi-ambient-synth-midi \
  pi-ambient-synth-monitor \
  pi-ambient-synth-boot-display \
  pi-ambient-synth-audio-display \
  pi-ambient-synth-deploy.timer \
  pi-ambient-jack-playback.timer \
  supercollider \
  ghostroll-watch; do
  state="$(systemctl is-active "$u" 2>/dev/null || echo n/a)"
  enabled="$(systemctl is-enabled "$u" 2>/dev/null || echo n/a)"
  masked="$(systemctl is-enabled "$u" 2>/dev/null | grep masked && echo yes || echo no)"
  printf "  %-42s active=%-10s enabled=%s\n" "$u" "$state" "$enabled"
done
echo ""

echo "--- Audio mode ---"
cat /etc/pi-ambient-synth/audio-mode.conf 2>/dev/null || echo "(no audio-mode.conf)"
echo ""

echo "--- waveshare_epd import ---"
if [[ -x "$INSTALL/.venv/bin/python" ]]; then
  "$INSTALL/.venv/bin/python" -c "import waveshare_epd; print('venv OK:', waveshare_epd.__file__)" 2>&1 \
    || echo "venv: import failed"
else
  echo "venv python missing at $INSTALL/.venv/bin/python"
fi
/usr/bin/python3 -c "import waveshare_epd; print('system:', waveshare_epd.__file__)" 2>/dev/null \
  || echo "system python: no waveshare_epd"
echo ""

echo "--- Busy polarity cache ---"
cat /var/lib/pi-ambient-synth/eink-busy-active-high 2>/dev/null \
  && echo "(cached busy_active_high above)" \
  || echo "(no cache yet)"
echo ""

echo "--- Last e-ink status marker ---"
cat /var/lib/pi-ambient-synth/last_eink_status 2>/dev/null || echo "(none)"
cat /var/lib/pi-ambient-synth/eink-status.json 2>/dev/null || true
echo ""

echo "--- Recent e-ink log ($LOG) ---"
tail -25 "$LOG" 2>/dev/null || echo "(no log yet)"
echo ""

echo "If GPIO busy: stop GhostRoll → scripts/free_eink_for_ambient.sh"
echo "Canonical refresh: sudo -u pi $INSTALL/scripts/eink_show_patch_status.sh"
