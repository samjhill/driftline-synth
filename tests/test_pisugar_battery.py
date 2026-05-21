"""PiSugar API parsing (no hardware)."""

from __future__ import annotations

from pisugar_battery import BatterySnapshot, parse_pisugar_line, read_battery_snapshot


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


def test_shows_charging_indicator():
    charging = BatterySnapshot(
        percent=74, voltage_v=4.1, charging=True, plugged=True,
        available=True, label="74% charging",
    )
    assert charging.shows_charging_indicator
    idle = BatterySnapshot(
        percent=74, voltage_v=4.1, charging=False, plugged=False,
        available=True, label="74%",
    )
    assert not idle.shows_charging_indicator
    plugged_only = BatterySnapshot(
        percent=74, voltage_v=4.1, charging=None, plugged=True,
        available=True, label="74%",
    )
    assert plugged_only.shows_charging_indicator
