"""MIDI note number → readable name for e-ink / status."""

from __future__ import annotations

_NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")


def midi_note_name(note: int) -> str:
    """Return standard name, e.g. 60 → C4."""
    n = int(note)
    if not 0 <= n <= 127:
        return f"n{n}"
    return f"{_NOTE_NAMES[n % 12]}{n // 12 - 1}"


def format_active_notes(notes: set[int] | list[int], *, max_notes: int = 5) -> str:
    if not notes:
        return ""
    ordered = sorted(int(n) for n in notes)[:max_notes]
    text = " ".join(midi_note_name(n) for n in ordered)
    extra = len(notes) - max_notes
    if extra > 0:
        text = f"{text} +{extra}"
    return text
