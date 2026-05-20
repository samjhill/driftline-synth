"""Waveshare 2.13\" E-Ink HAT V4 driver with graceful fallback."""

from __future__ import annotations

import logging
from typing import Any

from PIL import Image

from patch_model import Patch

logger = logging.getLogger(__name__)

_WAVESHARE_AVAILABLE = False
_epd_module = None

try:
    from waveshare_epd import epd2in13_V4

    _epd_module = epd2in13_V4
    _WAVESHARE_AVAILABLE = True
except ImportError:
    try:
        import sys
        from pathlib import Path

        vendor = Path(__file__).resolve().parent.parent / "vendor" / "waveshare"
        if vendor.exists():
            sys.path.insert(0, str(vendor))
            from waveshare_epd import epd2in13_V4

            _epd_module = epd2in13_V4
            _WAVESHARE_AVAILABLE = True
    except ImportError:
        pass


class EInkDisplay:
    def __init__(self, config: dict[str, Any]):
        eink = config.get("eink", {})
        self.enabled = eink.get("enabled", True)
        self.width = eink.get("width", 250)
        self.height = eink.get("height", 122)
        self.rotate = eink.get("rotate", 0)
        self.partial_refresh = eink.get("partial_refresh", False)
        self._epd = None
        self._available = False

    def init(self) -> bool:
        if not self.enabled:
            logger.info("E-ink disabled in config")
            return False
        if not _WAVESHARE_AVAILABLE or _epd_module is None:
            logger.warning(
                "Waveshare driver not available — display will use stub mode"
            )
            self._available = False
            return False
        try:
            self._epd = _epd_module.EPD()
            self._epd.init()
            self._available = True
            logger.info("E-ink display initialized (2.13\" V4)")
            return True
        except Exception as e:
            logger.warning("E-ink init failed: %s", e)
            self._available = False
            return False

    @property
    def available(self) -> bool:
        return self._available and self._epd is not None

    def _prepare_image(self, image: Image.Image) -> Image.Image:
        if image.mode != "1":
            image = image.convert("1")
        if image.size != (self.width, self.height):
            image = image.resize((self.width, self.height), Image.Resampling.LANCZOS)
        if self.rotate:
            image = image.rotate(self.rotate, expand=True)
        return image

    def show_image(self, image: Image.Image) -> None:
        image = self._prepare_image(image)
        if not self.available:
            logger.debug("E-ink stub: would show %dx%d image", image.width, image.height)
            return
        buf = self._epd.getbuffer(image)
        if self.partial_refresh and hasattr(self._epd, "displayPartial"):
            self._epd.displayPartial(buf)
        else:
            self._epd.display(buf)

    def show_patch(self, patch: Patch, image: Image.Image) -> None:
        self.show_image(image)
        logger.info("Display updated: %s", patch.summary())

    def clear(self) -> None:
        if self.available:
            self._epd.Clear(0xFF)
        logger.info("E-ink cleared")

    def sleep(self) -> None:
        if self.available:
            self._epd.sleep()
            logger.info("E-ink sleep")
