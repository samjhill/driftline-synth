#!/usr/bin/env bash
# Collect e-ink hardware evidence when the panel stays blank (no synth changes).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
OUT="${1:-/tmp/eink-hardware-report.txt}"

{
  echo "=== E-ink hardware report $(date -Iseconds) ==="
  echo "HAT expected: Waveshare 2.13\" e-Paper HAT V4 rev 2.1 (BCM RST=17 DC=25 CS=8 BUSY=24 PWR=18)"
  echo ""
  echo "--- CPU / SPI ---"
  grep -i model /proc/cpuinfo | head -1 || true
  ls -l /dev/spidev* 2>&1 || true
  grep -E '^dtparam=spi|^dtoverlay=.*spi' /boot/firmware/config.txt /boot/config.txt 2>/dev/null || true
  echo ""
  echo "--- GPIO busy (BCM 24) ---"
  PYTHONPATH="$ROOT/vendor/waveshare" GPIOZERO_PIN_FACTORY=lgpio \
    "$ROOT/.venv/bin/python" - <<'PY' 2>&1 || true
from waveshare_epd import epdconfig
epdconfig.module_init()
pin = epdconfig.BUSY_PIN
print("BUSY_PIN", pin, [epdconfig.digital_read(pin) for _ in range(8)])
epdconfig.module_exit()
PY
  echo ""
  echo "--- SPI smoke (spidev xfer) ---"
  "$ROOT/.venv/bin/python" - <<'PY' 2>&1 || true
import spidev
s = spidev.SpiDev()
s.open(0, 0)
s.max_speed_hz = 4000000
s.mode = 0
r = s.xfer2([0x12, 0x00])
print("xfer2 ok, response bytes:", r)
s.close()
PY
  echo ""
  echo "--- Recent e-ink log ---"
  tail -20 /var/log/pi-ambient-synth-eink.log 2>/dev/null || echo "(none)"
  echo ""
  echo "If official test exits 0 but glass never changes:"
  echo "  1) Reseat 24-pin FPC (driver PCB -> glass), not only the 40-pin Pi header"
  echo "  2) Confirm HAT is black/white V4, not HAT (B) red or HAT+"
  echo "  3) Try another Pi or replacement HAT — software path exhausted"
} | tee "$OUT"

echo "Wrote $OUT"
