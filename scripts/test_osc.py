#!/usr/bin/env python3
"""Send test patch and notes to SuperCollider."""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config
from logging_setup import setup_logging
from osc_client import OscClient
from patch_generator import PatchGenerator

setup_logging("INFO")


def main() -> int:
    config = load_config()
    osc = OscClient(config)
    gen = PatchGenerator(config)
    patch = gen.generate(seed=42)
    print("Loud test beep (440 Hz)...")
    osc._client.send_message("/pi_synth/test_beep", [440, 0.95])
    time.sleep(1.0)
    print(f"Sending patch: {patch.summary()}")
    osc.send_patch(patch)
    time.sleep(0.5)
    print("Note on C4 (vel 127)...")
    osc.note_on(60, 127)
    time.sleep(1.5)
    print("Note off C4...")
    osc.note_off(60)
    time.sleep(0.5)
    print("Done. If silent: sudo journalctl -u supercollider -n 30 | grep -E 'OSC note_on|playNote|test_beep|ERROR'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
