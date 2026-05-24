#!/usr/bin/env python3
"""E-ink progress — canonical src/eink_official_driver only."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from eink_official_driver import firstboot_post, progress_two_lines  # noqa: E402


def main() -> int:
    phase = (sys.argv[1] if len(sys.argv) > 1 else "BOOT").upper().replace(" ", "_")
    detail = " ".join(sys.argv[2:])[:28] if len(sys.argv) > 2 else ""

    if phase == "BOOT":
        return firstboot_post(root=ROOT)
    if phase in ("WIFI_FAILED",):
        return progress_two_lines("NO WIFI", detail or "TRY SSH", root=ROOT)
    if phase == "SSH_READY":
        return progress_two_lines("SSH OK", detail, root=ROOT)
    if phase.startswith("INSTALL"):
        return progress_two_lines("INSTALL", detail or "...", root=ROOT)
    if phase == "AUDIO_READY":
        return progress_two_lines("AUDIO OK", "", root=ROOT)
    if phase == "ERROR":
        return progress_two_lines("ERROR", detail[:12], root=ROOT)
    return progress_two_lines(phase[:10], detail, root=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
