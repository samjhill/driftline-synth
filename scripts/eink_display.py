#!/usr/bin/env python3
"""CLI for canonical Waveshare display (src/eink_official_driver.py only)."""
from __future__ import annotations

import logging
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

logging.basicConfig(level=logging.INFO, format="%(message)s")

from eink_official_driver import (  # noqa: E402
    firstboot_post,
    minimal_white_black_white,
    progress_two_lines,
)


def main() -> int:
    cmd = (sys.argv[1] if len(sys.argv) > 1 else "").lower()
    if cmd in ("firstboot-post", "post", "firstboot_post"):
        return firstboot_post(root=ROOT)
    if cmd == "minimal":
        mod = sys.argv[2] if len(sys.argv) > 2 else "epd2in13_V4"
        return minimal_white_black_white(mod, root=ROOT)
    if cmd == "progress":
        l1 = sys.argv[2] if len(sys.argv) > 2 else "OK"
        l2 = sys.argv[3] if len(sys.argv) > 3 else ""
        return progress_two_lines(l1, l2, root=ROOT)
    if cmd in ("install-failed", "fail"):
        return progress_two_lines("INSTALL", "FAILED", root=ROOT)
    if cmd in ("ssh-ready", "ssh"):
        ip = sys.argv[2] if len(sys.argv) > 2 else ""
        return progress_two_lines("SSH OK", ip[:12], root=ROOT)
    if cmd in ("wifi-failed",):
        hint = " ".join(sys.argv[2:])[:12] if len(sys.argv) > 2 else "TRY SSH"
        return progress_two_lines("NO WIFI", hint, root=ROOT)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
