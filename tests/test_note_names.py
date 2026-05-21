"""Tests for MIDI note name formatting."""

from __future__ import annotations

from note_names import format_active_notes, midi_note_name


def test_midi_note_name_middle_c():
    assert midi_note_name(60) == "C4"


def test_midi_note_name_sharp():
    assert midi_note_name(61) == "C#4"


def test_format_active_notes_sorted():
    assert format_active_notes({64, 60, 67}) == "C4 E4 G4"


def test_format_active_notes_truncation():
    notes = {60, 61, 62, 63, 64, 65}
    text = format_active_notes(notes, max_notes=3)
    assert text.startswith("C4 C#4 D4")
    assert "+3" in text
