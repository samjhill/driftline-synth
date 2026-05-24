"""Canonical Waveshare e-ink — exact init/display from eink_official_minimal_test.

All production display paths must use this module only.
"""
from __future__ import annotations

import logging
import os
import sys
import time
from pathlib import Path
from typing import Any

log = logging.getLogger("eink_official")

DEFAULT_MODULE = "epd2in13_V4"
DRIVERS = ("epd2in13_V4", "epd2in13_V3", "epd2in13_V2")


def repo_root(start: Path | None = None) -> Path:
    if start is not None:
        return start.resolve()
    here = Path(__file__).resolve().parent.parent
    for base in (here, Path("/boot/firmware/pi-ambient-synth"), Path("/boot/pi-ambient-synth")):
        if (base / "vendor" / "waveshare").is_dir():
            return base
    return here


def vendor_path(root: Path | None = None) -> Path:
    r = repo_root(root)
    return r / "vendor" / "waveshare"


def _env_setup(root: Path | None = None) -> Path:
    v = vendor_path(root)
    if v.is_dir():
        p = str(v.resolve())
        if p not in sys.path:
            sys.path.insert(0, p)
    os.environ.setdefault("HOME", "/home/pi")
    os.environ.setdefault("GPIOZERO_PIN_FACTORY", "lgpio")
    return v


def patch_read_busy(epd_cls: type) -> None:
    """Same BUSY patch as scripts/eink_official_minimal_test.py."""
    from waveshare_epd import epdconfig

    def read_busy(self, timeout_sec: float = 20.0) -> None:
        deadline = time.time() + min(timeout_sec, 20.0)
        while epdconfig.digital_read(self.busy_pin) == 1:
            if time.time() >= deadline:
                log.warning(
                    "BUSY BCM%s still 1 after %.0fs — continuing (+3s)",
                    self.busy_pin,
                    timeout_sec,
                )
                time.sleep(3.0)
                return
            epdconfig.delay_ms(20)

    epd_cls.ReadBusy = read_busy


def log_busy(epd: Any, label: str) -> None:
    from waveshare_epd import epdconfig

    try:
        val = epdconfig.digital_read(epd.busy_pin)
        log.info("BUSY pin=%s read=%s (%s)", epd.busy_pin, val, label)
    except Exception as exc:
        log.warning("BUSY read failed (%s): %s", label, exc)


def open_epd(
    module_name: str = DEFAULT_MODULE,
    *,
    root: Path | None = None,
) -> tuple[Any, Any, str]:
    """Official sequence: module_exit → module_init → patch → EPD → init()."""
    _env_setup(root)
    log.info("driver_module=%s init_path=eink_official_driver.open_epd", module_name)
    try:
        mod = __import__(f"waveshare_epd.{module_name}", fromlist=[module_name])
    except ImportError as exc:
        raise RuntimeError(f"import {module_name} failed: {exc}") from exc

    from waveshare_epd import epdconfig

    epdconfig.module_exit()
    if epdconfig.module_init() != 0:
        raise RuntimeError("module_init failed")

    patch_read_busy(mod.EPD)
    epd = mod.EPD()
    log.info("panel_size=%sx%s", epd.width, epd.height)
    log_busy(epd, "after module_init")

    try:
        init_rc = epd.init()
    except TypeError:
        init_rc = epd.init(0)
    if init_rc not in (0, None):
        epdconfig.module_exit()
        raise RuntimeError(f"init returned {init_rc}")

    log.info("official init() ok module=%s", module_name)
    log_busy(epd, "after init()")
    return epd, epdconfig, module_name


def clear_hold(epd: Any, value: int, hold_sec: float, label: str) -> None:
    log.info("official Clear(0x%02X) %s hold %.0fs", value, label, hold_sec)
    epd.Clear(value)
    log_busy(epd, f"after Clear {label}")
    time.sleep(hold_sec)


def display_text_official(
    epd: Any,
    line1: str,
    line2: str,
    *,
    hold_sec: float = 15.0,
) -> None:
    """Waveshare V4 demo style: PIL Image + epd.display(getbuffer)."""
    try:
        from PIL import Image, ImageDraw
    except ImportError as exc:
        log.error("PIL missing for text (%s) — hold black %.0fs", exc, hold_sec)
        clear_hold(epd, 0x00, hold_sec, "text-fallback-black")
        return

    image = Image.new("1", (epd.height, epd.width), 255)
    draw = ImageDraw.Draw(image)
    draw.rectangle([(0, 0), (epd.height - 1, epd.width - 1)], fill=255)
    draw.text((8, 24), line1[:16].upper(), fill=0)
    draw.text((8, 64), line2[:16].upper(), fill=0)
    log.info("official epd.display text %r / %r hold %.0fs", line1, line2, hold_sec)
    epd.display(epd.getbuffer(image))
    log_busy(epd, "after display text")
    time.sleep(hold_sec)


def close_epd(epd: Any, epdconfig: Any, *, sleep_panel: bool = False) -> None:
    if sleep_panel:
        try:
            epd.sleep()
        except Exception:
            pass
    epdconfig.module_exit()
    log.info("official module_exit done")


def _try_bootstrap_pil(root: Path | None) -> None:
    try:
        from PIL import Image  # noqa: F401
        return
    except ImportError:
        pass
    wheels = repo_root(root) / "vendor" / "wheels"
    if not wheels.is_dir():
        return
    import subprocess

    for pattern in ("pillow*.whl", "Pillow*.whl"):
        for whl in sorted(wheels.glob(pattern)):
            log.info("installing PIL from bundled wheel %s", whl.name)
            subprocess.run(
                [sys.executable, "-m", "pip", "install", "-q", str(whl)],
                check=False,
                timeout=180,
            )
            try:
                from PIL import Image  # noqa: F401
                log.info("PIL available after wheel install")
                return
            except ImportError:
                continue


def firstboot_post(
    *,
    root: Path | None = None,
    module_name: str = DEFAULT_MODULE,
) -> int:
    """firstboot-light POST: black 5s, white 2s, DRIFTLINE BOOTING 15s."""
    log.info("firstboot_post start module=%s", module_name)
    if not Path("/dev/spidev0.0").exists():
        log.error("SPI missing: /dev/spidev0.0")
        return 1

    _try_bootstrap_pil(root)
    epd, epdconfig, mod = open_epd(module_name, root=root)
    try:
        clear_hold(epd, 0x00, 5.0, "POST-black")
        clear_hold(epd, 0xFF, 2.0, "POST-white")
        display_text_official(epd, "DRIFTLINE", "BOOTING", hold_sec=15.0)
        log.info("OFFICIAL_SEQUENCE_SENT_TO_PANEL module=%s phase=firstboot_post", mod)
        return 0
    except Exception:
        log.exception("firstboot_post failed")
        return 1
    finally:
        close_epd(epd, epdconfig, sleep_panel=False)


def progress_two_lines(
    line1: str,
    line2: str = "",
    *,
    root: Path | None = None,
    module_name: str = DEFAULT_MODULE,
    hold_sec: float = 2.0,
) -> int:
    """Install/heavy status — official init + PIL display only."""
    try:
        epd, epdconfig, mod = open_epd(module_name, root=root)
        try:
            display_text_official(epd, line1, line2, hold_sec=hold_sec)
            log.info("OFFICIAL_SEQUENCE_SENT_TO_PANEL module=%s phase=progress", mod)
            return 0
        finally:
            close_epd(epd, epdconfig, sleep_panel=False)
    except Exception:
        log.exception("progress_two_lines failed")
        return 1


def minimal_white_black_white(
    module_name: str = DEFAULT_MODULE,
    *,
    root: Path | None = None,
) -> int:
    """Exact eink_official_minimal_test.run_driver sequence."""
    log.info("minimal_test start module=%s", module_name)
    epd, epdconfig, mod = open_epd(module_name, root=root)
    try:
        clear_hold(epd, 0xFF, 3.0, "minimal-white")
        clear_hold(epd, 0x00, 15.0, "minimal-black")
        clear_hold(epd, 0xFF, 10.0, "minimal-white-end")
        epd.sleep()
        log.info("OFFICIAL_SEQUENCE_SENT_TO_PANEL module=%s phase=minimal_test", mod)
        print(f"OFFICIAL_MINIMAL_{module_name}_DONE")
        return 0
    except Exception:
        log.exception("minimal_white_black_white failed")
        return 1
    finally:
        close_epd(epd, epdconfig, sleep_panel=False)
