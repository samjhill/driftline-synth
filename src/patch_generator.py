"""Curated patch randomization — scene archetypes + variation."""

from __future__ import annotations

import random
from pathlib import Path
from typing import Any

import yaml

from patch_genres import DEFAULT_GENRE, GENRES, apply_genre_postprocess, genre_archetype_keys
from patch_model import Patch

# Archetype defines biased ranges (lo, hi) per parameter — "same world, different weather"
ARCHETYPES: dict[str, dict[str, Any]] = {
    "fog_bank": {
        "label": "Fog Bank",
        "scales": ["Aeolian", "Dorian", "Minor Pentatonic"],
        "ranges": {
            "filter_cutoff": (450.0, 1200.0),
            "release": (2.0, 6.5),
            "reverb_mix": (0.45, 0.72),
            "reverb_size": (0.75, 0.95),
            "noise_level": (0.06, 0.18),
            "brightness": (0.2, 0.45),
            "drift_amount": (0.008, 0.025),
        },
    },
    "glass_room": {
        "label": "Glass Room",
        "scales": ["Lydian", "Major Pentatonic", "Suspended"],
        "ranges": {
            "filter_cutoff": (2200.0, 4200.0),
            "attack": (0.005, 0.12),
            "release": (0.4, 1.8),
            "delay_mix": (0.18, 0.42),
            "brightness": (0.65, 0.95),
            "reverb_mix": (0.22, 0.45),
        },
    },
    "tape_hymn": {
        "label": "Tape Hymn",
        "scales": ["Minor Pentatonic", "Hirajoshi", "In Sen"],
        "ranges": {
            "oscillator_blend": (0.35, 0.65),
            "noise_level": (0.08, 0.18),
            "lfo_rate": (0.04, 0.12),
            "drift_amount": (0.012, 0.025),
            "texture_density": (0.5, 0.9),
            "reverb_mix": (0.35, 0.6),
        },
    },
    "deep_floor": {
        "label": "Deep Floor",
        "scales": ["Aeolian", "Dorian"],
        "ranges": {
            "sub_level": (0.18, 0.35),
            "filter_cutoff": (450.0, 900.0),
            "release": (1.5, 4.0),
            "stereo_width": (0.4, 0.65),
            "brightness": (0.2, 0.4),
            "texture_density": (0.35, 0.7),
        },
    },
    "mist_shore": {
        "label": "Mist Shore",
        "scales": ["Dorian", "Suspended", "Aeolian"],
        "ranges": {
            "filter_cutoff": (800.0, 2000.0),
            "reverb_mix": (0.4, 0.65),
            "delay_mix": (0.12, 0.32),
            "lfo_depth": (0.08, 0.22),
            "stereo_width": (0.55, 0.95),
        },
    },
    "veil_light": {
        "label": "Veil Light",
        "scales": ["Lydian", "Major Pentatonic", "Dorian"],
        "ranges": {
            "filter_cutoff": (1600.0, 3200.0),
            "attack": (0.02, 0.35),
            "release": (1.0, 3.5),
            "reverb_size": (0.6, 0.85),
            "brightness": (0.55, 0.85),
            "texture_density": (0.2, 0.55),
        },
    },
}

PATCH_FLAVOR = [
    "Driftline", "Pale", "Still", "Quiet", "Soft", "Hollow", "Silver", "Low", "Dusk",
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

    def _pick_archetype(
        self, rng: random.Random, *, allowed: list[str] | None = None
    ) -> tuple[str, dict[str, Any]]:
        keys = allowed if allowed else list(ARCHETYPES.keys())
        keys = [k for k in keys if k in ARCHETYPES]
        if not keys:
            keys = list(ARCHETYPES.keys())
        key = rng.choice(keys)
        return key, ARCHETYPES[key]

    def _pick_param(
        self, rng: random.Random, key: str, archetype_ranges: dict[str, tuple[float, float]]
    ) -> float:
        if key in archetype_ranges:
            lo, hi = archetype_ranges[key]
        else:
            lo, hi = PARAM_RANGES[key]
        return lo + rng.random() * (hi - lo)

    def generate(
        self,
        seed: int | None = None,
        evolve_enabled: bool = False,
        *,
        genre: str | None = None,
        reseed_scope: str = "genre",
    ) -> Patch:
        if seed is None:
            seed = random.randint(0, 2**31 - 1)
        rng = random.Random(seed)
        genre_id = genre or DEFAULT_GENRE
        use_genre = reseed_scope != "all" and genre_id != "all"
        allowed = genre_archetype_keys(genre_id) if use_genre else None
        _arch_key, archetype = self._pick_archetype(rng, allowed=allowed)
        arch_ranges = archetype.get("ranges", {})
        arch_scales = archetype.get("scales", [])
        all_scales = self._scale_choices()
        if arch_scales:
            scale = rng.choice([s for s in all_scales if s["name"] in arch_scales] or all_scales)
        else:
            scale = rng.choice(all_scales)

        flavor = rng.choice(PATCH_FLAVOR)
        name = f"{archetype['label']} · {flavor}"
        if rng.random() < 0.35:
            name = f"{name} {rng.randint(2, 99)}"

        def pick(key: str) -> float:
            return self._pick_param(rng, key, arch_ranges)

        if _arch_key == "glass_room":
            delay_time = rng.choice((0.25, 0.375))
        else:
            delay_time = rng.choice(DELAY_TIMES)

        patch = Patch(
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
            delay_time=delay_time,
            reverb_mix=pick("reverb_mix"),
            reverb_size=pick("reverb_size"),
            texture_density=pick("texture_density"),
            stereo_width=pick("stereo_width"),
            brightness=pick("brightness"),
            evolve_enabled=evolve_enabled,
        )
        if use_genre:
            patch = apply_genre_postprocess(patch, genre_id)
            g = GENRES.get(genre_id) or {}
            tag = g.get("label", genre_id)
            if tag not in patch.name:
                patch = Patch.from_dict({**patch.to_dict(), "name": f"{patch.name} · {tag}"})
        return patch

    def morph_from(
        self,
        base: Patch,
        seed: int,
        evolve_enabled: bool | None = None,
        *,
        genre: str | None = None,
        reseed_scope: str = "genre",
    ) -> Patch:
        rng = random.Random(seed)
        new = self.generate(
            seed=seed,
            evolve_enabled=evolve_enabled if evolve_enabled is not None else base.evolve_enabled,
            genre=genre,
            reseed_scope=reseed_scope,
        )
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
