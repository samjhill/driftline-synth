#!/usr/bin/env python3
"""Step 1 V1: prove FluidSynth → ALSA plughw:0,0 → headphone jack."""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config  # noqa: E402
from fluidsynth_engine import FluidSynthEngine  # noqa: E402
from logging_setup import setup_logging  # noqa: E402


def stop_project() -> None:
    for unit in (
        "pi-ambient-synth",
        "pi-ambient-synth-midi",
        "pi-ambient-synth-monitor",
        "supercollider",
        "pi-flues-synth",
    ):
        subprocess.run(
            ["sudo", "-n", "systemctl", "stop", f"{unit}.service"],
            check=False,
            capture_output=True,
        )
    subprocess.run(["pkill", "-x", "jackd"], check=False)
    subprocess.run(["pkill", "-x", "scsynth"], check=False)
    subprocess.run(["pkill", "-x", "sclang"], check=False)
    subprocess.run(["pkill", "-x", "fluidsynth"], check=False)
    time.sleep(1)


def main() -> int:
    setup_logging("INFO")
    stop_project()
    if subprocess.run(["bash", "-c", "command -v raspi-config"], check=False).returncode == 0:
        subprocess.run(
            ["sudo", "raspi-config", "nonint", "do_audio", "1"],
            check=False,
        )
    subprocess.run(["amixer", "-c", "0", "set", "PCM", "95%", "unmute"], check=False)
    subprocess.run(["amixer", "-c", "0", "set", "Headphone", "95%", "unmute"], check=False)

    config = load_config()
    eng = FluidSynthEngine(config)
    print(f"FluidSynth backend: {eng.backend}")
    print(f"Soundfont: {eng._sf2}")
    print(f"ALSA device: {eng._alsa_device}")
    eng.demo_note(60, 110, 1.5)
    eng.demo_note(64, 100, 0.8)
    eng.demo_note(67, 100, 0.8)
    eng.stop()

    for unit in ("pi-ambient-synth-midi", "pi-ambient-synth-monitor"):
        subprocess.run(
            ["sudo", "-n", "systemctl", "start", f"{unit}.service"],
            check=False,
            capture_output=True,
        )

    print("")
    print("FLUIDSYNTH_HEADPHONE_DEMO_DONE_USER_MUST_CONFIRM")
    print("Listen on the Pi 3.5 mm headphone jack.")
    print("  Heard pad notes (C–E chord)?")
    print("  Silence?")
    print("")
    print("Reply: heard / silence")
    print("If heard: ./scripts/pi_enable_fluidsynth_engine.sh then play KeyStep.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
