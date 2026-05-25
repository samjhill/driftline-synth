#!/usr/bin/env python3
"""Single owner of Waveshare e-ink — processes queue messages only."""
from __future__ import annotations

import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

os.environ.setdefault("HOME", "/home/pi")
os.environ.setdefault("GPIOZERO_PIN_FACTORY", "lgpio")
os.environ.setdefault("MARKER_DIR", "/var/lib/pi-ambient-synth")
os.environ.setdefault("EINK_NO_DEEP_SLEEP", "0")

from config_loader import load_config
from eink_display import EInkDisplay, EinkBusyTimeoutError
from eink_queue import queue_depth, queue_dir
from eink_service_state import write_service_state
from eink_status import write_eink_status
from status_display import StatusDisplay

logger = logging.getLogger("eink_service")
_running = True


def _kill_legacy() -> None:
    script = ROOT / "scripts" / "eink_kill_legacy_holders.sh"
    if script.is_file():
        subprocess.run(["bash", str(script)], check=False, timeout=120)


def _setup_logging() -> None:
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    log_path = os.environ.get("EINK_LOG", "/var/log/pi-ambient-synth-eink.log")
    try:
        Path(log_path).parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_path, mode="a", encoding="utf-8"))
    except OSError:
        pass
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=handlers,
        force=True,
    )


def _sleep_panel(display: EInkDisplay) -> None:
    display.release()


def _render_patch_message(
    config: dict[str, Any], msg: dict[str, Any], display: EInkDisplay
) -> str:
    title = (msg.get("name") or "").strip()
    subtitle = (msg.get("subtitle") or "").strip()
    detail = (msg.get("detail") or "").strip()
    summary = title or "patch"

    if msg.get("from_state") or not title:
        try:
            from patch_generator import PatchGenerator
            from state_store import StateStore

            app = config.get("app", {})
            store = StateStore(
                Path(app.get("state_path", "./state/current_patch.json")),
                Path(app.get("favorites_path", "./state/favorites.json")),
            )
            patch = store.load_current()
            if not patch:
                patch = PatchGenerator(config).generate()
            title = patch.name[:28]
            subtitle = patch.scale_name[:28]
            detail = f"seed {patch.seed}"
            summary = patch.summary()
        except Exception as e:
            logger.warning("patch from state failed: %s", e)
            title = title or "Ambient"
            subtitle = subtitle or "no patch file"

    renderer = StatusDisplay(config)
    img = renderer.render("playing", title, subtitle, detail)
    display.show_image(img, full_refresh=False)
    return summary


def _render_status_message(
    config: dict[str, Any], msg: dict[str, Any], display: EInkDisplay
) -> str:
    phase = msg.get("phase") or "idle"
    title = msg.get("title") or ""
    subtitle = msg.get("subtitle") or ""
    detail = msg.get("detail") or ""
    renderer = StatusDisplay(config)
    full = phase in ("boot", "failed", "startup")
    img = renderer.render(phase, title, subtitle, detail)
    display.show_image(img, full_refresh=full)
    return f"{title} ({phase})"


def _process_one(
    path: Path, config: dict[str, Any], display: EInkDisplay
) -> None:
    try:
        import json

        msg = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        logger.warning("bad queue file %s: %s", path.name, e)
        path.unlink(missing_ok=True)
        write_eink_status("ERROR", detail=f"bad queue: {path.name}")
        write_service_state(last_error=str(e), queue_depth=queue_depth())
        return

    mtype = msg.get("type")
    logger.info("process %s (%s)", path.name, mtype)
    write_service_state(
        processing=path.name,
        queue_depth=queue_depth(),
        panel_sleeping=False,
    )

    try:
        if not display.available and not display.init():
            write_eink_status("INIT_FAILED", detail="init in service")
            write_service_state(last_error="init failed", queue_depth=queue_depth())
            path.unlink(missing_ok=True)
            return

        if mtype == "startup":
            _render_status_message(
                config,
                {
                    "phase": "boot",
                    "title": "Pi Ambient Synth",
                    "subtitle": "Ready",
                    "detail": "",
                },
                display,
            )
            summary = "startup"
        elif mtype == "status":
            summary = _render_status_message(config, msg, display)
        elif mtype == "patch":
            summary = _render_patch_message(config, msg, display)
        else:
            logger.warning("unknown message type %s", mtype)
            summary = str(mtype)

        write_eink_status("OK", patch_summary=summary)
        write_service_state(
            last_ok_at=time.strftime("%Y-%m-%d %H:%M:%S"),
            last_error="",
            last_message_type=mtype,
            queue_depth=queue_depth(),
        )
    except EinkBusyTimeoutError as e:
        logger.warning("busy timeout: %s", e)
        write_eink_status("EINK_BUSY_TIMEOUT", detail=str(e))
        write_service_state(last_error=str(e), queue_depth=queue_depth())
    except OSError as e:
        logger.warning("GPIO error: %s", e)
        write_eink_status("GPIO_UNAVAILABLE", detail=str(e))
        write_service_state(last_error=str(e), queue_depth=queue_depth())
    except Exception as e:
        logger.exception("display failed")
        write_eink_status("ERROR", detail=str(e))
        write_service_state(last_error=str(e), queue_depth=queue_depth())
    finally:
        path.unlink(missing_ok=True)
        write_service_state(
            panel_sleeping=False,
            queue_depth=queue_depth(),
            processing=None,
        )


def _drain_queue(config: dict[str, Any], display: EInkDisplay) -> None:
    q = queue_dir()
    paths = sorted(q.glob("*.json"), key=lambda p: p.name)
    for path in paths:
        if not _running:
            break
        _process_one(path, config, display)


def _stop(_s=None, _f=None) -> None:
    global _running
    _running = False


def main() -> int:
    global _running
    _setup_logging()
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    config = load_config()
    eink_cfg = config.get("eink", {})
    if not eink_cfg.get("enabled", True):
        logger.info("e-ink disabled in config")
        write_service_state(service_active=False, disabled=True)
        return 0

    logger.info("e-ink service starting (queue %s)", queue_dir())
    _kill_legacy()
    write_service_state(
        service_active=True,
        started_at=time.strftime("%Y-%m-%d %H:%M:%S"),
        queue_depth=queue_depth(),
        panel_sleeping=True,
    )

    display = EInkDisplay(config)
    # Startup screen once (also accept queued startup messages later).
    try:
        if display.init():
            _render_status_message(
                config,
                {
                    "phase": "boot",
                    "title": "Pi Ambient Synth",
                    "subtitle": "Audio ready",
                    "detail": "",
                },
                display,
            )
            write_eink_status("OK", patch_summary="service startup")
            write_service_state(last_ok_at=time.strftime("%Y-%m-%d %H:%M:%S"))
        else:
            write_eink_status("INIT_FAILED", detail="service startup init")
            write_service_state(last_error="startup init failed")
    except Exception as e:
        logger.exception("startup display failed")
        write_eink_status("ERROR", detail=str(e))
        write_service_state(last_error=str(e))

    poll = float(eink_cfg.get("service_poll_seconds", 0.5))
    while _running:
        _drain_queue(config, display)
        time.sleep(poll)

    logger.info("e-ink service stopping")
    _sleep_panel(display)
    from eink_service_state import mark_inactive

    mark_inactive()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
