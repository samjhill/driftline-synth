"""SHIFT+PLAY (MIDI start + shift CC) invokes reseed callback."""

from __future__ import annotations

import sys
from pathlib import Path

import mido

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config  # noqa: E402
from midi_controller import MidiController  # noqa: E402


def test_shift_play_start_reseed() -> None:
    config = load_config()
    midi = MidiController(config)
    seen: list[int] = []
    midi.on_reseed_requested = lambda: seen.append(1)
    midi._handle_message(mido.Message("control_change", control=63, value=127, channel=0))
    midi._handle_message(mido.Message("start"))
    assert seen, "SHIFT+PLAY should call on_reseed_requested"
