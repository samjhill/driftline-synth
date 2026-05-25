#!/usr/bin/env bash
# Quick checks after enable_recovery_eink.sh (ingest-style PNG watch).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/.venv/bin/python"
PNG="/var/lib/pi-ambient-synth/eink-status.png"
FAILED=""

fail() { FAILED="$1"; echo "FAIL: $1"; }

echo "=== Recovery + e-ink validation (ingest pattern) ==="

if ! systemctl is-active --quiet pi-ambient-synth-midi.service; then
  fail "midi_not_active"
fi
echo "OK: pi-ambient-synth-midi active"

if ! systemctl is-active --quiet pi-ambient-synth-eink.service; then
  fail "eink_not_active"
else
  echo "OK: pi-ambient-synth-eink active"
fi

if [[ ! -e /dev/spidev0.0 ]]; then
  fail "spidev_missing"
else
  echo "OK: /dev/spidev0.0 present"
fi

if ! python3 -c 'from waveshare_epd import epd2in13_V4' 2>/dev/null; then
  fail "waveshare_epd_missing"
else
  echo "OK: system waveshare_epd import"
fi

if [[ ! -f "$PNG" ]]; then
  fail "status_png_missing"
else
  echo "OK: status PNG at $PNG"
fi

if [[ -z "$FAILED" ]]; then
  echo ""
  echo "EINK_RECOVERY_OK"
  exit 0
fi
echo ""
echo "FAILED: $FAILED"
exit 1
