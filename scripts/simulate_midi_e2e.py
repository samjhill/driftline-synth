#!/usr/bin/env python3
"""Pi E2E: exercise MIDI → Python → OSC paths (no headphones required).

Run on the Pi while supercollider is up. Uses synthetic MIDI messages on
MidiController (same code as pi-ambient-synth). Verifies reseed + note_on reach SC.
"""

from __future__ import annotations

import json
import random
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

import mido  # noqa: E402

from config_loader import install_root, load_config, resolve_data_path  # noqa: E402
from logging_setup import setup_logging  # noqa: E402
from midi_controller import MidiController  # noqa: E402
from osc_client import OscClient  # noqa: E402
from patch_generator import PatchGenerator  # noqa: E402
from patch_resolve import resolve_current_patch  # noqa: E402
from state_store import StateStore  # noqa: E402

READY = Path("/var/lib/pi-ambient-synth/sc-engine-ready")


def _journal_grep(pattern: str, unit: str = "supercollider", lines: int = 40) -> str:
    try:
        out = subprocess.run(
            [
                "journalctl",
                "-u",
                unit,
                "-n",
                str(lines),
                "--no-pager",
                "--since",
                "3 min ago",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        return "\n".join(
            ln for ln in out.stdout.splitlines() if pattern.lower() in ln.lower()
        )
    except (subprocess.TimeoutExpired, OSError):
        return ""


def main() -> int:
    setup_logging("INFO")
    if not READY.is_file():
        print("FAIL: sc-engine-ready missing — supercollider not ready", file=sys.stderr)
        return 1

    config = load_config()
    root = install_root()
    app = config.get("app", {})
    store = StateStore(
        resolve_data_path(app.get("state_path", "./state/current_patch.json"), root),
        resolve_data_path(app.get("favorites_path", "./state/favorites.json"), root),
    )
    gen = PatchGenerator(config)
    osc = OscClient(config)
    patch = resolve_current_patch(config, store, gen)
    seed_before = patch.seed
    reseed_ok = False
    note_ok = False

    midi = MidiController(config)

    def on_reseed() -> None:
        nonlocal reseed_ok, patch
        new_seed = random.randint(0, 2**31 - 1)
        patch = gen.generate(seed=new_seed)
        store.save_current(patch)
        osc.reseed_transition(2.0)
        osc.reseed(new_seed)
        osc.send_patch(patch, morph_seconds=6.0)
        reseed_ok = True
        print(f"reseed ok → seed={new_seed} ({patch.summary()})")

    def on_note_on(note: int, velocity: int, _ch: int) -> None:
        nonlocal note_ok
        osc.note_on(note, velocity)
        note_ok = True
        print(f"note_on ok → {note} vel {velocity}")

    midi.on_reseed_requested = on_reseed
    midi.on_note_on = on_note_on

    # Shift held (CC 63 ≥ 64) + KeyStep Play (MIDI start)
    midi._handle_message(mido.Message("control_change", control=63, value=127, channel=0))
    midi._handle_message(mido.Message("start"))
    time.sleep(1.2)

    saved = store.load_current()
    seed_after = saved.seed if saved else None
    if not reseed_ok:
        print("FAIL: reseed callback not invoked", file=sys.stderr)
        return 2
    if seed_after is None or seed_after == seed_before:
        print(
            f"FAIL: patch seed unchanged ({seed_before} → {seed_after})",
            file=sys.stderr,
        )
        return 3

    sc_before = _journal_grep("reseed")
    # Release shift so note_on is not eaten by _handle_shift_note
    midi._handle_message(mido.Message("control_change", control=63, value=0, channel=0))
    midi._handle_message(mido.Message("note_on", note=72, velocity=110, channel=0))
    time.sleep(0.8)
    if not note_ok:
        print("FAIL: note_on callback not invoked", file=sys.stderr)
        return 4

    sc_note = _journal_grep("playNote") or _journal_grep("piAmbientVoice")
    sc_reseed = _journal_grep("reseed") or sc_before
    if "ERROR" in _journal_grep("ERROR"):
        err = _journal_grep("ERROR")
        if "linearRamp" in err or "not understood" in err:
            print(f"FAIL: SC errors in journal:\n{err}", file=sys.stderr)
            return 5

    print("PASS: MIDI reseed + note_on exercised (logic + OSC + state)")
    print(f"  seed: {seed_before} → {seed_after}")
    if sc_note:
        print(f"  SC journal (note): {sc_note[:200]}")
    if sc_reseed:
        print(f"  SC journal (reseed): {sc_reseed[:200]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
