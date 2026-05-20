"""State store persistence tests."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from patch_generator import PatchGenerator
from patch_model import Patch
from state_store import StateStore


@pytest.fixture
def store(tmp_path):
    return StateStore(tmp_path / "current.json", tmp_path / "favorites.json")


@pytest.fixture
def sample_patch():
    return Patch(
        seed=99,
        name="Test",
        scale_name="Dorian",
        root_note=48,
        oscillator_blend=0.5,
        sub_level=0.1,
        noise_level=0.05,
        filter_cutoff=1200.0,
        filter_resonance=0.2,
        attack=0.1,
        decay=0.5,
        sustain=0.6,
        release=2.0,
        drift_amount=0.01,
        lfo_rate=0.1,
        lfo_depth=0.1,
        delay_mix=0.2,
        delay_time=0.5,
        reverb_mix=0.4,
        reverb_size=0.7,
        texture_density=0.5,
        stereo_width=0.7,
        brightness=0.6,
    )


def test_save_and_load(store, sample_patch):
    store.save_current(sample_patch)
    loaded = store.load_current()
    assert loaded is not None
    assert loaded.seed == sample_patch.seed
    assert loaded.name == sample_patch.name


def test_favorites_append(store, sample_patch):
    store.add_favorite(sample_patch)
    store.add_favorite(sample_patch)
    favs = store.load_favorites()
    assert len(favs) == 1


def test_recall_last_favorite(store, sample_patch):
    store.add_favorite(sample_patch)
    recalled = store.load_last_favorite()
    assert recalled is not None
    assert recalled.seed == 99


def test_atomic_write_not_corrupt(store, sample_patch, tmp_path):
    store.save_current(sample_patch)
    with open(store.state_path) as f:
        data = json.load(f)
    assert data["seed"] == 99
