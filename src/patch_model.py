"""Typed patch representation for the ambient synth."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, fields
from typing import Any


@dataclass
class Patch:
    seed: int
    name: str
    scale_name: str
    root_note: int
    oscillator_blend: float
    sub_level: float
    noise_level: float
    filter_cutoff: float
    filter_resonance: float
    attack: float
    decay: float
    sustain: float
    release: float
    drift_amount: float
    lfo_rate: float
    lfo_depth: float
    delay_mix: float
    delay_time: float
    reverb_mix: float
    reverb_size: float
    texture_density: float
    stereo_width: float
    brightness: float
    evolve_enabled: bool = False

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Patch:
        valid = {f.name for f in fields(cls)}
        filtered = {k: v for k, v in data.items() if k in valid}
        return cls(**filtered)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)

    @classmethod
    def from_json(cls, text: str) -> Patch:
        return cls.from_dict(json.loads(text))

    def summary(self) -> str:
        return f"{self.name} | {self.scale_name} | seed={self.seed}"
