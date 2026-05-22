"""Shift press and transport patterns invoke reseed callback."""

from __future__ import annotations

import sys
import time
from pathlib import Path

import mido

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config  # noqa: E402
from midi_controller import MidiController  # noqa: E402


def test_shift_press_reseed() -> None:
    config = load_config()
    midi = MidiController(config)
    seen: list[int] = []
    midi.on_reseed_requested = lambda: seen.append(1)
    midi._handle_message(mido.Message("control_change", control=63, value=127, channel=0))
    assert seen, "Shift press (CC63) should reseed"
    seen.clear()
    midi._handle_message(mido.Message("control_change", control=63, value=0, channel=0))
    time.sleep(0.45)
    midi._handle_message(mido.Message("control_change", control=63, value=127, channel=0))
    assert len(seen) == 1, "Second shift press should reseed again"


def test_shift_latch_reseed_after_release() -> None:
    import time

    config = load_config()
    midi = MidiController(config)
    seen: list[int] = []
    midi.on_reseed_requested = lambda: seen.append(1)
    midi._handle_message(mido.Message("control_change", control=63, value=127, channel=0))
    midi._handle_message(mido.Message("control_change", control=63, value=0, channel=0))
    time.sleep(0.05)
    midi._handle_message(mido.Message("stop"))
    assert seen, "Reseed should fire within shift_latch_seconds after shift release"


def test_shift_transport_cc_reseed() -> None:
    config = load_config()
    midi = MidiController(config)
    seen: list[int] = []
    midi.on_reseed_requested = lambda: seen.append(1)
    midi._handle_message(mido.Message("control_change", control=63, value=127, channel=0))
    midi._handle_message(mido.Message("control_change", control=102, value=127, channel=0))
    assert seen, "SHIFT + transport play CC should reseed"


def test_transport_restart_reseed_without_shift() -> None:
    config = load_config()
    config.setdefault("midi", {})["reseed_on_transport_restart"] = True
    midi = MidiController(config)
    seen: list[int] = []
    midi.on_reseed_requested = lambda: seen.append(1)
    midi._handle_message(mido.Message("stop"))
    midi._handle_message(mido.Message("start"))
    assert seen, "stop then start should reseed when reseed_on_transport_restart is enabled"


def test_start_while_clocking_reseed() -> None:
    """Start while arp clock already running (optional legacy pattern)."""
    config = load_config()
    config.setdefault("midi", {})["reseed_on_start_while_clocking"] = True
    midi = MidiController(config)
    seen: list[int] = []
    midi.on_reseed_requested = lambda: seen.append(1)
    midi._clock_since = __import__("time").time() - 2.0
    midi._handle_message(mido.Message("start"))
    assert seen, "start while clocking should reseed"


def test_mmc_sysex_play_reseed_with_modifier() -> None:
    config = load_config()
    midi = MidiController(config)
    seen: list[int] = []
    midi.on_reseed_requested = lambda: seen.append(1)
    midi._handle_message(mido.Message("control_change", control=64, value=127, channel=0))
    midi._handle_message(mido.Message("sysex", data=(127, 127, 6, 2)))
    assert seen, "MMC play sysex with modifier should reseed"
