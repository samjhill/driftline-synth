"""MIDI clock → BPM for SuperCollider."""

from __future__ import annotations

import time


class MidiClock:
    def __init__(self, ppqn: int = 24, smooth: int = 8) -> None:
        self._ppqn = ppqn
        self._times: list[float] = []
        self._smooth = smooth
        self.bpm: float = 120.0

    def tick(self) -> float:
        now = time.monotonic()
        self._times.append(now)
        if len(self._times) > self._smooth:
            self._times.pop(0)
        if len(self._times) >= 2:
            span = self._times[-1] - self._times[0]
            ticks = (len(self._times) - 1) * self._ppqn
            if span > 0:
                self.bpm = (ticks / span) * 60.0 / self._ppqn
                self.bpm = max(40.0, min(200.0, self.bpm))
        return self.bpm
