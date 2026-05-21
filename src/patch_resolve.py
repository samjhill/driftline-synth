"""Resolve which patch to load — shared by synth and LAN monitor."""

from __future__ import annotations

from typing import Any

from patch_generator import PatchGenerator
from patch_model import Patch
from state_store import StateStore


def resolve_current_patch(
    config: dict[str, Any],
    store: StateStore,
    generator: PatchGenerator | None = None,
) -> Patch:
    """Load saved patch, or generate default from config (stable default_seed)."""
    saved = store.load_current()
    if saved:
        return saved

    gen = generator or PatchGenerator(config)
    patch_cfg = config.get("patch", {})
    evolve = patch_cfg.get("evolve_enabled", False)
    seed = patch_cfg.get("seed")
    if seed is None:
        seed = patch_cfg.get("default_seed", 1001)
    return gen.generate(seed=int(seed), evolve_enabled=evolve)
