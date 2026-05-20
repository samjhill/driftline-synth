"""Deterministic topographic patch sigil renderer."""

from __future__ import annotations

import hashlib
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from patch_model import Patch

SCALE_GEOMETRY = {
    "Dorian": 0,
    "Aeolian": 1,
    "Minor Pentatonic": 2,
    "Major Pentatonic": 3,
    "Suspended": 4,
    "Hirajoshi": 5,
    "In Sen": 6,
    "Lydian": 7,
}


def _seed_rng(seed: int, salt: str = "") -> np.random.Generator:
    digest = hashlib.sha256(f"{seed}:{salt}".encode()).digest()
    seed_int = int.from_bytes(digest[:8], "big") % (2**32)
    return np.random.default_rng(seed_int)


class VisualGenerator:
    def __init__(self, config: dict[str, Any]):
        visual = config.get("visual", {})
        eink = config.get("eink", {})
        self.width = eink.get("width", 250)
        self.height = eink.get("height", 122)
        self.margin = visual.get("margin", 8)
        self.line_count_min = visual.get("line_count_min", 9)
        self.line_count_max = visual.get("line_count_max", 28)
        self.include_patch_name = visual.get("include_patch_name", True)
        self.include_scale_name = visual.get("include_scale_name", True)

    def render_patch(self, patch: Patch) -> Image.Image:
        rng = _seed_rng(patch.seed, "visual")
        w, h = self.width, self.height
        img = Image.new("1", (w, h), 1)
        draw = ImageDraw.Draw(img)

        density = patch.texture_density
        line_count = int(
            self.line_count_min
            + density * (self.line_count_max - self.line_count_min)
        )
        thickness = max(1, int(1 + (patch.filter_cutoff / 4200.0) * 2))
        spread = 0.3 + patch.reverb_size * 0.5
        warp = patch.drift_amount * 400.0
        white_bias = patch.brightness
        h_spread = 0.5 + patch.stereo_width * 0.5

        geom = SCALE_GEOMETRY.get(patch.scale_name, patch.seed % 8)
        field = self._height_field(rng, w, h, geom, warp, h_spread)

        levels = np.linspace(
            field.min() + spread * 0.1,
            field.max() - spread * 0.15 * (1 - white_bias),
            line_count,
        )

        m = self.margin
        for level in levels:
            contours = self._contour_segments(field, level, m, w - m, m, h - m)
            for seg in contours:
                draw.line(seg, fill=0, width=thickness)

        self._draw_erosion_paths(draw, rng, w, h, m)
        self._draw_glyph(draw, rng, patch, w, h)
        self._draw_labels(draw, patch, w, h)

        return img

    def _height_field(
        self,
        rng: np.random.Generator,
        w: int,
        h: int,
        geom: int,
        warp: float,
        h_spread: float,
    ) -> np.ndarray:
        xs = np.linspace(-1.2 * h_spread, 1.2 * h_spread, w)
        ys = np.linspace(-1, 1, h)
        X, Y = np.meshgrid(xs, ys)

        if geom % 3 == 0:
            base = np.sin(X * 2.1 + rng.uniform(0, 6)) * np.cos(Y * 1.7 + rng.uniform(0, 6))
        elif geom % 3 == 1:
            base = np.exp(-(X**2 + Y**2) * (0.8 + rng.random() * 0.6))
            base += 0.3 * np.sin(X * 4 + Y * 3)
        else:
            base = np.sin(np.sqrt(X**2 + Y**2) * (3 + geom) + rng.uniform(0, 3))

        n1 = rng.standard_normal((h, w)) * 0.15
        n2 = rng.standard_normal((h // 4 + 1, w // 4 + 1))
        n2_up = np.repeat(np.repeat(n2, 4, axis=0), 4, axis=1)[:h, :w]

        field = base + n1 + n2_up[:h, :w] * 0.25
        if warp > 0:
            phase = rng.uniform(0, 2 * np.pi)
            field += (warp / 500.0) * np.sin(X * 5 + phase) * np.sin(Y * 4)
        return field

    def _contour_segments(
        self,
        field: np.ndarray,
        level: float,
        x0: int,
        y0: int,
        x1: int,
        y1: int,
    ) -> list[tuple[tuple[int, int], tuple[int, int]]]:
        sub = field[y0:y1, x0:x1]
        segments: list[tuple[tuple[int, int], tuple[int, int]]] = []
        h, w = sub.shape
        step = max(2, min(w, h) // 30)
        for y in range(0, h - step, step):
            for x in range(0, w - step, step):
                v00, v10 = sub[y, x], sub[y, min(x + step, w - 1)]
                v01, v11 = sub[min(y + step, h - 1), x], sub[min(y + step, h - 1), min(x + step, w - 1)]
                if (v00 - level) * (v10 - level) < 0:
                    segments.append(((x0 + x, y0 + y), (x0 + x + step, y0 + y)))
                if (v00 - level) * (v01 - level) < 0:
                    segments.append(((x0 + x, y0 + y), (x0 + x, y0 + y + step)))
                if abs(v00 - level) < 0.02 and abs(v11 - level) < 0.02:
                    segments.append(
                        ((x0 + x, y0 + y), (x0 + x + step, y0 + y + step))
                    )
        return segments[:80]

    def _draw_erosion_paths(
        self, draw: ImageDraw.ImageDraw, rng: np.random.Generator, w: int, h: int, m: int
    ) -> None:
        n_paths = int(rng.integers(2, 6))
        for _ in range(n_paths):
            x = int(rng.integers(m, w - m))
            y = int(rng.integers(m, h - m))
            points = [(x, y)]
            for _ in range(int(rng.integers(8, 20))):
                x = int(np.clip(x + rng.integers(-12, 13), m, w - m - 1))
                y = int(np.clip(y + rng.integers(-8, 9), m, h - m - 1))
                points.append((x, y))
            if len(points) > 2:
                draw.line(points, fill=0, width=1)

    def _draw_glyph(
        self, draw: ImageDraw.ImageDraw, rng: np.random.Generator, patch: Patch, w: int, h: int
    ) -> None:
        cx, cy = w // 2, h // 2
        r = 4 + int(patch.texture_density * 4)
        sides = 3 + (patch.seed % 4)
        pts = []
        for i in range(sides):
            ang = 2 * np.pi * i / sides + rng.uniform(-0.2, 0.2)
            px = cx + int(r * np.cos(ang))
            py = cy + int(r * 0.7 * np.sin(ang))
            pts.append((px, py))
        draw.polygon(pts, outline=0, fill=None)
        draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=0)

    def _draw_labels(self, draw: ImageDraw.ImageDraw, patch: Patch, w: int, h: int) -> None:
        try:
            font = ImageFont.load_default()
        except Exception:
            font = None
        y = 2
        if self.include_patch_name:
            draw.text((4, y), patch.name[:22], fill=0, font=font)
            y += 10
        if self.include_scale_name:
            draw.text((4, y), patch.scale_name[:18], fill=0, font=font)
        if patch.evolve_enabled:
            draw.text((w - 36, 2), "~evolve", fill=0, font=font)
