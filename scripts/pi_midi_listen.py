#!/usr/bin/env python3
"""Listen on KeyStep port for N seconds (stop pi-ambient-synth-midi first)."""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config  # noqa: E402
from midi_controller import MidiController  # noqa: E402

SECS = int(sys.argv[1]) if len(sys.argv) > 1 else 12


def main() -> int:
    import os

    os.environ.setdefault("PI_MIDI_LOG_TRANSPORT", "1")
    midi = MidiController(load_config())
    if not midi.open():
        print("FAIL: no MIDI input", file=sys.stderr)
        return 1
    midi.start()
    print(f"Listening on {midi.port_name} for {SECS}s — play the KeyStep now…")
    t0 = time.time()
    n = 0
    while time.time() - t0 < SECS:
        midi.poll()
        time.sleep(0.001)
    midi.stop()
    print("Done (see INFO lines above for note_on/note_off).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
