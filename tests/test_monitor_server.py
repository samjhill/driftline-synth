"""Tests for monitor status collection."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

from monitor_server import _tail_file, collect_status


def test_tail_file(tmp_path: Path):
    log = tmp_path / "test.log"
    log.write_text("line1\nline2\nline3\n", encoding="utf-8")
    assert _tail_file(log, 2) == ["line2", "line3"]


def test_collect_status_services(monkeypatch, tmp_path: Path):
    config = {
        "app": {
            "state_path": str(tmp_path / "missing.json"),
            "favorites_path": str(tmp_path / "fav.json"),
        },
        "monitor": {"port": 8080, "journal_lines": 5, "log_tail_lines": 10},
    }

    def fake_state(_unit: str) -> str:
        return {"supercollider.service": "failed"}.get(_unit, "active")

    midi_stub = {
        "label": "Not connected — no MIDI inputs",
        "ok": False,
        "inputs": [],
        "device_present": False,
    }
    with patch("monitor_server._service_state", side_effect=fake_state):
        with patch("monitor_server._service_detail", return_value={"ActiveState": "failed"}):
            with patch("monitor_server._journal_tail", return_value=([], None)):
                with patch("monitor_server._systemctl_status_tail", return_value=["● failed"]):
                    with patch("monitor_server.network_snapshot", return_value={"primary_ip": "10.0.0.1"}):
                        with patch("monitor_server.midi_status_summary", return_value=midi_stub):
                            status = collect_status(config)

    assert status["services"]["supercollider"] == "failed"
    assert "journal_logs" in status
    assert status["network"]["primary_ip"] == "10.0.0.1"
    assert status["midi"]["label"] == midi_stub["label"]
