#!/usr/bin/env bash
# Leave a high-contrast pattern on the panel for visual confirmation (no sleep).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
cd "$ROOT"

if [[ "$(id -un)" == "root" ]]; then
  exec sudo -u pi env INSTALL_DIR="$ROOT" GPIOZERO_PIN_FACTORY=lgpio "$0" "$@"
fi

systemctl stop pi-ambient-synth-eink.service 2>/dev/null || true
sleep 1

export PYTHONPATH="$ROOT/src:$ROOT/vendor/waveshare"
export GPIOZERO_PIN_FACTORY=lgpio

.venv/bin/python - <<'PY'
import sys
import time
from PIL import Image, ImageDraw

sys.path.insert(0, "src")
from config_loader import load_config
from eink_display import EInkDisplay

cfg = load_config()
d = EInkDisplay(cfg)
if not d.init():
    print("FAIL: init", file=sys.stderr)
    sys.exit(1)

w, h = d.width, d.height
print(f"Panel config: {w}x{h} driver: {d._driver_name}")

print("Clear BLACK — panel should go dark (20s wait)...")
d._epd.Clear(0x00)
d._wait_panel_refresh()
time.sleep(3)

img = Image.new("1", (w, h), 1)
dr = ImageDraw.Draw(img)
dr.rectangle([0, 0, w - 1, 40], fill=0)
dr.text((6, 12), "DRIFTLINE", fill=1)
dr.text((6, 52), "E-INK OK", fill=0)
dr.text((6, 72), f"{w}x{h}", fill=0)
dr.rectangle([0, h - 30, w - 1, h - 1], fill=0)

print("Show bars + text — should stay visible...")
d.show_image(img, full_refresh=False)
print("DONE — panel should show DRIFTLINE / E-INK OK (not blank white)")
print("Service not started; run: sudo systemctl start pi-ambient-synth-eink")
PY
