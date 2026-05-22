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
        vendor_str = str(vendor.resolve())
        # Prefer bundled driver over GhostRoll / apt copies in /usr/local.
        sys.path = [p for p in sys.path if "/dist-packages/waveshare_epd" not in p]
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
        self._eink_cfg = eink
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

    def _bind_read_busy(self, epd: Any, *, active_high: bool) -> None:
        """Patch vendor ReadBusy: timeout instead of hard fail (stuck busy pin)."""
        from waveshare_epd import epdconfig

        busy_pin = epd.busy_pin
        busy_level = 1 if active_high else 0
        timeout = float(self._eink_cfg.get("busy_timeout_seconds", 25))

        def read_busy(timeout_sec: float = timeout) -> None:
            deadline = time.time() + timeout_sec
            while epdconfig.digital_read(busy_pin) == busy_level:
                if time.time() >= deadline:
                    logger.warning(
                        "e-Paper busy pin did not clear within %.0fs; proceeding",
                        timeout_sec,
                    )
                    return
                epdconfig.delay_ms(10)

        epd.ReadBusy = read_busy

    @staticmethod
    def _prepare_gpio_env() -> None:
        import os

        home = os.environ.get("HOME") or "/home/pi"
        os.environ["HOME"] = home
        os.environ.setdefault("GPIOZERO_PIN_FACTORY", "lgpio")
        try:
            os.chdir(home)
        except OSError:
            pass
        for directory in (home, os.getcwd()):
            try:
                for name in os.listdir(directory):
                    if name.startswith(".lgd-"):
                        try:
                            os.remove(os.path.join(directory, name))
                        except OSError:
                            pass
            except OSError:
                pass

    def init(self) -> bool:
        if not self.enabled:
            logger.info("E-ink disabled in config")
            return False
        self._prepare_gpio_env()
        self._release_gpio_only()
        if not _WAVESHARE_AVAILABLE or _epd_module is None:
            _load_epd_modules()
        if not _WAVESHARE_AVAILABLE or _epd_module is None:
            logger.warning(
                "Waveshare driver not available — display will use stub mode"
            )
            self._available = False
            return False
        polarities = (True, False)
        cfg_high = self._eink_cfg.get("busy_active_high")
        if cfg_high is True:
            polarities = (True,)
        elif cfg_high is False:
            polarities = (False,)

        last_error: BaseException | None = None
        for attempt, active_high in enumerate(polarities, start=1):
            try:
                self._release_gpio_only()
                self._epd = _epd_module.EPD()
                self._bind_read_busy(self._epd, active_high=active_high)
                self._epd.init()
                self._available = True
                self._driver_name = getattr(_epd_module, "__name__", "waveshare")
                logger.info(
                    "E-ink display initialized (%s, busy_active_high=%s)",
                    self._driver_name,
                    active_high,
                )
                return True
            except Exception as e:
                last_error = e
                logger.warning(
                    "E-ink init attempt %s failed (busy_active_high=%s): %s",
                    attempt,
                    active_high,
                    e,
                )
                self._force_release()
        if last_error is not None:
            logger.warning("E-ink init failed: %s", last_error)
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

        use_full = full_refresh or (
            self.full_refresh_boot and self._frame_count == 0
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
        *,
        config: dict[str, Any] | None = None,
        battery=None,
    ) -> None:
        from status_display import StatusDisplay

        if not self.available and not self.init():
            return

        if battery is None and config is not None:
            from pisugar_battery import read_battery_snapshot

            if config.get("pisugar", {}).get("show_on_display", True):
                battery = read_battery_snapshot(config)

        renderer = StatusDisplay(
            {"eink": {"width": self.width, "height": self.height}}
        )
        self.show_image(
            renderer.render(phase, title, subtitle, detail, battery=battery)
        )
        logger.info("Status display: %s — %s", phase, title)

    def clear(self) -> None:
        if self.available:
            self._epd.Clear(0xFF)
        logger.info("E-ink cleared")

    def _release_gpio_only(self) -> None:
        try:
            from waveshare_epd import epdconfig

            epdconfig.release_implementation()
        except Exception as e:
            logger.debug("E-ink GPIO release: %s", e)

    def _force_release(self) -> None:
        """Release panel and GPIO after a failed init (EPD() may have claimed pins)."""
        if self._epd:
            try:
                self._epd.sleep()
            except Exception as e:
                logger.debug("E-ink sleep after failed init: %s", e)
        self._release_gpio_only()
        self._epd = None
        self._available = False

    def release(self) -> None:
        """Deep-sleep panel and free GPIO/SPI for other tools."""
        self._force_release()
        logger.info("E-ink released")

    def sleep(self) -> None:
        self.release()
