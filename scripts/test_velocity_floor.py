#!/usr/bin/env python3
"""Verify MIDI velocity floor (no hardware). Run on Pi."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

import mido  # noqa: E402

from config_loader import load_config  # noqa: E402
from midi_controller import MidiController  # noqa: E402

logged: list[tuple[int, int, int]] = []


def main() -> int:
    config = load_config()
    midi = MidiController(config)
    floor = midi._velocity_floor

    def on_note_on(note: int, velocity: int, ch: int) -> None:
        logged.append((ch, note, velocity))

    midi.on_note_on = on_note_on
    midi._handle_message(mido.Message("note_on", note=72, velocity=11, channel=14))
    if not logged:
        print("FAIL: callback not invoked", file=sys.stderr)
        return 1
    ch, note, vel = logged[0]
    if vel != floor:
        print(f"FAIL: expected vel {floor}, got {vel}", file=sys.stderr)
        return 1
    print(f"PASS: ch={ch} note={note} vel={vel} (floor={floor})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
