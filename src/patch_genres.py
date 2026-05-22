"""Broad sonic genres for patch generation and reseed."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from patch_model import Patch

# Archetype keys must match patch_generator.ARCHETYPES
GENRES: dict[str, dict[str, Any]] = {
    "all": {
        "label": "All styles",
        "description": "Any archetype — full range of moods",
        "archetypes": None,
    },
    "chill": {
        "label": "Chill",
        "description": "Soft, slow, foggy — gentle pads and long releases",
        "archetypes": ["fog_bank", "mist_shore", "tape_hymn", "veil_light"],
        "post": {
            "filter_cutoff_max": 1600.0,
            "brightness_max": 0.52,
            "attack_min": 0.06,
            "release_min": 1.8,
            "filter_resonance_max": 0.22,
            "delay_mix_max": 0.22,
            "noise_level_max": 0.1,
        },
    },
    "gentle": {
        "label": "Gentle",
        "description": "Very quiet and warm — minimal edge or shimmer",
        "archetypes": ["fog_bank", "mist_shore", "tape_hymn"],
        "post": {
            "filter_cutoff_max": 1200.0,
            "brightness_max": 0.42,
            "attack_min": 0.1,
            "release_min": 2.5,
            "filter_resonance_max": 0.18,
            "delay_mix_max": 0.15,
            "noise_level_max": 0.07,
            "texture_density_max": 0.55,
        },
    },
    "ambient": {
        "label": "Ambient",
        "description": "Wide spaces — reverb-heavy, drifting textures",
        "archetypes": ["fog_bank", "mist_shore", "veil_light", "glass_room"],
        "post": {
            "reverb_mix_min": 0.42,
            "stereo_width_min": 0.6,
            "drift_amount_min": 0.01,
        },
    },
    "deep": {
        "label": "Deep",
        "description": "Low, subdued floor — sub and narrow brightness",
        "archetypes": ["deep_floor", "fog_bank", "tape_hymn"],
        "post": {
            "filter_cutoff_max": 1100.0,
            "sub_level_min": 0.14,
            "brightness_max": 0.45,
            "stereo_width_max": 0.7,
        },
    },
    "bright": {
        "label": "Bright",
        "description": "Glassy and open — more air and shimmer",
        "archetypes": ["glass_room", "veil_light", "mist_shore"],
        "post": {
            "brightness_min": 0.58,
            "filter_cutoff_min": 1400.0,
            "attack_max": 0.25,
        },
    },
    "pulse": {
        "label": "Pulse",
        "description": "More movement — still synth-led, not full techno lead",
        "archetypes": ["glass_room", "mist_shore", "deep_floor"],
        "post": {
            "lfo_rate_min": 0.08,
            "delay_mix_min": 0.18,
            "attack_max": 0.2,
        },
    },
}

DEFAULT_GENRE = "chill"
VALID_RESEED_SCOPES = frozenset({"genre", "all"})


@dataclass(frozen=True)
class GenreInfo:
    id: str
    label: str
    description: str


def list_genres() -> list[GenreInfo]:
    return [
        GenreInfo(id=k, label=v["label"], description=v.get("description", ""))
        for k, v in GENRES.items()
    ]


def genre_archetype_keys(genre_id: str) -> list[str] | None:
    """None means all archetypes."""
    g = GENRES.get(genre_id) or GENRES[DEFAULT_GENRE]
    return g.get("archetypes")


def apply_genre_postprocess(patch: Patch, genre_id: str) -> Patch:
    """Clamp generated patch toward genre character (in-place on new Patch)."""
    g = GENRES.get(genre_id)
    if not g:
        return patch
    post: dict[str, float] = g.get("post") or {}
    d = patch.to_dict()

    def cap(key: str, field: str) -> None:
        if field in post:
            d[key] = min(d[key], post[field])

    def floor(key: str, field: str) -> None:
        if field in post:
            d[key] = max(d[key], post[field])

    cap("filter_cutoff", "filter_cutoff_max")
    cap("brightness", "brightness_max")
    cap("attack", "attack_max")
    floor("attack", "attack_min")
    floor("release", "release_min")
    cap("filter_resonance", "filter_resonance_max")
    cap("delay_mix", "delay_mix_max")
    cap("noise_level", "noise_level_max")
    cap("texture_density", "texture_density_max")
    cap("stereo_width", "stereo_width_max")
    floor("brightness", "brightness_min")
    floor("filter_cutoff", "filter_cutoff_min")
    floor("reverb_mix", "reverb_mix_min")
    floor("stereo_width", "stereo_width_min")
    floor("drift_amount", "drift_amount_min")
    floor("sub_level", "sub_level_min")
    floor("lfo_rate", "lfo_rate_min")
    floor("delay_mix", "delay_mix_min")

    return Patch.from_dict(d)
