"""Status display renderer tests."""

from __future__ import annotations

from pathlib import Path

from config_loader import load_config
from status_display import StatusDisplay


def test_render_status_image():
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    img = StatusDisplay(config).render(
        "download", "Pulling update", "311c037", "samjhill/driftline-synth"
    )
    assert img.size == (250, 122)
    assert img.mode == "1"


def test_boot_phase_label():
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    img = StatusDisplay(config).render("boot", "Booting", "Pi Ambient Synth", "power on")
    assert img.mode == "1"


def test_render_phases_distinct():
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    r = StatusDisplay(config)
    a = list(r.render("install", "Installing", "abc", "").getdata())
    b = list(r.render("ready", "Update complete", "abc", "").getdata())
    assert a != b
