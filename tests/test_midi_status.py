"""Tests for MIDI status exposed on the LAN monitor."""

from __future__ import annotations

from unittest.mock import patch

from midi_controller import (
    _midi_status_label,
    midi_snapshot,
    midi_status_summary,
    save_midi_status,
)


def test_midi_snapshot_prefers_keystep():
    config = {"midi": {"preferred_input_keywords": ["KeyStep"]}}
    with patch(
        "midi_controller.MidiController.list_inputs",
        return_value=["USB MIDI 1", "Arturia KeyStep 37"],
    ):
        snap = midi_snapshot(config)
    assert snap["preferred_found"] is True
    assert snap["selected_port"] == "Arturia KeyStep 37"


def test_midi_status_label_connected():
    snap = {"selected_port": "KeyStep", "preferred_found": True, "inputs": ["KeyStep"]}
    synth = {"listening": True, "port_name": "Arturia KeyStep 37", "connected": True}
    label, ok = _midi_status_label(snap, synth)
    assert ok is True
    assert "Connected" in label
    assert "KeyStep" in label


def test_midi_status_label_not_connected():
    snap = {"preferred_found": False, "device_present": False, "inputs": []}
    label, ok = _midi_status_label(snap, {"listening": False, "connected": False})
    assert ok is False
    assert "Not connected" in label


def test_save_and_summary(tmp_path):
    config = {
        "app": {"marker_dir": str(tmp_path)},
        "midi": {"preferred_input_keywords": ["KeyStep"]},
    }
    save_midi_status(
        config, connected=True, port_name="Arturia KeyStep 37", listening=True
    )
    with patch(
        "midi_controller.MidiController.list_inputs",
        return_value=["Arturia KeyStep 37"],
    ):
        status = midi_status_summary(config)
    assert status["ok"] is True
    assert "Connected" in status["label"]
