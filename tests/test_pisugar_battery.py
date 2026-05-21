"""PiSugar API parsing (no hardware)."""

from __future__ import annotations

from pisugar_battery import parse_pisugar_line, read_battery_snapshot


def test_parse_battery_line():
    assert parse_pisugar_line("battery: 87") == ("battery", 87)
    assert parse_pisugar_line("battery_v: 4.12") == ("battery_v", 4.12)
    assert parse_pisugar_line("battery_charging: true") == (
        "battery_charging",
        True,
    )


def test_read_battery_disabled():
    snap = read_battery_snapshot({"pisugar": {"enabled": False}})
    assert not snap.available
    assert snap.percent is None
