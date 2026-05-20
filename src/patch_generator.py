"""Curated patch randomization — same world, different weather."""

from __future__ import annotations

import random
from pathlib import Path
from typing import Any

import yaml

from patch_model import Patch

PATCH_NAMES = [
    "Driftline",
    "Mist Shore",
    "Low Tide",
    "Pale Horizon",
    "Still Air",
    "Glass Fog",
    "Quiet Ridge",
    "Soft Meridian",
    "Veil Light",
    "Dusk Field",
    "Hollow Bay",
    "Silver Haze",
]

DELAY_TIMES = (0.25, 0.375, 0.5, 0.75)

PARAM_RANGES: dict[str, tuple[float, float]] = {
    "oscillator_blend": (0.15, 0.85),
    "sub_level": (0.0, 0.35),
    "noise_level": (0.0, 0.18),
    "filter_cutoff": (450.0, 4200.0),
    "filter_resonance": (0.08, 0.45),
    "attack": (0.005, 0.8),
    "decay": (0.1, 2.5),
    "sustain": (0.35, 0.85),
    "release": (0.4, 6.5),
    "drift_amount": (0.001, 0.025),
    "lfo_rate": (0.02, 0.35),
    "lfo_depth": (0.02, 0.22),
    "delay_mix": (0.08, 0.42),
    "reverb_mix": (0.22, 0.72),
    "reverb_size": (0.55, 0.95),
    "texture_density": (0.1, 0.9),
    "stereo_width": (0.4, 1.0),
    "brightness": (0.2, 0.95),
}

ROOT_NOTES = (36, 38, 40, 41, 43, 45, 48)


class PatchGenerator:
    def __init__(self, config: dict[str, Any], scales_path: Path | None = None):
        self._config = config
        patch_cfg = config.get("patch", {})
        self._scale_family = patch_cfg.get("default_scale_family", "ambient_modal")
        if scales_path is None:
            scales_path = Path(__file__).resolve().parent.parent / "config" / "scales.yaml"
        with open(scales_path) as f:
            self._scales_data = yaml.safe_load(f)

    def _scale_choices(self) -> list[dict[str, Any]]:
        family = self._scales_data.get(self._scale_family, [])
        if not family:
            return [{"name": "Dorian", "intervals": [0, 2, 3, 5, 7, 9, 10]}]
        return family

    def generate(self, seed: int | None = None, evolve_enabled: bool = False) -> Patch:
        if seed is None:
            seed = random.randint(0, 2**31 - 1)
        rng = random.Random(seed)
        scale = rng.choice(self._scale_choices())
        name = rng.choice(PATCH_NAMES)
        if rng.random() < 0.4:
            name = f"{name} {rng.randint(2, 99)}"

        def pick(key: str) -> float:
            lo, hi = PARAM_RANGES[key]
            return lo + rng.random() * (hi - lo)

        return Patch(
            seed=seed,
            name=name,
            scale_name=scale["name"],
            root_note=rng.choice(ROOT_NOTES),
            oscillator_blend=pick("oscillator_blend"),
            sub_level=pick("sub_level"),
            noise_level=pick("noise_level"),
            filter_cutoff=pick("filter_cutoff"),
            filter_resonance=pick("filter_resonance"),
            attack=pick("attack"),
            decay=pick("decay"),
            sustain=pick("sustain"),
            release=pick("release"),
            drift_amount=pick("drift_amount"),
            lfo_rate=pick("lfo_rate"),
            lfo_depth=pick("lfo_depth"),
            delay_mix=pick("delay_mix"),
            delay_time=rng.choice(DELAY_TIMES),
            reverb_mix=pick("reverb_mix"),
            reverb_size=pick("reverb_size"),
            texture_density=pick("texture_density"),
            stereo_width=pick("stereo_width"),
            brightness=pick("brightness"),
            evolve_enabled=evolve_enabled,
        )

    def morph_from(self, base: Patch, seed: int, evolve_enabled: bool | None = None) -> Patch:
        """Generate a related patch — keeps some character from base."""
        rng = random.Random(seed)
        new = self.generate(seed=seed, evolve_enabled=evolve_enabled if evolve_enabled is not None else base.evolve_enabled)
        if rng.random() < 0.5:
            new.root_note = base.root_note
        if rng.random() < 0.35:
            new.scale_name = base.scale_name
        return new

    @staticmethod
    def validate_ranges(patch: Patch) -> list[str]:
        errors: list[str] = []
        for key, (lo, hi) in PARAM_RANGES.items():
            val = getattr(patch, key, None)
            if val is None:
                continue
            if not (lo <= val <= hi):
                errors.append(f"{key}={val} outside [{lo}, {hi}]")
        if patch.delay_time not in DELAY_TIMES:
            errors.append(f"delay_time={patch.delay_time} not in allowed set")
        return errors
