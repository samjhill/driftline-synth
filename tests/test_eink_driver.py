"""Waveshare vendor driver import (no hardware required)."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "vendor" / "waveshare"


def test_vendor_epd2in13_v4_has_epd_class():
    assert VENDOR.is_dir(), "vendor/waveshare missing — run scripts/ensure_waveshare_vendor.sh"
    vendor_str = str(VENDOR)
    if vendor_str not in sys.path:
        sys.path.insert(0, vendor_str)
    mod = __import__("waveshare_epd.epd2in13_V4", fromlist=["epd2in13_V4"])
    assert hasattr(mod, "EPD")
    assert mod.EPD.__name__ == "EPD"

