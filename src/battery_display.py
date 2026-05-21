"""Monochrome PiSugar battery badge for the 2.13\" e-ink panel."""

from __future__ import annotations

from typing import TYPE_CHECKING

from PIL import Image, ImageDraw, ImageFont

if TYPE_CHECKING:
    from pisugar_battery import BatterySnapshot


def _level_tier(percent: int) -> str:
    if percent <= 15:
        return "low"
    if percent <= 35:
        return "mid"
    return "high"


def draw_battery_badge(
    draw: ImageDraw.ImageDraw,
    *,
    x: int,
    y: int,
    percent: int,
    charging: bool = False,
    width: int = 250,
) -> None:
    """Draw a compact battery gauge + large percent in the top-right."""
    pct = max(0, min(100, int(percent)))
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None

    tier = _level_tier(pct)
    body_w, body_h = 34, 12
    cap_w = 3
    bx, by = x, y

    # Outer frame (inverted cap reads clearly on e-ink)
    draw.rounded_rectangle(
        (bx, by, bx + body_w, by + body_h),
        radius=2,
        outline=0,
        fill=1,
    )
    draw.rectangle(
        (bx + body_w, by + 3, bx + body_w + cap_w, by + body_h - 3),
        fill=0,
    )

    inner_l = bx + 2
    inner_t = by + 2
    inner_r = bx + body_w - 2
    inner_b = by + body_h - 2
    inner_w = inner_r - inner_l
    segments = 4
    seg_w = max(1, inner_w // segments)
    filled_segs = max(0, min(segments, (pct * segments + 99) // 100))

    for i in range(segments):
        sx0 = inner_l + i * seg_w
        sx1 = inner_l + (i + 1) * seg_w - 1 if i < segments - 1 else inner_r
        if i < filled_segs:
            fill = 0
        else:
            fill = 1
        draw.rectangle((sx0, inner_t, sx1, inner_b), fill=fill)

    # Low-battery hatch on empty segments
    if tier == "low" and filled_segs < segments:
        for i in range(filled_segs, segments):
            sx0 = inner_l + i * seg_w
            sx1 = inner_l + (i + 1) * seg_w - 1 if i < segments - 1 else inner_r
            for yy in range(inner_t, inner_b, 2):
                draw.line([(sx0, yy), (sx1, yy)], fill=0, width=1)

    pct_text = f"{pct}%"
    tx = bx + body_w + cap_w + 5
    ty = by - 1
    draw.text((tx, ty), pct_text, fill=0, font=font)

    if charging:
        cx = bx - 8
        cy = by + 2
        draw.line([(cx, cy + 6), (cx + 3, cy), (cx + 3, cy + 4), (cx + 7, cy + 4)], fill=0)
        draw.line([(cx + 3, cy + 4), (cx, cy + 10), (cx, cy + 6)], fill=0)


def overlay_battery(
    image: Image.Image,
    snapshot: BatterySnapshot | None,
    *,
    margin: int = 6,
) -> Image.Image:
    if snapshot is None or not snapshot.available:
        return image
    pct = snapshot.display_percent
    if pct is None:
        return image
    draw = ImageDraw.Draw(image)
    x = image.width - margin - 72
    y = margin
    draw_battery_badge(
        draw,
        x=x,
        y=y,
        percent=pct,
        charging=bool(snapshot.charging),
        width=image.width,
    )
    return image
