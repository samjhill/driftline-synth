"""Patch generator unit tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from config_loader import load_config
from patch_generator import DELAY_TIMES, PARAM_RANGES, PatchGenerator


@pytest.fixture
def generator():
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    scales = Path(__file__).resolve().parent.parent / "config" / "scales.yaml"
    return PatchGenerator(config, scales_path=scales)


def test_same_seed_same_patch(generator):
    a = generator.generate(seed=12345)
    b = generator.generate(seed=12345)
    assert a.to_dict() == b.to_dict()


def test_different_seed_different_patch(generator):
    a = generator.generate(seed=1)
    b = generator.generate(seed=2)
    assert a.seed != b.seed
    assert a.filter_cutoff != b.filter_cutoff or a.name != b.name


def test_ranges_within_curated_bounds(generator):
    for seed in range(20):
        patch = generator.generate(seed=seed * 7919)
        errors = PatchGenerator.validate_ranges(patch)
        assert errors == [], f"seed={seed}: {errors}"


def test_delay_time_quantized(generator):
    for seed in range(10):
        patch = generator.generate(seed=seed)
        assert patch.delay_time in DELAY_TIMES


def test_param_ranges_defined():
    assert "filter_cutoff" in PARAM_RANGES
    assert PARAM_RANGES["filter_cutoff"] == (450.0, 4200.0)
