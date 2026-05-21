#!/usr/bin/env python3
"""Looping soft ambient pad on ALSA plughw (Pi 3 headphone jack).

Used when SuperCollider→JACK is silent but per-note aplay blips work (hybrid ambient).
"""

from __future__ import annotations

import math
import os
import signal
import subprocess
import sys
import time

SAMPLE_RATE = int(os.environ.get("PI_DRONE_SAMPLE_RATE", "48000"))
CHUNK = int(os.environ.get("PI_DRONE_CHUNK", "2048"))
DEVICE = os.environ.get("PI_DRONE_ALSA_DEVICE", "plughw:0,0")
LEVEL = float(os.environ.get("PI_DRONE_LEVEL", "0.22"))
ROOT_MIDI = int(os.environ.get("PI_DRONE_ROOT", "48"))

_running = True


def _hz(midi: int) -> float:
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def _samples(t0: float, n: int) -> bytes:
    root = _hz(ROOT_MIDI)
    fifth = _hz(ROOT_MIDI + 7)
    oct_ = _hz(ROOT_MIDI + 12)
    out = []
    for i in range(n):
        t = t0 + i / SAMPLE_RATE
        drift = 1.0 + 0.003 * math.sin(t * 0.037)
        lfo = 0.52 + 0.48 * math.sin(t * 0.019)
        s = (
            0.42 * math.sin(2.0 * math.pi * root * drift * t)
            + 0.28 * math.sin(2.0 * math.pi * fifth * drift * t * 0.997)
            + 0.18 * math.sin(2.0 * math.pi * oct_ * t)
        )
        # cheap noise shimmer
        s += 0.04 * math.sin(2.0 * math.pi * (t * 137.0 % 1.0) * 800.0)
        v = int(max(-32767, min(32767, s * lfo * LEVEL * 32767)))
        out.append(v.to_bytes(2, "little", signed=True))
    return b"".join(out)


def main() -> int:
    global _running

    def stop(_s=None, _f=None) -> None:
        global _running
        _running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    cmd = [
        "aplay",
        "-q",
        "-D",
        DEVICE,
        "-f",
        "S16_LE",
        "-r",
        str(SAMPLE_RATE),
        "-c",
        "1",
    ]
    print(f"pi_alsa_texture_drone: {DEVICE} level={LEVEL} root={ROOT_MIDI}", flush=True)
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    t = 0.0
    try:
        while _running and proc.poll() is None:
            proc.stdin.write(_samples(t, CHUNK))
            proc.stdin.flush()
            t += CHUNK / SAMPLE_RATE
    except BrokenPipeError:
        pass
    finally:
        try:
            if proc.stdin:
                proc.stdin.close()
        except OSError:
            pass
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
    return 0 if proc.returncode in (0, None, -15) else proc.returncode or 1


if __name__ == "__main__":
    sys.exit(main())
