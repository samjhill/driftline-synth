#!/usr/bin/env python3
"""Headless MIDI → OSC bridge (separate from main.py to avoid Pi rtmidi SIGBUS)."""

from __future__ import annotations

import logging
import os
import signal
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import install_root, load_config, resolve_data_path  # noqa: E402
from logging_setup import setup_logging  # noqa: E402
from midi_controller import MidiController, save_midi_status  # noqa: E402
from osc_client import OscClient  # noqa: E402
from patch_generator import PatchGenerator  # noqa: E402
from patch_model import Patch  # noqa: E402
from patch_resolve import resolve_current_patch  # noqa: E402
from state_store import StateStore  # noqa: E402

logger = logging.getLogger("pi_midi_bridge")
_running = True


def main() -> int:
    global _running
    setup_logging(os.environ.get("LOG_LEVEL", "INFO"))
    config = load_config()
    root = install_root()
    app_cfg = config.get("app", {})
    store = StateStore(
        resolve_data_path(app_cfg.get("state_path", "./state/current_patch.json"), root),
        resolve_data_path(app_cfg.get("favorites_path", "./state/favorites.json"), root),
    )
    gen = PatchGenerator(config)
    osc = OscClient(config)
    patch: Patch | None = resolve_current_patch(config, store, gen)
    morph = float(config.get("audio", {}).get("patch_morph_seconds", 6.0))

    midi = MidiController(config)

    def on_note_on(note: int, velocity: int, _ch: int) -> None:
        osc.note_on(note, velocity)

    def on_note_off(note: int, velocity: int, _ch: int) -> None:
        osc.note_off(note, velocity)

    def on_reseed() -> None:
        nonlocal patch
        import random

        new = gen.generate(seed=random.randint(0, 2**31 - 1))
        store.save_current(new)
        patch = new
        osc.reseed_transition(2.0)
        osc.reseed(new.seed)
        osc.send_patch(new, morph_seconds=morph)
        logger.info("Reseed → %s", new.summary())

    midi.on_note_on = on_note_on
    midi.on_note_off = on_note_off
    midi.on_reseed_requested = on_reseed

    if not midi.open():
        logger.error("No MIDI input — bridge exiting")
        save_midi_status(config, connected=False, port_name=None, listening=False)
        return 1

    midi.start()
    save_midi_status(
        config,
        connected=True,
        port_name=midi.port_name,
        listening=True,
        state="running",
    )
    logger.info("MIDI bridge running on %s → OSC", midi.port_name)

    def stop(_s=None, _f=None):
        global _running
        _running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    try:
        while _running:
            midi.poll()
            time.sleep(0.002)
    finally:
        midi.stop()
        save_midi_status(config, connected=False, port_name=None, listening=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
