"""Battery badge rendering."""

from __future__ import annotations

from pathlib import Path

from battery_display import draw_battery_badge, overlay_battery
from config_loader import load_config
from pisugar_battery import BatterySnapshot
from PIL import Image, ImageDraw
from status_display import StatusDisplay


def test_overlay_battery_on_status_image():
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    snap = BatterySnapshot(
        percent=72,
        voltage_v=4.1,
        charging=True,
        plugged=True,
        available=True,
        label="72%",
    )
    img = StatusDisplay(config).render("ready", "OK", "", "", battery=snap)
    assert img.mode == "1"
    # Badge region should include some black pixels vs without battery
    plain = StatusDisplay(config).render("ready", "OK", "", "")
    assert list(img.getdata()) != list(plain.getdata())


def test_draw_battery_badge_levels():
    img = Image.new("1", (80, 30), 1)
    draw = ImageDraw.Draw(img)
    draw_battery_badge(draw, x=4, y=4, percent=12, charging=False)
    draw_battery_badge(draw, x=4, y=16, percent=88, charging=True)
    assert img.mode == "1"
