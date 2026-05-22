"""Flues CC mapping tests."""

from __future__ import annotations

from patch_model import Patch
from flues_client import _feedback_levels, _f_to_cc


def test_feedback_capped_low():
    patch = Patch(
        seed=1,
        name="test",
        scale_name="Dorian",
        root_note=48,
        oscillator_blend=0.5,
        sub_level=0.1,
        noise_level=0.15,
        filter_cutoff=2000.0,
        filter_resonance=0.4,
        attack=0.1,
        decay=0.5,
        sustain=0.6,
        release=2.0,
        drift_amount=0.01,
        lfo_rate=0.1,
        lfo_depth=0.1,
        delay_mix=0.4,
        delay_time=0.5,
        reverb_mix=0.7,
        reverb_size=0.8,
        texture_density=0.5,
        stereo_width=0.7,
        brightness=0.6,
    )
    cfg = {
        "max_delay1_feedback": 0.05,
        "max_delay2_feedback": 0.04,
        "max_filter_feedback": 0.03,
    }
    d1, d2, fb = _feedback_levels(patch, cfg)
    assert d1 <= 0.05
    assert d2 <= 0.04
    assert fb <= 0.03
    assert _f_to_cc(d1) < 20  # well below default 0.2 → ~25 CC
