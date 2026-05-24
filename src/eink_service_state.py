"""Health snapshot written only by pi-ambient-synth-eink.service."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

SERVICE_STATE_FILE = "eink-service.json"


def state_path() -> Path:
    root = Path(os.environ.get("MARKER_DIR", "/var/lib/pi-ambient-synth"))
    return root / SERVICE_STATE_FILE


def write_service_state(**fields: Any) -> None:
    path = state_path()
    payload: dict[str, Any] = {
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "updated_at_epoch": int(time.time()),
        "service_active": True,
    }
    payload.update(fields)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    except OSError:
        pass


def read_service_state() -> dict[str, Any] | None:
    path = state_path()
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def mark_inactive() -> None:
    prev = read_service_state() or {}
    write_service_state(
        service_active=False,
        last_error=prev.get("last_error", ""),
        last_ok_at=prev.get("last_ok_at"),
        panel_sleeping=True,
    )
