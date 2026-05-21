"""Track held notes, sustain pedal, and arpeggiator-like note streams."""

from __future__ import annotations

import time


class PlayTracker:
    def __init__(self, arp_window: float = 0.45, arp_min_notes: int = 4) -> None:
        self._active: set[int] = set()
        self._hold_latch = False
        self._note_times: list[float] = []
        self._arp_window = arp_window
        self._arp_min = arp_min_notes
        self._arp_active = False

    @property
    def hold_latched(self) -> bool:
        return self._hold_latch

    @property
    def arp_active(self) -> bool:
        return self._arp_active

    @property
    def active_notes(self) -> frozenset[int]:
        return frozenset(self._active)

    def set_hold(self, on: bool) -> bool:
        changed = on != self._hold_latch
        self._hold_latch = on
        return changed

    def note_on(self, note: int) -> tuple[int | None, bool]:
        """Returns (texture_root_note, arp_active_changed)."""
        now = time.monotonic()
        self._active.add(note)
        self._note_times = [t for t in self._note_times if now - t < self._arp_window]
        self._note_times.append(now)
        was_arp = self._arp_active
        self._arp_active = len(self._note_times) >= self._arp_min
        root = self._texture_root()
        return root, was_arp != self._arp_active

    def note_off(self, note: int) -> int | None:
        self._active.discard(note)
        return self._texture_root()

    def lowest_active_note(self) -> int | None:
        if not self._active:
            return None
        return min(self._active)

    def _texture_root(self) -> int | None:
        if not self._active:
            return None
        if self._hold_latch or self._arp_active:
            return min(self._active)
        return None
