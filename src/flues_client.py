"""Map Pi Ambient patches → Flues-Synth MIDI (program change + CCs)."""

from __future__ import annotations

import logging
import time

import mido

from patch_model import Patch

logger = logging.getLogger(__name__)

# Flues docs: channel 1 → mido channel 0.
FLUES_CH = 0

# Avoid program 0/7 (Disyn Echo) and bell/drum interfaces — they sound like cymbals on keys.
PROGRAM_KEYBOARD = 5  # Physical Model: Noise → Interface → Delays → Filter
PROGRAM_FORMANT = 3  # Soft vocal pad
PROGRAM_HYBRID = 6

# CC 24 Interface Type (discrete 0–11). See flues-synth/docs/midi.md
INTERFACE_NAMES = (
    "pluck",
    "hit",
    "reed",
    "flute",
    "brass",
    "bow",
    "bell",
    "drum",
)


def find_flues_output_port() -> str | None:
    for name in mido.get_output_names():
        if "flues" in name.lower():
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


def _interface_cc(name: str) -> int:
    """Discrete interface selector (Reed/Flute/Bow — not Bell/Drum/Hit)."""
    idx = INTERFACE_NAMES.index(name) if name in INTERFACE_NAMES else 2
    return int(round(idx / 11.0 * 127))


def patch_to_program(patch: Patch) -> int:
    """Ambient KeyStep: prefer physical model or formant, never Disyn Echo."""
    if patch.filter_cutoff < 900 and patch.attack > 0.15:
        return PROGRAM_FORMANT
    if patch.noise_level > 0.18 and patch.reverb_mix > 0.55:
        return PROGRAM_HYBRID
    return PROGRAM_KEYBOARD


def _interface_for_patch(patch: Patch) -> str:
    if patch.attack > 0.2 or patch.sustain < 0.45:
        return "bow"
    if patch.brightness > 0.7:
        return "flute"
    return "reed"


def apply_keyboard_voice(port: mido.ports.BaseOutput, patch: Patch | None = None) -> None:
    """Program + CCs tuned for melodic KeyStep (not percussion)."""
    p = patch
    prog = patch_to_program(p) if p else PROGRAM_KEYBOARD
    port.send(mido.Message("program_change", channel=FLUES_CH, program=prog))

    iface = _interface_for_patch(p) if p else "reed"
    attack = p.attack if p else 0.12
    release = p.release if p else 1.8
    cutoff = p.filter_cutoff if p else 2200.0
    res = p.filter_resonance if p else 0.35
    delay_fb = (p.delay_mix * 0.5 if p else 0.22)
    rev_fb = (p.reverb_mix * 0.45 if p else 0.28)

    targets: list[tuple[int, int]] = [
        (24, _interface_cc(iface)),
        (1, _f_to_cc(0.38)),
        (7, _f_to_cc(0.72)),
        (20, _f_to_cc(0.06 if p else 0.08, 0.0, 0.25)),
        (73, _f_to_cc(max(attack, 0.05), 0.02, 0.6)),
        (72, _f_to_cc(max(release, 0.4), 0.2, 3.0)),
        (32, _hz_to_cc(cutoff, 200, 8000)),
        (33, _f_to_cc(min(res, 1.2), 0.1, 1.5)),
        (28, _f_to_cc(delay_fb, 0.05, 0.35)),
        (29, _f_to_cc(rev_fb, 0.05, 0.35)),
        (30, _f_to_cc(0.1, 0.0, 0.25)),
    ]
    for cc, val in targets:
        _cc(port, cc, val)
    logger.info("Flues keyboard voice: program=%s interface=%s", prog, iface)


def apply_patch(port: mido.ports.BaseOutput, patch: Patch, *, morph_steps: int = 0) -> None:
    """Send program + CCs to Flues-Synth."""
    if morph_steps <= 1:
        apply_keyboard_voice(port, patch)
        return

    prog = patch_to_program(patch)
    port.send(mido.Message("program_change", channel=FLUES_CH, program=prog))
    logger.info("Flues program %s for %s", prog, patch.summary())

    iface = _interface_for_patch(patch)
    semi = max(-12, min(12, patch.root_note - 48))
    targets: list[tuple[int, int]] = [
        (24, _interface_cc(iface)),
        (7, _f_to_cc(0.72)),
        (1, _f_to_cc(0.38)),
        (73, _f_to_cc(max(patch.attack, 0.05), 0.02, 0.6)),
        (72, _f_to_cc(max(patch.release, 0.4), 0.2, 3.0)),
        (32, _hz_to_cc(patch.filter_cutoff, 200, 8000)),
        (33, _f_to_cc(min(patch.filter_resonance, 1.2), 0.1, 1.5)),
        (20, _f_to_cc(patch.noise_level * 0.4, 0.0, 0.2)),
        (28, _f_to_cc(patch.delay_mix * 0.45, 0.05, 0.35)),
        (29, _f_to_cc(patch.reverb_mix * 0.4, 0.05, 0.35)),
        (26, int(round((semi + 12) / 24.0 * 127))),
    ]

    for step in range(morph_steps):
        frac = (step + 1) / morph_steps
        for cc, val in targets:
            _cc(port, cc, int(val * frac) if step < morph_steps - 1 else val)
        time.sleep(0.04)


def open_flues_output() -> mido.ports.BaseOutput | None:
    name = find_flues_output_port()
    if not name:
        logger.warning("No Flues MIDI output port (is pi-flues-synth running?)")
        return None
    return mido.open_output(name)
