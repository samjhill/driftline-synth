#!/usr/bin/env python3
"""Test Waveshare 2.13\" e-ink display."""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config
from eink_display import EInkDisplay
from logging_setup import setup_logging
from PIL import Image, ImageDraw, ImageFont

setup_logging("INFO")


def main() -> int:
    config = load_config()
    display = EInkDisplay(config)
    ok = display.init()
    if not ok:
        print("Display not available (stub mode). Install Waveshare driver on Pi.")
    w, h = display.width, display.height
    pattern = Image.new("1", (w, h), 1)
    draw = ImageDraw.Draw(pattern)
    for y in range(0, h, 8):
        draw.line([(0, y), (w, y)], fill=0 if (y // 8) % 2 else 1)
    display.show_image(pattern)
    time.sleep(3)
    text_img = Image.new("1", (w, h), 1)
    draw = ImageDraw.Draw(text_img)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    draw.text((10, h // 2 - 8), "Pi Ambient Synth", fill=0, font=font)
    display.show_image(text_img)
    print("Displayed test pattern and title. Sleeping in 5s...")
    time.sleep(5)
    display.sleep()
    return 0


if __name__ == "__main__":
    sys.exit(main())
