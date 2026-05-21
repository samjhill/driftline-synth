#!/usr/bin/env python3
"""Short sine blip on ALSA default (dmix) — audible KeyStep notes while JACK holds hw:0,0."""

from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


def midi_to_hz(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def write_blip_wav(path: Path, *, freq: float, sample_rate: int, duration: float, amp: float) -> None:
    n = max(1, int(sample_rate * duration))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        for i in range(n):
            t = i / sample_rate
            env = min(1.0, t / 0.008) * min(1.0, (duration - t) / 0.04)
            sample = int(max(-32767, min(32767, env * amp * math.sin(2.0 * math.pi * freq * t) * 32767)))
            wf.writeframes(sample.to_bytes(2, "little", signed=True))


def play(device: str, note: int, velocity: int, duration: float) -> int:
    freq = midi_to_hz(note)
    amp = 0.25 + (velocity / 127.0) * 0.55
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = Path(tmp.name)
    try:
        write_blip_wav(path, freq=freq, sample_rate=48000, duration=duration, amp=amp)
        subprocess.run(["aplay", "-q", "-D", device, str(path)], check=True)
        return 0
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        print(f"keyboard blip failed: {e}", file=sys.stderr)
        return 1
    finally:
        path.unlink(missing_ok=True)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("note", type=int, help="MIDI note number")
    p.add_argument("velocity", type=int, nargs="?", default=100)
    p.add_argument("-D", "--device", default="default")
    p.add_argument("-d", "--duration", type=float, default=0.14)
    args = p.parse_args()
    return play(args.device, args.note, args.velocity, args.duration)


if __name__ == "__main__":
    sys.exit(main())
