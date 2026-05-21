"""Map Pi Ambient patches → Flues-Synth MIDI (program change + CCs)."""

from __future__ import annotations

import logging
import time
from typing import Any

import mido

from patch_model import Patch

logger = logging.getLogger(__name__)

# Flues listens on MIDI channel 1 in docs → mido channel 0.
FLUES_CH = 0

# Ambient-friendly programs (see flues-synth/docs/midi.md).
PROGRAM_AMBIENT = 5  # Physical Model
PROGRAM_FORMANT = 3
PROGRAM_HYBRID = 6
PROGRAM_DISYN = 0


def find_flues_output_port() -> str | None:
    for name in mido.get_output_names():
        low = name.lower()
        if "flues" in low:
            return name
    return None


def _cc(port: mido.ports.BaseOutput, control: int, value: int) -> None:
    port.send(mido.Message("control_change", channel=FLUES_CH, control=control, value=value))


def _f_to_cc(value: float, lo: float = 0.0, hi: float = 1.0) -> int:
    v = max(lo, min(hi, float(value)))
    return int(round((v - lo) / (hi - lo) * 127))


def _hz_to_cc(hz: float, lo: float, hi: float) -> int:
    import math

    hz = max(lo, min(hi, float(hz)))
    return int(round(127 * math.log(hz / lo) / math.log(hi / lo)))


def patch_to_program(patch: Patch) -> int:
    """Pick a Flues program from patch character."""
    if patch.noise_level > 0.12 and patch.filter_cutoff < 1200:
        return PROGRAM_FORMANT
    if patch.texture_density > 0.55 or patch.reverb_mix > 0.5:
        return PROGRAM_HYBRID
    if patch.oscillator_blend > 0.6:
        return PROGRAM_DISYN
    return PROGRAM_AMBIENT


def apply_patch(port: mido.ports.BaseOutput, patch: Patch, *, morph_steps: int = 0) -> None:
    """Send program + CCs to Flues-Synth."""
    prog = patch_to_program(patch)
    port.send(mido.Message("program_change", channel=FLUES_CH, program=prog))
    logger.info("Flues program %s for %s", prog, patch.summary())

    semi = max(-12, min(12, patch.root_note - 48))
    targets: list[tuple[int, int]] = [
        (7, _f_to_cc(0.88)),
        (73, _f_to_cc(patch.attack, 0.001, 1.0)),
        (72, _f_to_cc(patch.release, 0.01, 3.0)),
        (32, _hz_to_cc(patch.filter_cutoff, 80, 12000)),
        (33, _f_to_cc(patch.filter_resonance, 0.1, 2.5)),
        (20, _f_to_cc(patch.noise_level, 0.0, 0.4)),
        (28, _f_to_cc(patch.delay_mix * 0.85, 0.0, 0.55)),
        (29, _f_to_cc(patch.reverb_mix * 0.7, 0.0, 0.5)),
        (1, _f_to_cc(0.35 + patch.texture_density * 0.35, 0.0, 1.0)),
        (26, int(round((semi + 12) / 24.0 * 127))),
    ]

    steps = max(1, morph_steps)
    for step in range(steps):
        frac = (step + 1) / steps
        for cc, val in targets:
            _cc(port, cc, int(val * frac) if step < steps - 1 else val)
        if morph_steps > 1:
            time.sleep(0.04)


def open_flues_output() -> mido.ports.BaseOutput | None:
    name = find_flues_output_port()
    if not name:
        logger.warning("No Flues MIDI output port (is pi-flues-synth running?)")
        return None
    return mido.open_output(name)
