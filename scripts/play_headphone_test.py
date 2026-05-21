#!/usr/bin/env python3
"""Play a short, gentle stereo test tone with slow left–right motion (headphone check)."""

from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


def _write_chill_wav(path: Path, *, sample_rate: int, duration: float) -> None:
    """Soft dual-tone pad with constant-power pan and fade in/out."""
    n = int(sample_rate * duration)
    f1, f2 = 196.0, 293.66  # G3 + D4 — calm open fifth
    pan_hz = 0.11  # slow L↔R (~9 s per full cycle)
    amp = 0.22

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        for i in range(n):
            t = i / sample_rate
            env = min(1.0, t / 0.6) * min(1.0, (duration - t) / 1.0)
            pan = 0.5 + 0.5 * math.sin(2.0 * math.pi * pan_hz * t)
            l_gain = math.sqrt(1.0 - pan)
            r_gain = math.sqrt(pan)
            tone = (
                0.65 * math.sin(2.0 * math.pi * f1 * t)
                + 0.35 * math.sin(2.0 * math.pi * f2 * t)
            )
            mono = env * amp * tone
            left = int(max(-32767, min(32767, mono * l_gain * 32767)))
            right = int(max(-32767, min(32767, mono * r_gain * 32767)))
            wf.writeframes(
                left.to_bytes(2, "little", signed=True)
                + right.to_bytes(2, "little", signed=True)
            )


def play(device: str, sample_rate: int, duration: float) -> int:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = Path(tmp.name)
    try:
        _write_chill_wav(path, sample_rate=sample_rate, duration=duration)
        print(f"Playing {duration:.0f}s chill pan test → {device} @ {sample_rate} Hz")
        subprocess.run(
            ["aplay", "-q", "-D", device, str(path)],
            check=True,
        )
        print("OK — headphone jack produced audio")
        return 0
    except FileNotFoundError:
        print("ERROR: aplay not found", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"ERROR: aplay failed ({e})", file=sys.stderr)
        return 1
    finally:
        path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-D", "--device", default="plughw:0,0", help="ALSA device (aplay -D)")
    parser.add_argument("-r", "--rate", type=int, default=44100, help="Sample rate")
    parser.add_argument("-d", "--duration", type=float, default=6.0, help="Seconds")
    args = parser.parse_args()
    return play(args.device, args.rate, args.duration)


if __name__ == "__main__":
    sys.exit(main())
