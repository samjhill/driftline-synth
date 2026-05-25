"""Enqueue e-ink updates via status PNG (ingest-style; pi_eink_waveshare213v4 watches mtime)."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

DEFAULT_QUEUE_DIR = Path("/run/pi-ambient-synth/eink-queue")


def queue_dir() -> Path:
    raw = os.environ.get("EINK_QUEUE_DIR", "").strip()
    return Path(raw) if raw else DEFAULT_QUEUE_DIR


def _write_png_from_config(fn, *args, **kwargs) -> Path | None:
    try:
        from config_loader import load_config

        return fn(load_config(), *args, **kwargs)
    except Exception:
        return None


def enqueue(payload: dict[str, Any]) -> Path | None:
    """Legacy queue API — maps to PNG write for ingest-style e-ink service."""
    ptype = payload.get("type")
    if ptype == "patch":
        return enqueue_patch(
            name=str(payload.get("name") or ""),
            subtitle=str(payload.get("subtitle") or ""),
            detail=str(payload.get("detail") or ""),
            from_state=bool(payload.get("from_state")),
        )
    if ptype == "status":
        from eink_status_png import write_status_png
        from config_loader import load_config

        return write_status_png(
            load_config(),
            phase=str(payload.get("phase") or "idle"),
            title=str(payload.get("title") or ""),
            subtitle=str(payload.get("subtitle") or ""),
            detail=str(payload.get("detail") or ""),
        )
    if ptype == "startup":
        return enqueue_status("boot", "Pi Ambient Synth", "Ready", "")
    return None


def enqueue_startup() -> Path | None:
    return enqueue_status("boot", "Pi Ambient Synth", "Ready", "")


def enqueue_status(
    phase: str,
    title: str,
    subtitle: str = "",
    detail: str = "",
) -> Path | None:
    from eink_status_png import write_status_png
    from config_loader import load_config

    return write_status_png(
        load_config(),
        phase=phase,
        title=title,
        subtitle=subtitle,
        detail=detail,
    )


def enqueue_patch(
    *,
    name: str = "",
    subtitle: str = "",
    detail: str = "",
    from_state: bool = False,
) -> Path | None:
    from eink_status_png import write_patch_png

    return _write_png_from_config(
        write_patch_png,
        name=name,
        subtitle=subtitle,
        detail=detail,
        from_state=from_state,
    )


def queue_depth() -> int:
    try:
        return len(list(queue_dir().glob("*.json")))
    except OSError:
        return 0


def pending_messages() -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    try:
        paths = sorted(queue_dir().glob("*.json"), key=lambda p: p.name)
    except OSError:
        return out
    for path in paths:
        try:
            out.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            continue
    return out
