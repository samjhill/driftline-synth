"""E-ink status screens for deploy and system events."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from PIL import Image, ImageDraw, ImageFont


# Visual phases (monochrome, high contrast for 2.13" panel)
PHASE_LABELS = {
    "boot": "BOOT",
    "network": "NET",
    "wifi": "WIFI",
    "audio": "AUDIO",
    "synth": "SYNTH",
    "midi": "MIDI",
    "checking": "SYNC",
    "download": "PULL",
    "install": "INSTALL",
    "restart": "RESTART",
    "ready": "READY",
    "playing": "PLAYING",
    "failed": "ERROR",
    "idle": "IDLE",
}


class StatusDisplay:
    def __init__(self, config: dict[str, Any]):
        eink = config.get("eink", {})
        self.width = eink.get("width", 250)
        self.height = eink.get("height", 122)
        self.margin = 10

    def _font(self, size: str = "default"):
        try:
            if size == "large":
                return ImageFont.load_default()
            return ImageFont.load_default()
        except Exception:
            return None

    def render(
        self,
        phase: str,
        title: str,
        subtitle: str = "",
        detail: str = "",
        progress: float | None = None,
        step: int | None = None,
        total_steps: int | None = None,
    ) -> Image.Image:
        w, h = self.width, self.height
        img = Image.new("1", (w, h), 1)
        draw = ImageDraw.Draw(img)
        font = self._font()
        m = self.margin

        badge = PHASE_LABELS.get(phase, phase.upper()[:8])
        draw.rectangle((m, m, m + 52, m + 14), outline=0, fill=0)
        draw.text((m + 4, m + 2), badge, fill=1, font=font)

        y = m + 22
        for line in (title, subtitle, detail):
            if not line:
                continue
            text = line[:28]
            draw.text((m, y), text, fill=0, font=font)
            y += 13

        if step is not None and total_steps is not None and total_steps > 0:
            step = max(1, min(step, total_steps))
            if progress is None:
                progress = step / total_steps
            draw.text((w - m - 36, m + 2), f"{step}/{total_steps}", fill=0, font=font)

        ts = datetime.now().strftime("%H:%M:%S")
        draw.line((m, h - 22, w - m, h - 22), fill=0, width=1)
        draw.text((m, h - 18), ts, fill=0, font=font)

        if progress is not None:
            progress = max(0.0, min(1.0, progress))
            bar_y = h - 32
            bar_w = w - 2 * m
            draw.rectangle((m, bar_y, m + bar_w, bar_y + 6), outline=0, fill=1)
            fill_w = int(bar_w * progress)
            if fill_w > 0:
                draw.rectangle((m, bar_y, m + fill_w, bar_y + 6), fill=0)

        # Corner ticks for "activity"
        if phase in ("boot", "network", "wifi", "audio", "synth", "midi", "checking", "download", "install", "restart"):
            cx = w - m - 8
            cy = m + 6
            draw.rectangle((cx, cy, cx + 6, cy + 6), outline=0, fill=0)

        return img
