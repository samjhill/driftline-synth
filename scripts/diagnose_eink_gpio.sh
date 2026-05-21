#!/usr/bin/env bash
# Diagnose e-ink / GPIO conflicts (e.g. after another project on the same Pi).
#   bash ~/pi-ambient-synth/scripts/diagnose_eink_gpio.sh
set -euo pipefail

echo "=== E-ink / GPIO diagnostics ==="
echo "User: $(id -un)  HOME=${HOME:-<unset>}  cwd=$(pwd)"
echo ""

echo "--- SPI ---"
ls -l /dev/spidev* 2>/dev/null || echo "(no /dev/spidev* — enable SPI in raspi-config)"
echo ""

echo "--- Groups (pi should include gpio, spi) ---"
groups pi 2>/dev/null || groups
echo ""

echo "--- Services (ambient + common ingest names) ---"
for u in \
  pi-ambient-synth \
  pi-ambient-synth-deploy.service \
  pi-ambient-synth-deploy.timer \
  ingest \
  ingest.service \
  pisugar-server; do
  state="$(systemctl is-active "$u" 2>/dev/null || echo n/a)"
  enabled="$(systemctl is-enabled "$u" 2>/dev/null || echo n/a)"
  printf "  %-40s active=%-12s enabled=%s\n" "$u" "$state" "$enabled"
done
echo ""

echo "--- Processes that often hold GPIO ---"
ps aux | grep -E '[Pp]ython|ingest|waveshare|gpio|pisugar|boot_display|show_status|pi-ambient' \
  | grep -v grep || echo "(none matched)"
echo ""

echo "--- Python waveshare installs (prefer vendor/ only) ---"
/usr/bin/python3 -c "import waveshare_epd; print('system:', waveshare_epd.__file__)" 2>/dev/null \
  || echo "system python: no waveshare_epd"
if [[ -x /home/pi/pi-ambient-synth/.venv/bin/python ]]; then
  /home/pi/pi-ambient-synth/.venv/bin/python -c "import waveshare_epd; print('venv:', waveshare_epd.__file__)" 2>/dev/null \
    || echo "venv: no waveshare_epd"
fi
echo ""

echo "--- lgpio scratch files (should be under /home/pi) ---"
ls -la /home/pi/.lgd-* 2>/dev/null || echo "(none in /home/pi)"
ls -la ./.lgd-* 2>/dev/null || true
echo ""

echo "--- Recent e-ink log ---"
tail -15 /var/log/pi-ambient-synth-eink.log 2>/dev/null || echo "(no log yet)"
echo ""
echo "If GPIO busy persists after stopping services above, try:"
echo "  sudo systemctl disable --now <old-ingest-service>"
echo "  sudo rm -rf /usr/local/lib/python3.*/dist-packages/waveshare_epd"
echo "  sudo reboot   # clears stuck lgpio from killed processes"
echo "  SKIP_SYNC=1 bash ~/pi-ambient-synth/scripts/eink_pull_and_refresh.sh"
