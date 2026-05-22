"""Genre bias and prefs tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from config_loader import load_config
from patch_generator import PatchGenerator
from patch_prefs import PatchPrefs, load_patch_prefs, save_patch_prefs


@pytest.fixture
def generator(tmp_path):
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    scales = Path(__file__).resolve().parent.parent / "config" / "scales.yaml"
    return PatchGenerator(config, scales_path=scales)


def test_chill_genre_softens_patch(generator):
    raw = generator.generate(seed=999, genre="all", reseed_scope="all")
    chill = generator.generate(seed=999, genre="chill", reseed_scope="genre")
    assert chill.brightness <= raw.brightness or chill.filter_cutoff <= raw.filter_cutoff
    assert chill.release >= raw.release or chill.attack >= raw.attack


def test_reseed_scope_all_skips_genre_post(generator):
    scoped = generator.generate(seed=4242, genre="chill", reseed_scope="genre")
    free = generator.generate(seed=4242, genre="chill", reseed_scope="all")
    assert "Chill" in scoped.name
    assert "Chill" not in free.name


def test_gentle_genre_caps_brightness(generator):
    p = generator.generate(seed=77, genre="gentle", reseed_scope="genre")
    assert p.brightness <= 0.42
    assert p.filter_cutoff <= 1200.0


def test_patch_prefs_roundtrip(tmp_path):
    config = {
        "app": {"marker_dir": str(tmp_path)},
        "patch": {"default_genre": "gentle", "default_reseed_scope": "genre"},
    }
    save_patch_prefs(config, PatchPrefs(genre="ambient", reseed_scope="all"))
    loaded = load_patch_prefs(config)
    assert loaded.genre == "ambient"
    assert loaded.reseed_scope == "all"
