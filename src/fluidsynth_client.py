"""Map Pi Ambient patches → FluidSynth GM programs (reseed = program change)."""

from __future__ import annotations

import logging
from typing import Any

from fluidsynth_engine import FluidSynthEngine
from patch_model import Patch

logger = logging.getLogger(__name__)

# GM programs suited to ambient pads (FluidR3_GM)
DEFAULT_PROGRAMS = (88, 89, 90, 48, 52, 95, 91)


def _fs_cfg(config: dict[str, Any] | None) -> dict[str, Any]:
    if not config:
        return {}
    return config.get("fluidsynth", {})


def patch_to_program(patch: Patch | None, config: dict[str, Any] | None) -> int:
    cfg = _fs_cfg(config)
    programs = tuple(cfg.get("programs", DEFAULT_PROGRAMS))
    if not patch:
        return int(programs[0])
    idx = abs(int(patch.seed)) % len(programs)
    # Slight bias from brightness toward brighter programs
    if patch.brightness > 0.75 and len(programs) > 3:
        idx = (idx + 2) % len(programs)
    return int(programs[idx])


def apply_patch_voice(engine: FluidSynthEngine, patch: Patch | None, config: dict[str, Any]) -> None:
    """Reseed / startup: select GM program and set expression."""
    prog = patch_to_program(patch, config)
    engine.start()
    engine.all_notes_off()
    engine.program_select(prog)
    if patch is not None:
        rev = max(0, min(127, int(patch.reverb_mix * 100)))
        engine.cc(7, int(patch.sustain * 127))
        engine.cc(91, rev)
    logger.info("FluidSynth program=%s patch=%s", prog, patch.summary() if patch else "default")


def open_engine(config: dict[str, Any]) -> FluidSynthEngine:
    eng = FluidSynthEngine(config)
    eng.start()
    return eng
