"""Live note names on e-ink (used by pi_midi_bridge; main.py has its own path)."""

from __future__ import annotations

import logging
import threading
import time
from typing import Any

from eink_lock import eink_exclusive_lock
from note_names import format_active_notes

logger = logging.getLogger(__name__)

_last_refresh = 0.0
_lock = threading.Lock()
_display = None


def _display_for(config: dict[str, Any]):
    global _display
    if _display is None:
        from eink_display import EInkDisplay

        _display = EInkDisplay(config)
    return _display


def refresh_playing_notes(
    config: dict[str, Any],
    active_notes: frozenset[int],
    *,
    velocity: int | None = None,
    patch_name: str = "",
    force: bool = False,
) -> None:
    eink_cfg = config.get("eink", {})
    if not eink_cfg.get("show_playing_note", True) or not eink_cfg.get("enabled", True):
        return

    global _last_refresh
    now = time.monotonic()
    interval = float(eink_cfg.get("note_refresh_seconds", 0.5))
    with _lock:
        if not force and now - _last_refresh < interval:
            return
        _last_refresh = now

    def _work() -> None:
        try:
            with eink_exclusive_lock(timeout_seconds=8.0):
                disp = _display_for(config)
                if not disp.available and not disp.init():
                    return
                if not active_notes:
                    return
                title = format_active_notes(active_notes)
                subtitle = f"vel {velocity}" if velocity is not None else ""
                if patch_name:
                    line = patch_name[:22]
                    subtitle = f"{subtitle}  {line}".strip() if subtitle else line
                disp.show_status(
                    "playing",
                    title,
                    subtitle,
                    "",
                    config=config,
                )
                # Do not release() — re-init costs 25s+ and blocks the panel.
        except TimeoutError:
            logger.warning("e-ink busy — skipped playing-note refresh")
        except Exception:
            logger.exception("e-ink playing-note refresh failed")

    threading.Thread(target=_work, daemon=True, name="eink-playing-note").start()
