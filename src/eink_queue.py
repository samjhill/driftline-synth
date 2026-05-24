"""Enqueue e-ink updates for pi-ambient-synth-eink.service (never touch GPIO/SPI here)."""

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


def _ensure_queue_dir() -> Path:
    d = queue_dir()
    d.mkdir(parents=True, exist_ok=True)
    return d


def enqueue(payload: dict[str, Any]) -> Path | None:
    """Append one command for the e-ink service. Returns path or None on failure."""
    if not payload.get("type"):
        return None
    body = dict(payload)
    body.setdefault("enqueued_at", time.time())
    d = _ensure_queue_dir()
    path = d / f"{time.time_ns()}.json"
    tmp = path.with_suffix(".tmp")
    try:
        tmp.write_text(json.dumps(body) + "\n", encoding="utf-8")
        tmp.rename(path)
        return path
    except OSError:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        return None


def enqueue_startup() -> Path | None:
    return enqueue({"type": "startup"})


def enqueue_status(
    phase: str,
    title: str,
    subtitle: str = "",
    detail: str = "",
) -> Path | None:
    return enqueue(
        {
            "type": "status",
            "phase": phase,
            "title": title,
            "subtitle": subtitle,
            "detail": detail,
        }
    )


def enqueue_patch(
    *,
    name: str = "",
    subtitle: str = "",
    detail: str = "",
    from_state: bool = False,
) -> Path | None:
    return enqueue(
        {
            "type": "patch",
            "name": name,
            "subtitle": subtitle,
            "detail": detail,
            "from_state": from_state,
        }
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
