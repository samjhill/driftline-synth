"""Cross-process reseed request (monitor → MIDI bridge)."""

from __future__ import annotations

import time
from pathlib import Path

DEFAULT_REQUEST_PATH = Path("/var/lib/pi-ambient-synth/reseed.request")


def reseed_request_path(marker_dir: str | Path | None = None) -> Path:
    if marker_dir:
        return Path(marker_dir) / "reseed.request"
    return DEFAULT_REQUEST_PATH


def touch_reseed_request(path: Path | None = None) -> Path:
    p = path or DEFAULT_REQUEST_PATH
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"{time.time():f}\n", encoding="utf-8")
    return p


def consume_reseed_request(path: Path | None = None) -> bool:
    """Return True once per touch; removes the request file."""
    p = path or DEFAULT_REQUEST_PATH
    if not p.is_file():
        return False
    try:
        p.unlink()
    except OSError:
        return False
    return True
