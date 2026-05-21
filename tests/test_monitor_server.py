"""Tests for monitor status collection and web controls."""

from __future__ import annotations

import json
from http.client import HTTPConnection
from pathlib import Path
from threading import Thread
from unittest.mock import MagicMock, patch

from monitor_server import (
    MonitorHandler,
    ThreadingHTTPServer,
    _apply_web_param,
    _controls_payload,
    _html_page,
    _osc_weights,
    _read_deploy_sha,
    _sigil_png,
    _tail_file,
    collect_status,
)
from patch_model import Patch


def test_read_deploy_sha_prefers_git_over_placeholder(tmp_path: Path, monkeypatch):
    install = tmp_path / "pi-ambient-synth"
    install.mkdir()
    marker = tmp_path / "var-lib"
    marker.mkdir()
    (install / ".deploy_sha").write_text("boot-sd\n", encoding="utf-8")
    (marker / "last_deploy_sha").write_text("281a96cdef0123456789abcdef0123456789ab\n", encoding="utf-8")
    monkeypatch.setattr("monitor_server.DEPLOY_SHA_FILE", install / ".deploy_sha")
    monkeypatch.setattr("monitor_server.MARKER_DIR", marker)
    sha, source = _read_deploy_sha()
    assert sha == "281a96cdef0"
    assert source == "marker"


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


def test_osc_weights_match_engine_blend():
    w = _osc_weights(0.5)
    assert abs(w["saw"] - 0.175) < 1e-6
    assert abs(w["sine"] - 0.2) < 1e-6
    assert abs(w["triangle"] - 0.125) < 1e-6


def test_controls_payload_has_knobs(tmp_path: Path):
    patch = Patch(
        seed=42,
        name="Test",
        scale_name="Dorian",
        root_note=48,
        oscillator_blend=0.5,
        sub_level=0.1,
        noise_level=0.05,
        filter_cutoff=1400.0,
        filter_resonance=0.2,
        attack=0.05,
        decay=0.8,
        sustain=0.6,
        release=2.5,
        drift_amount=0.01,
        lfo_rate=0.08,
        lfo_depth=0.08,
        delay_mix=0.2,
        delay_time=0.5,
        reverb_mix=0.45,
        reverb_size=0.75,
        texture_density=0.5,
        stereo_width=0.7,
        brightness=0.6,
    )
    state_path = tmp_path / "current_patch.json"
    state_path.write_text(patch.to_json(), encoding="utf-8")
    config = {
        "app": {
            "state_path": str(state_path),
            "favorites_path": str(tmp_path / "fav.json"),
        },
        "audio": {"default_volume": 0.7},
        "patch": {"default_seed": 42},
    }
    payload = _controls_payload(config)
    assert payload["patch"]["seed"] == 42
    assert any(k["key"] == "filter_cutoff" for k in payload["knobs"])
    assert payload["wave_presets"][0]["name"] == "Sine"


def test_apply_web_param_sends_osc(tmp_path: Path, monkeypatch):
    patch = Patch(
        seed=1,
        name="T",
        scale_name="Dorian",
        root_note=48,
        oscillator_blend=0.5,
        sub_level=0.1,
        noise_level=0.05,
        filter_cutoff=1400.0,
        filter_resonance=0.2,
        attack=0.05,
        decay=0.8,
        sustain=0.6,
        release=2.5,
        drift_amount=0.01,
        lfo_rate=0.08,
        lfo_depth=0.08,
        delay_mix=0.2,
        delay_time=0.5,
        reverb_mix=0.45,
        reverb_size=0.75,
        texture_density=0.5,
        stereo_width=0.7,
        brightness=0.6,
    )
    state_path = tmp_path / "current_patch.json"
    state_path.write_text(patch.to_json(), encoding="utf-8")
    config = {
        "app": {
            "state_path": str(state_path),
            "favorites_path": str(tmp_path / "fav.json"),
        },
        "osc": {"supercollider_host": "127.0.0.1", "supercollider_port": 57120},
    }
    mock_osc = MagicMock()
    monkeypatch.setattr("monitor_server.OscClient", lambda _cfg: mock_osc)
    result = _apply_web_param(config, "filter_cutoff", 2000.0)
    assert result["ok"] is True
    assert result["value"] == 2000.0
    mock_osc.set_param.assert_called_with("filter_cutoff", 2000.0)
    saved = json.loads(state_path.read_text(encoding="utf-8"))
    assert saved["filter_cutoff"] == 2000.0


def test_sigil_png_bytes(tmp_path: Path):
    patch = Patch(
        seed=99,
        name="Sigil",
        scale_name="Aeolian",
        root_note=48,
        oscillator_blend=0.5,
        sub_level=0.1,
        noise_level=0.05,
        filter_cutoff=1400.0,
        filter_resonance=0.2,
        attack=0.05,
        decay=0.8,
        sustain=0.6,
        release=2.5,
        drift_amount=0.01,
        lfo_rate=0.08,
        lfo_depth=0.08,
        delay_mix=0.2,
        delay_time=0.5,
        reverb_mix=0.45,
        reverb_size=0.75,
        texture_density=0.5,
        stereo_width=0.7,
        brightness=0.6,
    )
    state_path = tmp_path / "current_patch.json"
    state_path.write_text(patch.to_json(), encoding="utf-8")
    config = {
        "app": {
            "state_path": str(state_path),
            "favorites_path": str(tmp_path / "fav.json"),
        },
        "eink": {"width": 120, "height": 60},
    }
    png = _sigil_png(config)
    assert png[:8] == b"\x89PNG\r\n\x1a\n"


def test_html_includes_controls_panel():
    html = _html_page({"app": "Test", "patch": {}, "network": {}})
    assert "controls-panel" in html
    assert "wave-canvas" in html
    assert "/api/sigil.png" in html


def test_monitor_http_routes(tmp_path: Path, monkeypatch):
    patch = Patch(
        seed=7,
        name="HTTP",
        scale_name="Dorian",
        root_note=48,
        oscillator_blend=0.5,
        sub_level=0.1,
        noise_level=0.05,
        filter_cutoff=1400.0,
        filter_resonance=0.2,
        attack=0.05,
        decay=0.8,
        sustain=0.6,
        release=2.5,
        drift_amount=0.01,
        lfo_rate=0.08,
        lfo_depth=0.08,
        delay_mix=0.2,
        delay_time=0.5,
        reverb_mix=0.45,
        reverb_size=0.75,
        texture_density=0.5,
        stereo_width=0.7,
        brightness=0.6,
    )
    state_path = tmp_path / "current_patch.json"
    state_path.write_text(patch.to_json(), encoding="utf-8")
    config = {
        "app": {
            "state_path": str(state_path),
            "favorites_path": str(tmp_path / "fav.json"),
        },
        "eink": {"width": 80, "height": 40},
    }
    mock_osc = MagicMock()
    monkeypatch.setattr("monitor_server.OscClient", lambda _cfg: mock_osc)

    handler = type("BoundMonitorHandler", (MonitorHandler,), {"config": config})
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = server.server_address[1]
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        conn = HTTPConnection("127.0.0.1", port, timeout=5)
        conn.request("GET", "/api/controls")
        resp = conn.getresponse()
        assert resp.status == 200
        data = json.loads(resp.read().decode())
        assert data["patch"]["name"] == "HTTP"

        conn = HTTPConnection("127.0.0.1", port, timeout=5)
        conn.request("GET", "/api/sigil.png")
        resp = conn.getresponse()
        assert resp.status == 200
        assert resp.getheader("Content-Type", "").startswith("image/png")

        conn = HTTPConnection("127.0.0.1", port, timeout=5)
        conn.request(
            "POST",
            "/api/param",
            body=json.dumps({"name": "reverb_mix", "value": 0.55}),
            headers={"Content-Type": "application/json"},
        )
        resp = conn.getresponse()
        assert resp.status == 200
        assert json.loads(resp.read().decode())["ok"] is True
    finally:
        server.shutdown()
        thread.join(timeout=2)
