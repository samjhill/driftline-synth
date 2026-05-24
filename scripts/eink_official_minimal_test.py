#!/usr/bin/env python3
"""Minimal official Waveshare test: white -> black -> white. No app code.

Self-contained — same path that visibly worked before (vendor/waveshare only).

Usage:
  eink_official_minimal_test.py [epd2in13_V4|epd2in13_V3|epd2in13_V2]

Env:
  EINK_VALIDATE_BUSY=1  — fail if BUSY stuck (validation / direct test)
  (unset)               — production: warn on BUSY timeout, continue (original)
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "vendor" / "waveshare"))
os.environ.setdefault("HOME", "/home/pi")
os.environ.setdefault("GPIOZERO_PIN_FACTORY", "lgpio")

DRIVERS = ("epd2in13_V4", "epd2in13_V3", "epd2in13_V2")
_VALIDATE = os.environ.get("EINK_VALIDATE_BUSY", "").strip().lower() in (
    "1",
    "true",
    "yes",
)


def _patch_read_busy(epd_cls) -> None:
    from waveshare_epd import epdconfig

    def read_busy(self, timeout_sec: float = 20.0) -> None:
        deadline = time.time() + min(timeout_sec, 20.0)
        while epdconfig.digital_read(self.busy_pin) == 1:
            if time.time() >= deadline:
                msg = (
                    f"WARN: BUSY BCM{self.busy_pin} still 1 after {timeout_sec}s"
                )
                if _VALIDATE:
                    print(f"FAIL: {msg}", flush=True)
                    raise RuntimeError(msg)
                print(f"{msg} — continuing", flush=True)
                time.sleep(3.0)
                return
            epdconfig.delay_ms(20)

    epd_cls.ReadBusy = read_busy


def _check_busy_before_init(epd_cls, epdconfig) -> None:
    """Probe BUSY before init — fail in validation if already stuck high."""
    pin = getattr(epd_cls, "busy_pin", None)
    if pin is None:
        return
    try:
        val = epdconfig.digital_read(pin)
    except Exception as exc:
        print(f"WARN: pre-init BUSY read failed: {exc}", flush=True)
        return
    print(f"pre-init BUSY BCM{pin} read={val}", flush=True)
    if _VALIDATE and val == 1:
        raise RuntimeError(f"pre-init BUSY stuck HIGH (BCM{pin}={val})")


def run_driver(module_name: str) -> int:
    print(f"\n========== {module_name} ==========", flush=True)
    try:
        mod = __import__(f"waveshare_epd.{module_name}", fromlist=[module_name])
    except ImportError as e:
        print(f"SKIP: import failed: {e}")
        return 2

    from waveshare_epd import epdconfig

    epdconfig.module_exit()
    _check_busy_before_init(mod.EPD, epdconfig)
    if epdconfig.module_init() != 0:
        print("FAIL: module_init")
        return 1

    _patch_read_busy(mod.EPD)
    epd = mod.EPD()
    print(f"Panel logical size: {epd.width}x{epd.height}")

    print("1. init()")
    try:
        init_rc = epd.init()
    except TypeError:
        init_rc = epd.init(0)
    if init_rc not in (0, None):
        print(f"FAIL: init returned {init_rc}")
        epdconfig.module_exit()
        return 1

    print("2. Clear white (0xFF)")
    epd.Clear(0xFF)
    time.sleep(3)

    print("3. Clear black (0x00) — LOOK AT PANEL (15s)")
    epd.Clear(0x00)
    time.sleep(15)

    print("4. Clear white (0xFF) — LOOK AT PANEL (10s)")
    epd.Clear(0xFF)
    time.sleep(10)

    print("5. sleep()")
    epd.sleep()
    epdconfig.module_exit()
    print(f"OFFICIAL_MINIMAL_{module_name}_DONE")
    print(f"OFFICIAL_SEQUENCE_SENT_TO_PANEL module={module_name}")
    return 0


def main() -> int:
    targets = sys.argv[1:] if len(sys.argv) > 1 else ["epd2in13_V4"]
    rc = 0
    for name in targets:
        if name not in DRIVERS:
            print(f"Unknown driver {name}, skip")
            continue
        try:
            r = run_driver(name)
        except RuntimeError as exc:
            print(f"FAIL: {exc}", flush=True)
            r = 1
        if r != 0:
            rc = r
        time.sleep(2)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
