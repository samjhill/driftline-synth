#!/usr/bin/env bash
# Full e-ink hardware isolation (no audio, no app display code).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
cd "$ROOT"
LOG="${EINK_ISOLATION_LOG:-/home/pi/pi-ambient-synth-eink-isolation.log}"
PY="${ROOT}/.venv/bin/python"
export GPIOZERO_PIN_FACTORY=lgpio
export PYTHONPATH="${ROOT}/vendor/waveshare:${ROOT}/src"

exec > >(tee -a "$LOG") 2>&1
echo "=== eink isolation $(date -Iseconds) ==="

echo "=== Step 1: full cleanup ==="
sudo systemctl stop pi-ambient-synth pi-ambient-synth-monitor \
  pi-ambient-synth-audio-display pi-ambient-synth-boot-display \
  pi-ambient-synth-network-announce 2>/dev/null || true
# Do not stop pi-ambient-synth-midi (audio path).
pkill -f show_status.py 2>/dev/null || true
pkill -f boot_display 2>/dev/null || true
pkill -f test_eink 2>/dev/null || true
pkill -f eink_official 2>/dev/null || true
pkill -f ghostroll 2>/dev/null || true
pkill -f ingest 2>/dev/null || true
sleep 1
echo "--- remaining display-related processes ---"
ps aux | grep -iE 'show_status|boot_display|test_eink|eink_|ghostroll|ingest|waveshare' | grep -v grep || echo "(none)"
sudo fuser -v /dev/gpiomem /dev/spidev0.0 /dev/spidev0.1 2>/dev/null || echo "(fuser: none)"

echo "=== Step 2: pin map (from driver) ==="
"$PY" -c "
from waveshare_epd import epdconfig
i = epdconfig._get_implementation()
for n in ('RST_PIN','DC_PIN','CS_PIN','BUSY_PIN','PWR_PIN'):
    print(f'{n} = BCM {getattr(i,n)}')
"

echo "=== Step 3: raw GPIO report ==="
"$PY" scripts/eink_gpio_raw_report.py

echo "=== Step 4: hard reset only ==="
"$PY" scripts/eink_hard_reset_only.py

echo "=== Step 5: official minimal (V4, V3, V2) ==="
"$PY" scripts/eink_official_minimal_test.py

echo "=== Step 6: diagnosis hint (software; user confirms visibility) ==="
BUSY_SAMPLES=$("$PY" -c "
import os, sys, time
sys.path.insert(0, 'vendor/waveshare')
os.environ.setdefault('GPIOZERO_PIN_FACTORY','lgpio')
from waveshare_epd import epdconfig
epdconfig.module_init()
b = epdconfig._get_implementation().BUSY_PIN
s = [epdconfig.digital_read(b) for _ in range(5)]
epdconfig.module_exit()
print(max(s), min(s), len(set(s)))
" 2>/dev/null || echo "? ? ?")

echo "BUSY sample summary (max min unique_count): $BUSY_SAMPLES"
echo ""
echo "USER MUST CONFIRM: Did you see full BLACK then WHITE during Step 5?"
echo "Reply: VISIBLE_YES or VISIBLE_NO"
echo ""
echo "Software classification (pending user eyes):"
echo "  If VISIBLE_YES -> A) DISPLAY_VISIBLE_OFFICIAL_TEST_WORKED"
echo "  If VISIBLE_NO and one driver log differs -> B) DRIVER_VARIANT_MISMATCH"
echo "  If VISIBLE_YES but BUSY stuck -> C) GPIO_BUSY_STUCK_BUT_DISPLAY_UPDATES"
echo "  If VISIBLE_NO, BUSY stuck, FPC reseated -> D) GPIO_BUSY_STUCK_AND_NO_VISIBLE_UPDATE_AFTER_FPC_RESEAT"
echo "  If fuser showed holders -> E) GPIO_CONFLICT_FOUND"
echo ""
echo "=== isolation complete $(date -Iseconds) ==="
