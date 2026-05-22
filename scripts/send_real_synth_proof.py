#!/usr/bin/env python3
"""OSC proof messages for real SuperCollider path (no ALSA fallback)."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config  # noqa: E402
from osc_client import OscClient  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "action",
        choices=("proof_note", "proof_patch_a", "proof_patch_b", "note_on", "note_off"),
    )
    p.add_argument("--note", type=int, default=60)
    p.add_argument("--velocity", type=int, default=100)
    p.add_argument("--wait", type=float, default=0.0)
    args = p.parse_args()

    osc = OscClient(load_config())
    host, port = osc.host, osc.port
    print(f"OSC → {host}:{port} action={args.action}")

    if args.action == "proof_note":
        osc._client.send_message("/pi_synth/proof_note", [])
    elif args.action == "proof_patch_a":
        osc._client.send_message("/pi_synth/proof_patch_a", [])
    elif args.action == "proof_patch_b":
        osc._client.send_message("/pi_synth/proof_patch_b", [])
    elif args.action == "note_on":
        osc.note_on(args.note, args.velocity)
    else:
        osc.note_off(args.note)

    if args.wait > 0:
        time.sleep(args.wait)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
