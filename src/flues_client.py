"""Map Pi Ambient patches → Flues-Synth MIDI (program change + CCs)."""

from __future__ import annotations

import logging

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
    if patch.attack > 0.12 or patch.release > 1.5:
        return "bow"
    if patch.brightness > 0.62:
        return "flute"
    if patch.filter_cutoff < 1400:
        return "bow"
    return "reed"


def _silence_flues(port: mido.ports.BaseOutput) -> None:
    for ch in range(16):
        port.send(mido.Message("control_change", channel=ch, control=123, value=0))


def apply_keyboard_voice(port: mido.ports.BaseOutput, patch: Patch | None = None) -> None:
    """Program 5 (Physical Model) with Flues-native MIDI CC map (see flues-synth boot log)."""
    p = patch
    # Program 0 (Disyn Echo) is cymbal-like on keys — never use for KeyStep.
    prog = PROGRAM_KEYBOARD
    _silence_flues(port)
    port.send(mido.Message("program_change", channel=FLUES_CH, program=prog))

    iface = _interface_for_patch(p) if p else "bow"
    attack = p.attack if p else 0.14
    release = p.release if p else 2.2
    # Softer than fixed 0.55 intensity — stadium lead was too bright/aggressive.
    if p:
        intensity = max(0.28, min(0.62, 0.72 - p.brightness * 0.45))
        filt_fb = max(0.03, min(0.12, 0.14 - p.filter_resonance * 0.15))
        delay_mix = min(0.22, p.delay_mix * 0.28)
        delay2 = min(0.18, p.reverb_mix * 0.2)
    else:
        intensity = 0.38
        filt_fb = 0.05
        delay_mix = 0.08
        delay2 = 0.06

    # Program 5 slider map (MIDI CC → internal), from Flues-Synth v0.1.0 logs:
    # Dly1=73, Dly2=72, FiltFB=28, Interface=30, Intensity=74, Tuning=71, Ratio=1, Attack=27, Release=7
    targets: list[tuple[int, int]] = [
        (30, _interface_cc(iface)),
        (74, _f_to_cc(intensity)),
        (27, _f_to_cc(max(attack, 0.05), 0.02, 0.5)),
        (7, _f_to_cc(max(release, 0.5), 0.3, 4.0)),
        (73, _f_to_cc(delay_mix, 0.0, 0.3)),
        (72, _f_to_cc(delay2, 0.0, 0.25)),
        (28, _f_to_cc(filt_fb, 0.0, 0.15)),
        (71, _f_to_cc(0.5)),
        (1, _f_to_cc(0.35, 0.1, 0.6)),
    ]
    for cc, val in targets:
        _cc(port, cc, val)
    logger.info(
        "Flues keyboard voice: program=%s interface=%s patch=%s",
        prog,
        iface,
        p.summary() if p else "(default)",
    )


def apply_patch(port: mido.ports.BaseOutput, patch: Patch, *, morph_steps: int = 0) -> None:
    """Send program + CCs to Flues-Synth (morph_steps ignored — instant voice update)."""
    del morph_steps
    apply_keyboard_voice(port, patch)


def forward_pitch_bend(port: mido.ports.BaseOutput, pitch: int, channel: int = 0) -> None:
    """Pass KeyStep pitch strip → Flues (channel 0 voice)."""
    port.send(mido.Message("pitchwheel", channel=FLUES_CH, pitch=int(pitch)))


def forward_mod_wheel(port: mido.ports.BaseOutput, value: int) -> None:
    """Mod wheel → filter brightness (program 5: CC 28 FiltFB)."""
    v = max(0, min(127, int(value)))
    # Keep a little headroom so silence is not harsh; full mod opens filter.
    fb = int(8 + (v / 127.0) * 100)
    _cc(port, 28, fb)


def open_flues_output() -> mido.ports.BaseOutput | None:
    name = find_flues_output_port()
    if not name:
        logger.warning("No Flues MIDI output port (is pi-flues-synth running?)")
        return None
    return mido.open_output(name)
