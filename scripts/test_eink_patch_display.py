#!/usr/bin/env python3
"""Deterministic e-ink patch render test (single writer, no note-triggered refresh)."""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config  # noqa: E402
from eink_lock import eink_exclusive_lock  # noqa: E402
from eink_display import EInkDisplay  # noqa: E402


def main() -> int:
    config = load_config()
    eink_cfg = config.get("eink", {})
    if not eink_cfg.get("enabled", True):
        print("SKIP: eink disabled in config")
        return 0

    print("eink_test: acquiring lock (timeout 30s)")
    t0 = time.monotonic()
    try:
        with eink_exclusive_lock(timeout_seconds=30.0):
            print(f"eink_test: lock ok ({time.monotonic() - t0:.1f}s)")
            disp = EInkDisplay(config)
            print("eink_test: init start")
            if not disp.init():
                print("FAIL: e-ink init returned false")
                return 1
            print(f"eink_test: init ok ({time.monotonic() - t0:.1f}s)")
            print("eink_test: render start")
            disp.show_status(
                "patch test",
                "Fog Bank",
                "validate e-ink",
                "seed 4242",
                config=config,
            )
            print(f"eink_test: render end ({time.monotonic() - t0:.1f}s)")
            print("PASS: e-ink patch display updated (no release() after draw)")
            return 0
    except TimeoutError:
        print(f"FAIL: e-ink busy timeout ({time.monotonic() - t0:.1f}s)")
        return 1
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
