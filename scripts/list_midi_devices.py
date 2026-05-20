#!/usr/bin/env python3
"""List MIDI devices and optionally monitor incoming messages."""

from __future__ import annotations

import argparse
import sys
import time

try:
    import mido
except ImportError:
    print("Install mido and python-rtmidi: pip install mido python-rtmidi")
    sys.exit(1)


def list_devices() -> None:
    print("=== MIDI Input Ports ===")
    inputs = mido.get_input_names()
    if not inputs:
        print("(none)")
    for i, name in enumerate(inputs):
        print(f"  [{i}] {name}")
    print("\n=== MIDI Output Ports ===")
    outputs = mido.get_output_names()
    if not outputs:
        print("(none)")
    for i, name in enumerate(outputs):
        print(f"  [{i}] {name}")


def monitor(port_name: str | None) -> None:
    names = mido.get_input_names()
    if not names:
        print("No MIDI inputs available.")
        return
    if port_name is None:
        for kw in ("KeyStep", "Arturia"):
            for n in names:
                if kw.lower() in n.lower():
                    port_name = n
                    break
            if port_name:
                break
        port_name = port_name or names[0]
    print(f"Monitoring: {port_name} (Ctrl+C to stop)\n")
    with mido.open_input(port_name) as port:
        while True:
            for msg in port.iter_pending():
                print(msg)
            time.sleep(0.01)


def main() -> int:
    parser = argparse.ArgumentParser(description="List / monitor MIDI devices")
    parser.add_argument("--monitor", "-m", action="store_true", help="Print incoming MIDI")
    parser.add_argument("--port", type=str, default=None, help="Port name for monitor")
    args = parser.parse_args()
    list_devices()
    if args.monitor:
        print()
        try:
            monitor(args.port)
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
