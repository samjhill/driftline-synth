#!/usr/bin/env python3
"""Minimal Waveshare epd2in13_V4 test (matches their epd_2in13_V4_test.py layout).

User must see: white → black → labeled shapes. Does not touch synth audio.
"""
from __future__ import annotations

import logging
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "vendor" / "waveshare"
sys.path.insert(0, str(VENDOR))
os.environ.setdefault("GPIOZERO_PIN_FACTORY", "lgpio")
os.environ.setdefault("HOME", "/home/pi")

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("eink_official_v4")


def _patch_read_busy(epd_cls) -> None:
    """Stuck BUSY HIGH on some HAT rev 2.1: wait briefly, then fixed pause."""
    from waveshare_epd import epdconfig

    def read_busy(self, timeout_sec: float = 3.0) -> None:
        deadline = time.time() + timeout_sec
        while epdconfig.digital_read(self.busy_pin) == 1:
            if time.time() >= deadline:
                logger.warning(
                    "BUSY still HIGH after %.0fs — continuing (+2s)", timeout_sec
                )
                time.sleep(2.0)
                return
            epdconfig.delay_ms(20)

    epd_cls.ReadBusy = read_busy


def main() -> int:
    use_dev = os.environ.get("EINK_USE_DEV_SO", "").strip().lower() in (
        "1",
        "true",
        "yes",
    )
    from waveshare_epd import epd2in13_V4, epdconfig

    if use_dev:
        logger.info("Using DEV_Config.so SPI path")
        epdconfig.module_init(cleanup=True)
    else:
        epdconfig.module_init()

    _patch_read_busy(epd2in13_V4.EPD)
    epd = epd2in13_V4.EPD()
    logger.info("Panel %sx%s — init + clear white", epd.width, epd.height)
    epd.init()
    epd.Clear(0xFF)
    time.sleep(3)
    logger.info("Clear BLACK — full screen should go dark")
    epd.Clear(0x00)
    time.sleep(5)

    from PIL import Image, ImageDraw

    image = Image.new("1", (epd.height, epd.width), 255)
    draw = ImageDraw.Draw(image)
    draw.rectangle([(0, 0), (epd.height - 1, 50)], fill=0)
    draw.text((10, 70), "Waveshare V4", fill=0)
    draw.text((10, 100), "HAT rev 2.1", fill=0)
    logger.info("Display bar + text")
    epd.display(epd.getbuffer(image))
    time.sleep(5)
    epd.init()
    epd.Clear(0xFF)
    time.sleep(2)
    epd.sleep()
    if use_dev:
        epdconfig.module_exit(cleanup=True)
    else:
        epdconfig.module_exit()
    print("OFFICIAL_V4_TEST_DONE — did the panel change?")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        logger.exception("Official V4 test failed: %s", exc)
        raise SystemExit(1) from exc
