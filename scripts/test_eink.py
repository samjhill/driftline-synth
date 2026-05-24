#!/usr/bin/env python3
"""Test Waveshare 2.13\" e-ink display."""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config
from eink_display import EInkDisplay, EinkBusyTimeoutError
from eink_lock import eink_exclusive_lock
from eink_status import write_eink_status
from logging_setup import setup_logging
from PIL import Image, ImageDraw, ImageFont

setup_logging("INFO")


def main() -> int:
    config = load_config()
    if not config.get("eink", {}).get("enabled", True):
        write_eink_status("DISABLED", detail="test_eink")
        return 0
    try:
        with eink_exclusive_lock(timeout_seconds=30.0):
            display = EInkDisplay(config)
            try:
                ok = display.init()
                if not ok:
                    write_eink_status("INIT_FAILED", detail="test_eink init")
                    print(
                        "Display not available (stub mode). Install Waveshare driver on Pi."
                    )
                    return 1
                w, h = display.width, display.height
                pattern = Image.new("1", (w, h), 1)
                draw = ImageDraw.Draw(pattern)
                for y in range(0, h, 8):
                    draw.line([(0, y), (w, y)], fill=0 if (y // 8) % 2 else 1)
                display.show_image(pattern, full_refresh=False)
                time.sleep(2)
                text_img = Image.new("1", (w, h), 1)
                draw = ImageDraw.Draw(text_img)
                try:
                    font = ImageFont.load_default()
                except Exception:
                    font = None
                draw.text((10, h // 2 - 8), "Pi Ambient Synth", fill=0, font=font)
                display.show_image(text_img, full_refresh=False)
                print("Displayed test pattern and title.")
            except EinkBusyTimeoutError as e:
                write_eink_status("EINK_BUSY_TIMEOUT", detail=str(e))
                print("EINK_BUSY_TIMEOUT", file=sys.stderr)
                return 2
            finally:
                display.release()
    except TimeoutError:
        write_eink_status("SKIPPED_LOCKED", detail="test_eink")
        return 3
    write_eink_status("OK", detail="test_eink")
    return 0


if __name__ == "__main__":
    sys.exit(main())
