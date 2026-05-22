#!/usr/bin/env python3
"""Show deploy/system status on the e-ink display.

Usage:
  show_status.py <phase> <title> [subtitle] [detail]
  show_status.py --step 3 --total 10 <phase> <title> [subtitle] [detail]
  show_status.py --restore-patch
"""
from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path


def _src_dir() -> Path:
    for candidate in (
        Path(__file__).resolve().parent.parent / "src",
        Path("/home/pi/pi-ambient-synth/src"),
    ):
        if candidate.is_dir():
            return candidate
    return Path(__file__).resolve().parent.parent / "src"


sys.path.insert(0, str(_src_dir()))

from config_loader import load_config
from eink_display import EInkDisplay
from pisugar_battery import read_battery_snapshot
from status_display import StatusDisplay


def _skip_numpy_sigil(config: dict) -> bool:
    """Pi production: numpy/visual_generator can SIGBUS in a short-lived e-ink job."""
    for key in ("PI_EINK_SKIP_NUMPY", "PI_MONITOR_SKIP_SIGIL"):
        if os.environ.get(key, "").strip().lower() in ("1", "true", "yes"):
            return True
    if config.get("eink", {}).get("skip_numpy_sigil"):
        return True
    return bool(config.get("monitor", {}).get("skip_sigil", False))


def show_status(
    phase: str,
    title: str,
    subtitle: str = "",
    detail: str = "",
    step: int | None = None,
    total_steps: int | None = None,
    config_path: Path | None = None,
) -> int:
    config = load_config(config_path)
    if not config.get("eink", {}).get("enabled", True):
        return 0
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    log_path = os.environ.get("EINK_LOG")
    if log_path:
        try:
            Path(log_path).parent.mkdir(parents=True, exist_ok=True)
            handlers.append(
                logging.FileHandler(log_path, mode="a", encoding="utf-8")
            )
        except OSError:
            pass
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s %(message)s",
        handlers=handlers,
        force=True,
    )
    display = EInkDisplay(config)
    if not display.init():
        display.release()
        print("E-ink init failed — check SPI, gpiozero, vendor/waveshare", file=sys.stderr)
        return 1
    battery = None
    if config.get("pisugar", {}).get("show_on_display", True):
        battery = read_battery_snapshot(config)
        if not battery.available:
            battery = None
    renderer = StatusDisplay(config)
    img = renderer.render(
        phase,
        title,
        subtitle,
        detail,
        step=step,
        total_steps=total_steps,
        battery=battery,
    )
    full = os.environ.get("EINK_FORCE") == "1" or phase in ("boot", "failed")
    try:
        display.show_image(img, full_refresh=full)
    finally:
        display.release()
    return 0


def restore_patch() -> int:
    from patch_generator import PatchGenerator
    from state_store import StateStore

    config = load_config()
    if not config.get("eink", {}).get("enabled", True):
        return 0
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    log_path = os.environ.get("EINK_LOG")
    if log_path:
        try:
            Path(log_path).parent.mkdir(parents=True, exist_ok=True)
            handlers.append(
                logging.FileHandler(log_path, mode="a", encoding="utf-8")
            )
        except OSError:
            pass
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s %(message)s",
        handlers=handlers,
        force=True,
    )
    app = config.get("app", {})
    store = StateStore(
        Path(app.get("state_path", "./state/current_patch.json")),
        Path(app.get("favorites_path", "./state/favorites.json")),
    )
    patch = store.load_current()
    if not patch:
        patch = PatchGenerator(config).generate()
    display = EInkDisplay(config)
    if not display.init():
        display.release()
        return 1
    battery = None
    if config.get("pisugar", {}).get("show_on_display", True):
        battery = read_battery_snapshot(config)
        if not battery.available:
            battery = None
    if _skip_numpy_sigil(config):
        renderer = StatusDisplay(config)
        img = renderer.render(
            "playing",
            patch.name[:28],
            patch.scale_name[:28],
            f"seed {patch.seed}",
            battery=battery,
        )
    else:
        from visual_generator import VisualGenerator

        img = VisualGenerator(config).render_patch(patch, battery=battery)
    try:
        display.show_image(img, full_refresh=False)
    finally:
        display.release()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="E-ink status display")
    parser.add_argument("--restore-patch", action="store_true")
    parser.add_argument("--config", type=Path, default=None)
    parser.add_argument("--step", type=int, default=None)
    parser.add_argument("--total", type=int, default=None)
    parser.add_argument("phase", nargs="?", default="idle")
    parser.add_argument("title", nargs="?", default="")
    parser.add_argument("subtitle", nargs="?", default="")
    parser.add_argument("detail", nargs="?", default="")
    args = parser.parse_args()

    if args.restore_patch:
        return restore_patch()
    return show_status(
        args.phase,
        args.title,
        args.subtitle,
        args.detail,
        args.step,
        args.total,
        args.config,
    )


if __name__ == "__main__":
    sys.exit(main())
