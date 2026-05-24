#!/usr/bin/env python3
"""Raw GPIO/SPI report for Waveshare HAT — no display init, no app code."""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "vendor" / "waveshare"
sys.path.insert(0, str(VENDOR))
os.environ.setdefault("HOME", "/home/pi")
os.environ.setdefault("GPIOZERO_PIN_FACTORY", "lgpio")


def main() -> int:
    from waveshare_epd import epdconfig

    impl = epdconfig._get_implementation()
    pins = {
        "RST_PIN": impl.RST_PIN,
        "DC_PIN": impl.DC_PIN,
        "CS_PIN": impl.CS_PIN,
        "BUSY_PIN": impl.BUSY_PIN,
        "PWR_PIN": impl.PWR_PIN,
        "MOSI_PIN": impl.MOSI_PIN,
        "SCLK_PIN": impl.SCLK_PIN,
    }
    print("=== waveshare_epd pin map (installed driver) ===")
    for k, v in pins.items():
        print(f"  {k} = BCM {v}")
    print(f"GPIOZERO_PIN_FACTORY={os.environ.get('GPIOZERO_PIN_FACTORY', '')}")
    print(f"implementation={type(impl).__name__}")
    print(f"use_lgpio={getattr(impl, '_use_lgpio', False)}")

    print("\n=== module_init (GPIO only, no EPD.init) ===")
    if epdconfig.module_init() != 0:
        print("module_init failed")
        return 1

    def read_busy() -> int:
        return epdconfig.digital_read(impl.BUSY_PIN)

    def toggle_report(label: str, pin: int) -> None:
        before = epdconfig.digital_read(pin) if pin == impl.BUSY_PIN else None
        if pin != impl.BUSY_PIN:
            epdconfig.digital_write(pin, 1)
            high = epdconfig.digital_read(pin) if pin == impl.BUSY_PIN else "n/a"
            epdconfig.digital_write(pin, 0)
            low = epdconfig.digital_read(pin) if pin == impl.BUSY_PIN else "n/a"
            epdconfig.digital_write(pin, 1)
            print(
                f"  {label} BCM{pin}: drive 1/0/1 "
                f"(read only implemented for BUSY; toggled via digital_write)"
            )
        else:
            print(f"  {label} BCM{pin}: read-only, before={before}")

    print("\n=== RST toggle (via digital_write) ===")
    r_before = read_busy()
    epdconfig.digital_write(impl.RST_PIN, 1)
    time.sleep(0.05)
    epdconfig.digital_write(impl.RST_PIN, 0)
    time.sleep(0.05)
    epdconfig.digital_write(impl.RST_PIN, 1)
    time.sleep(0.05)
    r_after = read_busy()
    print(f"  BUSY during RST wiggle: before={r_before} after={r_after}")

    print("\n=== DC toggle ===")
    epdconfig.digital_write(impl.DC_PIN, 0)
    time.sleep(0.02)
    epdconfig.digital_write(impl.DC_PIN, 1)
    time.sleep(0.02)
    print("  DC toggled 0 -> 1")

    print("\n=== BUSY read-only 10s (1 sample/s) ===")
    samples = []
    for i in range(10):
        v = read_busy()
        samples.append(v)
        print(f"  t={i}s BUSY BCM{impl.BUSY_PIN} = {v}")
        time.sleep(1)
    print(f"  BUSY summary: min={min(samples)} max={max(samples)} unique={set(samples)}")

    print("\n=== SPI ===")
    for dev in ("/dev/spidev0.0", "/dev/spidev0.1"):
        print(f"  {dev}: {'exists' if Path(dev).exists() else 'MISSING'}")
    try:
        impl.SPI.open(0, 0)
        impl.SPI.max_speed_hz = 4_000_000
        impl.SPI.mode = 0b00
        rx = impl.SPI.writebytes([0x12])
        print(f"  spidev writebytes([0x12]) ok, return={rx}")
        impl.SPI.close()
    except Exception as e:
        print(f"  spidev error: {e}")

    epdconfig.module_exit()
    print("\nEINK_GPIO_RAW_REPORT_DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
