#!/usr/bin/env python3
"""Hardware RST pulse only — no display init."""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "vendor" / "waveshare"))
os.environ.setdefault("HOME", "/home/pi")
os.environ.setdefault("GPIOZERO_PIN_FACTORY", "lgpio")


def main() -> int:
    from waveshare_epd import epdconfig

    impl = epdconfig._get_implementation()
    busy = impl.BUSY_PIN
    rst = impl.RST_PIN
    print(f"RST=BCM{rst} BUSY=BCM{busy} (from waveshare_epd)")

    epdconfig.module_init()
    before = epdconfig.digital_read(busy)
    print(f"BUSY before reset: {before}")

    print("RST low 500ms...")
    epdconfig.digital_write(rst, 0)
    time.sleep(0.5)
    mid = epdconfig.digital_read(busy)
    print(f"BUSY during RST low: {mid}")

    print("RST high, wait 2s...")
    epdconfig.digital_write(rst, 1)
    time.sleep(2.0)
    after = epdconfig.digital_read(busy)
    print(f"BUSY after reset: {after}")

    epdconfig.module_exit()
    print("EINK_HARD_RESET_ONLY_DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
