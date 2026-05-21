"""Waveshare 2.13\" E-Ink HAT V4 driver with graceful fallback."""

from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any

from PIL import Image

from patch_model import Patch

logger = logging.getLogger(__name__)

_WAVESHARE_AVAILABLE = False
_epd_module = None
_EPD_CLASS_NAMES = ("epd2in13_V4", "epd2in13_V3", "epd2in13")


def _vendor_waveshare_path() -> Path:
    return Path(__file__).resolve().parent.parent / "vendor" / "waveshare"


def _purge_waveshare_modules() -> None:
    import sys

    vendor_root = str(_vendor_waveshare_path().resolve())
    for key in list(sys.modules):
        if not key.startswith("waveshare_epd"):
            continue
        mod = sys.modules.get(key)
        mod_file = getattr(mod, "__file__", "") or ""
        if mod_file and vendor_root not in mod_file:
            del sys.modules[key]


def _load_epd_modules() -> None:
    global _WAVESHARE_AVAILABLE, _epd_module
    import sys

    vendor = _vendor_waveshare_path()
    if vendor.is_dir():
        vendor_str = str(vendor)
        if vendor_str not in sys.path:
            sys.path.insert(0, vendor_str)
        _purge_waveshare_modules()

    last_error: BaseException | None = None
    for name in _EPD_CLASS_NAMES:
        try:
            mod = __import__(f"waveshare_epd.{name}", fromlist=[name])
            # Waveshare e-Paper drivers expose the panel class as EPD, not epd2in13_V4.
            if not hasattr(mod, "EPD"):
                raise AttributeError(
                    f"module 'waveshare_epd.{name}' has no EPD class"
                )
            _epd_module = mod
            _WAVESHARE_AVAILABLE = True
            mod_file = getattr(mod, "__file__", "")
            logger.debug("Using Waveshare driver %s (%s)", name, mod_file)
            return
        except (ImportError, AttributeError, OSError) as e:
            last_error = e
            logger.debug("Waveshare driver %s unavailable: %s", name, e)
            continue
    _WAVESHARE_AVAILABLE = False
    _epd_module = None
    if last_error is not None:
        vendor = _vendor_waveshare_path()
        hint = (
            f"vendor missing at {vendor}"
            if not vendor.is_dir()
            else "run scripts/ensure_waveshare_vendor.sh"
        )
        logger.warning("Waveshare driver load failed (%s); %s", last_error, hint)


class EInkDisplay:
    def __init__(self, config: dict[str, Any]):
        eink = config.get("eink", {})
        self.enabled = eink.get("enabled", True)
        self.width = eink.get("width", 250)
        self.height = eink.get("height", 122)
        self.rotate = eink.get("rotate", 0)
        self.partial_refresh = eink.get("partial_refresh", False)
        self.full_refresh_boot = eink.get("full_refresh_boot", True)
        self._epd = None
        self._available = False
        self._driver_name = ""
        self._frame_count = 0

    def init(self) -> bool:
        if not self.enabled:
            logger.info("E-ink disabled in config")
            return False
        if not _WAVESHARE_AVAILABLE or _epd_module is None:
            _load_epd_modules()
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
            self._driver_name = getattr(_epd_module, "__name__", "waveshare")
            logger.info("E-ink display initialized (%s)", self._driver_name)
            return True
        except Exception as e:
            logger.warning("E-ink init failed: %s", e)
            self._available = False
            return False

    @property
    def available(self) -> bool:
        return self._available and self._epd is not None

    def _purge_panel(self) -> None:
        """Full refresh (white → black → white) to clear ghosting from old images."""
        if not self._epd:
            return
        try:
            self._epd.init()
            self._epd.Clear(0xFF)
            time.sleep(0.1)
            self._epd.Clear(0x00)
            time.sleep(0.1)
            self._epd.Clear(0xFF)
            logger.info("E-ink full purge (ghost clear)")
        except Exception as e:
            logger.warning("E-ink purge failed: %s", e)

    def _prepare_image(self, image: Image.Image) -> Image.Image:
        if image.mode != "1":
            image = image.convert("1")
        if image.size != (self.width, self.height):
            image = image.resize((self.width, self.height), Image.Resampling.LANCZOS)
        if self.rotate:
            image = image.rotate(self.rotate, expand=True)
        return image

    def show_image(self, image: Image.Image, *, full_refresh: bool = False) -> None:
        image = self._prepare_image(image)
        if not self.available:
            logger.warning("E-ink stub: display not initialized — image not shown")
            return
        import os

        use_full = (
            full_refresh
            or os.environ.get("EINK_FORCE") == "1"
            or (self.full_refresh_boot and self._frame_count == 0)
        )
        if use_full:
            self._purge_panel()
        buf = self._epd.getbuffer(image)
        if self.partial_refresh and hasattr(self._epd, "displayPartial"):
            self._epd.displayPartial(buf)
        else:
            self._epd.display(buf)
        self._frame_count += 1

    def show_patch(self, patch: Patch, image: Image.Image) -> None:
        self.show_image(image)
        logger.info("Display updated: %s", patch.summary())

    def show_status(
        self,
        phase: str,
        title: str,
        subtitle: str = "",
        detail: str = "",
    ) -> None:
        from status_display import StatusDisplay

        renderer = StatusDisplay(
            {"eink": {"width": self.width, "height": self.height}}
        )
        self.show_image(renderer.render(phase, title, subtitle, detail))
        logger.info("Status display: %s — %s", phase, title)

    def clear(self) -> None:
        if self.available:
            self._epd.Clear(0xFF)
        logger.info("E-ink cleared")

    def release(self) -> None:
        """Deep-sleep panel and free GPIO/SPI for other tools."""
        if not self._epd:
            return
        try:
            self._epd.sleep()
        except Exception as e:
            logger.warning("E-ink sleep failed: %s", e)
        try:
            from waveshare_epd import epdconfig

            epdconfig.release_implementation()
        except Exception as e:
            logger.warning("E-ink GPIO release failed: %s", e)
        self._epd = None
        self._available = False
        logger.info("E-ink released")

    def sleep(self) -> None:
        self.release()
