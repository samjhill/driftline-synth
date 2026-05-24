#!/usr/bin/env bash
# High-contrast e-ink sanity: full black → wait → full white → wait → bars.
# User must SEE the panel change. Does not touch audio services.
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
LOG="${EINK_LOG:-/var/log/pi-ambient-synth-eink.log}"

if [[ "$(id -un)" == "root" ]] && [[ "${EINK_ALLOW_ROOT:-0}" != "1" ]]; then
  exec sudo -u pi env INSTALL_DIR="$ROOT" EINK_LOG="$LOG" GPIOZERO_PIN_FACTORY=lgpio "$0" "$@"
fi

echo "$(date -Iseconds) [eink_sanity] start" | tee -a "$LOG"
cd "$ROOT"
export PYTHONPATH="$ROOT/src:vendor/waveshare"
export GPIOZERO_PIN_FACTORY=lgpio
export EINK_LOG="$LOG"
export EINK_LOCK_FILE="${EINK_LOCK_FILE:-/tmp/pi-ambient-synth-eink.lock}"

.venv/bin/python - <<'PY'
import sys
import time

sys.path.insert(0, "src")
from config_loader import load_config
from eink_display import EInkDisplay
from eink_lock import eink_exclusive_lock

with eink_exclusive_lock(timeout_seconds=60):
    d = EInkDisplay(load_config())
    if not d.init():
        print("EINK_SANITY_FAIL: init", file=sys.stderr)
        sys.exit(1)
    epd = d._epd
    print("Step 1: FULL BLACK (5s) — panel should go dark")
    epd.Clear(0x00)
    d._wait_panel_refresh()
    time.sleep(5)
    print("Step 2: FULL WHITE (5s) — panel should flash bright")
    epd.Clear(0xFF)
    d._wait_panel_refresh()
    time.sleep(5)
    from PIL import Image, ImageDraw

    w, h = d.width, d.height
    img = Image.new("1", (w, h), 1)
    dr = ImageDraw.Draw(img)
    for i in range(0, w, 14):
        dr.rectangle([i, 0, i + 10, h - 1], fill=0)
    dr.text((8, h // 2 - 10), "DRIFTLINE", fill=0)
    print("Step 3: BLACK BARS + text")
    d.show_image(img, full_refresh=True)
    time.sleep(3)
    d.release()
print("EINK_SANITY_DONE — confirm you saw black, white, then bars")
PY

echo "$(date -Iseconds) [eink_sanity] done" | tee -a "$LOG"
