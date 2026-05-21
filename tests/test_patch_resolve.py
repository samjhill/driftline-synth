"""Tests for default patch resolution."""

from __future__ import annotations

from pathlib import Path

from patch_generator import PatchGenerator
from patch_resolve import resolve_current_patch
from state_store import StateStore


def test_resolve_uses_default_seed_when_no_state_file(tmp_path: Path):
    config = {
        "patch": {"default_seed": 4242, "evolve_enabled": False},
    }
    store = StateStore(tmp_path / "current.json", tmp_path / "fav.json")
    gen = PatchGenerator(config)
    p1 = resolve_current_patch(config, store, gen)
    p2 = resolve_current_patch(config, store, gen)
    assert p1.seed == 4242
    assert p2.seed == 4242
    assert p1.name == p2.name


def test_resolve_loads_saved_patch(tmp_path: Path):
    config = {"patch": {"default_seed": 1}}
    store = StateStore(tmp_path / "current.json", tmp_path / "fav.json")
    gen = PatchGenerator(config)
    first = resolve_current_patch(config, store, gen)
    store.save_current(first)
    second = resolve_current_patch(config, store, gen)
    assert second.seed == first.seed
