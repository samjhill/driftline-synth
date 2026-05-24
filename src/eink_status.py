"""Persist e-ink outcome for monitor and debugging (never blocks audio)."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

# Human-readable one-liner (legacy monitor reads this file).
STATUS_LINE_FILE = "last_eink_status"
# Structured JSON for monitor API/HTML.
STATUS_JSON_FILE = "eink-status.json"

STATUSES = frozenset(
    {
        "OK",
        "SKIPPED_LOCKED",
        "EINK_BUSY_TIMEOUT",
        "GPIO_UNAVAILABLE",
        "INIT_FAILED",
        "DISABLED",
        "ERROR",
    }
)


def marker_dir() -> Path:
    return Path(
        os.environ.get("MARKER_DIR", "/var/lib/pi-ambient-synth")
    )


def write_eink_status(
    status: str,
    *,
    detail: str = "",
    patch_summary: str = "",
) -> None:
    """Record last e-ink attempt (short-lived jobs call this on exit)."""
    st = status if status in STATUSES else "ERROR"
    now = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{now} {st}"
    if detail:
        line += f" — {detail}"
    root = marker_dir()
    try:
        root.mkdir(parents=True, exist_ok=True)
        (root / STATUS_LINE_FILE).write_text(line + "\n", encoding="utf-8")
        payload: dict[str, Any] = {
            "updated_at": now,
            "updated_at_epoch": int(time.time()),
            "status": st,
            "detail": detail,
            "patch_summary": patch_summary,
        }
        (root / STATUS_JSON_FILE).write_text(
            json.dumps(payload, indent=2) + "\n",
            encoding="utf-8",
        )
    except OSError:
        pass


def read_eink_status() -> dict[str, Any] | None:
    path = marker_dir() / STATUS_JSON_FILE
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
