"""Tests for PiSugar button → reseed configuration."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

from pisugar_button import configure_button_shell, get_button_shell, setup_reseed_button


def test_get_button_shell_parses_kind_and_path():
    with patch(
        "pisugar_button.query_pisugar",
        return_value={"button_shell": "single /home/pi/pi-ambient-synth/scripts/pi_pisugar_button_reseed.sh"},
    ):
        path = get_button_shell("single", {"pisugar": {"enabled": True}})
    assert path == "/home/pi/pi-ambient-synth/scripts/pi_pisugar_button_reseed.sh"


def test_configure_button_shell_calls_set_commands(tmp_path: Path):
    script = tmp_path / "scripts" / "pi_pisugar_button_reseed.sh"
    script.parent.mkdir(parents=True)
    script.touch()
    calls: list[str] = []

    def fake_query(cmd: str, _cfg):
        calls.append(cmd)
        return {cmd.split()[0]: "done"}

    cfg = {"pisugar": {"enabled": True, "socket_path": "/tmp/x.sock"}}
    with patch("pisugar_button.query_pisugar", side_effect=fake_query):
        ok = configure_button_shell("single", script, config=cfg)
    assert ok
    assert len(calls) == 2
    assert calls[0] == f"set_button_shell single {script.resolve()}"
    assert calls[1] == "set_button_enable single 1"


def test_setup_reseed_button_skips_when_disabled(tmp_path: Path):
    script = tmp_path / "scripts" / "pi_pisugar_button_reseed.sh"
    script.parent.mkdir(parents=True)
    script.write_text("#!/bin/sh\ntrue\n", encoding="utf-8")
    cfg = {"pisugar": {"enabled": True, "reseed_on_button": False}}
    with patch("pisugar_button.configure_button_shell") as mock_cfg:
        assert setup_reseed_button(tmp_path, cfg) is False
        mock_cfg.assert_not_called()


def test_setup_reseed_button_registers_script(tmp_path: Path):
    script = tmp_path / "scripts" / "pi_pisugar_button_reseed.sh"
    script.parent.mkdir(parents=True)
    script.write_text("#!/bin/sh\ntrue\n", encoding="utf-8")
    cfg = {"pisugar": {"enabled": True, "reseed_on_button": True}}
    with patch("pisugar_button.configure_button_shell", return_value=True) as mock_cfg:
        assert setup_reseed_button(tmp_path, cfg) is True
        mock_cfg.assert_called_once()
        assert mock_cfg.call_args[0][1] == script.resolve()
