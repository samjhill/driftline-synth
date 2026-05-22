"""Flues CC mapping tests."""

from __future__ import annotations

from patch_model import Patch
from flues_client import (
    _feedback_levels,
    _f_to_cc,
    keyboard_program,
    keystep_to_flues_note,
    PROGRAM_FORMANT,
    PROGRAM_PHYSICAL,
)


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
        "max_delay1_feedback": 0.012,
        "max_delay2_feedback": 0.01,
        "max_filter_feedback": 0.008,
        "min_noise_level": 0.035,
        "max_noise_level": 0.055,
    }
    d1, d2, fb = _feedback_levels(patch, cfg)
    assert d1 <= 0.012
    assert d2 <= 0.01
    assert fb <= 0.008
    assert _f_to_cc(d1) < 20  # well below default 0.2 → ~25 CC


def test_default_keyboard_program_is_physical():
    assert keyboard_program(None, {}) == PROGRAM_PHYSICAL
    assert keyboard_program(None, {"keyboard_program": "formant"}) == PROGRAM_FORMANT


def test_keystep_mpe_note_fold():
    assert keystep_to_flues_note(80, 14) < 80
    assert keystep_to_flues_note(60, 0) == 60
