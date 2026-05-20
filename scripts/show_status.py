#!/usr/bin/env python3
"""Show deploy/system status on the e-ink display.

Usage:
  show_status.py <phase> <title> [subtitle] [detail]
  show_status.py --restore-patch   # redraw current patch sigil after deploy
"""
from __future__ import annotations

import argparse
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
from patch_generator import PatchGenerator
from state_store import StateStore
from status_display import StatusDisplay
from visual_generator import VisualGenerator


def show_status(phase: str, title: str, subtitle: str = "", detail: str = "") -> int:
    config = load_config()
    if not config.get("eink", {}).get("enabled", True):
        return 0
    display = EInkDisplay(config)
    display.init()
    renderer = StatusDisplay(config)
    img = renderer.render(phase, title, subtitle, detail)
    display.show_image(img)
    return 0


def restore_patch() -> int:
    config = load_config()
    if not config.get("eink", {}).get("enabled", True):
        return 0
    app = config.get("app", {})
    store = StateStore(
        Path(app.get("state_path", "./state/current_patch.json")),
        Path(app.get("favorites_path", "./state/favorites.json")),
    )
    patch = store.load_current()
    if not patch:
        patch = PatchGenerator(config).generate()
    display = EInkDisplay(config)
    display.init()
    img = VisualGenerator(config).render_patch(patch)
    display.show_patch(patch, img)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="E-ink status display")
    parser.add_argument("--restore-patch", action="store_true")
    parser.add_argument("phase", nargs="?", default="idle")
    parser.add_argument("title", nargs="?", default="")
    parser.add_argument("subtitle", nargs="?", default="")
    parser.add_argument("detail", nargs="?", default="")
    args = parser.parse_args()

    if args.restore_patch:
        return restore_patch()
    return show_status(args.phase, args.title, args.subtitle, args.detail)


if __name__ == "__main__":
    sys.exit(main())
