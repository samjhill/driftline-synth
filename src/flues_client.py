"""Map Pi Ambient patches → Flues-Synth MIDI (program change + CCs)."""

from __future__ import annotations

import logging
from typing import Any

import mido

from patch_model import Patch

logger = logging.getLogger(__name__)

# Flues docs: channel 1 → mido channel 0.
FLUES_CH = 0

PROGRAM_KEYBOARD = 5  # Physical Model: Noise → Interface → Delays → Filter

# Program 5 hardware-slider CCs (see flues-synth/docs/PROGRAM_CHANGE.md).
# Sliders 1–2 are delay FEEDBACK (echo), not mix/send.
PM_DELAY1_FB = 73  # → internal CC 28
PM_DELAY2_FB = 72  # → internal CC 29
PM_FILTER_FB = 28  # → internal CC 30
PM_INTERFACE = 30  # → internal CC 24
PM_INTENSITY = 74  # → internal CC 1
PM_TUNING = 71  # → internal CC 26
PM_RATIO = 1  # → internal CC 27
PM_ATTACK = 27  # → internal CC 73
PM_RELEASE = 7  # → internal CC 72

# Direct engine CCs (not remapped by sliders).
CC_NOISE_LEVEL = 20
CC_MASTER_GAIN = 7  # only when not using PM_RELEASE on same CC — prog 5 uses 7 as release slider
CC_FILTER_FREQ = 32
CC_FILTER_Q = 33
CC_FILTER_SHAPE = 34

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


def _hz_to_cc(hz: float, lo: float = 80.0, hi: float = 8000.0) -> int:
    import math

    hz = max(lo, min(hi, float(hz)))
    return int(round(127 * math.log(hz / lo) / math.log(hi / lo)))


def _interface_cc(name: str) -> int:
    idx = INTERFACE_NAMES.index(name) if name in INTERFACE_NAMES else 2
    return int(round(idx / 11.0 * 127))


def _flues_cfg(config: dict[str, Any] | None) -> dict[str, Any]:
    if not config:
        return {}
    return config.get("flues", {})


def _feedback_levels(patch: Patch | None, cfg: dict[str, Any]) -> tuple[float, float, float]:
    """Keep delay/filter feedback low — PM program defaults (0.2) sound washy on Pi."""
    max_d1 = float(cfg.get("max_delay1_feedback", 0.05))
    max_d2 = float(cfg.get("max_delay2_feedback", 0.04))
    max_filt = float(cfg.get("max_filter_feedback", 0.03))
    if not patch:
        return max_d1 * 0.5, max_d2 * 0.5, max_filt * 0.5
    d1 = min(max_d1, 0.015 + patch.delay_mix * max_d1)
    d2 = min(max_d2, 0.015 + patch.reverb_mix * max_d2)
    filt = min(max_filt, patch.filter_resonance * max_filt * 0.5)
    return d1, d2, filt


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


def apply_keyboard_voice(
    port: mido.ports.BaseOutput,
    patch: Patch | None = None,
    *,
    config: dict[str, Any] | None = None,
) -> None:
    """Program 5 with low echo/noise — see flues-synth Program 5 slider map."""
    p = patch
    cfg = _flues_cfg(config)
    _silence_flues(port)
    port.send(mido.Message("program_change", channel=FLUES_CH, program=PROGRAM_KEYBOARD))

    iface = _interface_for_patch(p) if p else "bow"
    attack = p.attack if p else 0.14
    release = p.release if p else 2.2
    d1_fb, d2_fb, filt_fb = _feedback_levels(p, cfg)

    # Program 5 needs noise excitation (Noise → Interface). Too low = silent keys.
    noise_min = float(cfg.get("min_noise_level", 0.14))
    noise_max = float(cfg.get("max_noise_level", 0.22))
    if p:
        intensity = max(0.32, min(0.52, 0.55 - p.brightness * 0.28))
        noise = max(
            noise_min,
            min(noise_max, noise_min + p.noise_level * (noise_max - noise_min)),
        )
        filt_hz = max(500.0, min(3200.0, p.filter_cutoff * 0.9))
        filt_q = min(0.35, p.filter_resonance * 0.4)
    else:
        intensity = 0.4
        noise = noise_min
        filt_hz = 1200.0
        filt_q = 0.15

    ratio_cc = _f_to_cc(1.0, 0.5, 2.0)  # neutral delay ratio — detune adds metallic wash

    targets: list[tuple[int, int]] = [
        (PM_INTERFACE, _interface_cc(iface)),
        (PM_INTENSITY, _f_to_cc(intensity)),
        (PM_ATTACK, _f_to_cc(max(attack, 0.05), 0.02, 0.5)),
        (PM_RELEASE, _f_to_cc(max(release, 0.5), 0.3, 4.0)),
        (PM_DELAY1_FB, _f_to_cc(d1_fb)),
        (PM_DELAY2_FB, _f_to_cc(d2_fb)),
        (PM_FILTER_FB, _f_to_cc(filt_fb)),
        (PM_TUNING, _f_to_cc(0.5)),
        (PM_RATIO, ratio_cc),
        (CC_NOISE_LEVEL, _f_to_cc(noise)),
        (CC_FILTER_FREQ, _hz_to_cc(filt_hz)),
        (CC_FILTER_Q, _f_to_cc(filt_q, 0.1, 2.0)),
        (CC_FILTER_SHAPE, _f_to_cc(0.15)),  # mostly lowpass
    ]
    for cc, val in targets:
        _cc(port, cc, val)
    logger.info(
        "Flues PM voice: iface=%s d1_fb=%.3f d2_fb=%.3f noise=%.3f patch=%s",
        iface,
        d1_fb,
        d2_fb,
        noise,
        p.summary() if p else "(default)",
    )


def apply_patch(
    port: mido.ports.BaseOutput,
    patch: Patch,
    *,
    morph_steps: int = 0,
    config: dict[str, Any] | None = None,
) -> None:
    del morph_steps
    apply_keyboard_voice(port, patch, config=config)


def forward_pitch_bend(port: mido.ports.BaseOutput, pitch: int, channel: int = 0) -> None:
    del channel
    port.send(mido.Message("pitchwheel", channel=FLUES_CH, pitch=int(pitch)))


def forward_mod_wheel(port: mido.ports.BaseOutput, value: int) -> None:
    """Mod wheel → filter cutoff brighten (engine CC 32), not delay feedback."""
    v = max(0, min(127, int(value)))
    base = _hz_to_cc(900.0)
    top = _hz_to_cc(2800.0)
    cc_val = int(base + (v / 127.0) * (top - base))
    _cc(port, CC_FILTER_FREQ, cc_val)


def open_flues_output() -> mido.ports.BaseOutput | None:
    name = find_flues_output_port()
    if not name:
        logger.warning("No Flues MIDI output port (is pi-flues-synth running?)")
        return None
    return mido.open_output(name)
