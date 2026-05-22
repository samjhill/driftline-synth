"""Map Pi Ambient patches → Flues-Synth MIDI (program change + CCs)."""

from __future__ import annotations

import logging
from typing import Any

import mido

from patch_model import Patch

logger = logging.getLogger(__name__)

FLUES_CH = 0

# Program 3: pitched formant pad (Noise → Formants). Best for KeyStep melody.
PROGRAM_FORMANT = 3
# Program 5: physical model — easy to turn into noise-only whoosh if mis-tuned.
PROGRAM_PHYSICAL = 5

# Program 3 slider CCs (PROGRAM_CHANGE.md)
FMT_F1 = 73  # → CC 71
FMT_F2 = 72  # → CC 10
FMT_F3 = 28  # → CC 74
FMT_F4 = 30  # → CC 75
FMT_NOISE = 74  # → CC 20 (breath, keep low)
FMT_ATTACK = 27  # → CC 73
FMT_RELEASE = 7  # → CC 72

# Program 5 slider CCs
PM_DELAY1_FB = 73
PM_DELAY2_FB = 72
PM_FILTER_FB = 28
PM_INTERFACE = 30
PM_INTENSITY = 74
PM_TUNING = 71
PM_RATIO = 1
PM_ATTACK = 27
PM_RELEASE = 7

CC_NOISE_LEVEL = 20
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
    """Prefer bridge RtMidiOut (aconnect → Flues); else Flues MIDI In."""
    names = mido.get_output_names()
    for name in names:
        low = name.lower()
        if "rtmidi" in low and "output" in low:
            return name
    for name in names:
        if "flues" in name.lower() and "in" in name.lower():
            return name
    for name in names:
        if "flues" in name.lower():
            return name
    return None


def keystep_to_flues_note(note: int, channel: int) -> int:
    """KeyStep MPE (ch 14+) often sends high note IDs — fold into a melodic range."""
    n = int(note)
    if channel >= 2 and n > 72:
        n -= 24
    if channel >= 2 and n > 72:
        n -= 12
    return max(36, min(96, n))


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
    idx = INTERFACE_NAMES.index(name) if name in INTERFACE_NAMES else 2
    return int(round(idx / 11.0 * 127))


def _flues_cfg(config: dict[str, Any] | None) -> dict[str, Any]:
    if not config:
        return {}
    return config.get("flues", {})


def keyboard_program(patch: Patch | None, cfg: dict[str, Any]) -> int:
    """Which Flues program to use for KeyStep notes."""
    mode = str(cfg.get("keyboard_program", "physical")).lower()
    if mode == "physical":
        return PROGRAM_PHYSICAL
    if mode == "formant":
        return PROGRAM_FORMANT
    # auto: physical only for bright/pulse patches with high brightness
    if patch and patch.brightness > 0.72 and patch.attack < 0.12:
        return PROGRAM_PHYSICAL
    return PROGRAM_FORMANT


def _feedback_levels(patch: Patch | None, cfg: dict[str, Any]) -> tuple[float, float, float]:
    """Near-dry — feedback loops read as constant hiss on Pi headphones."""
    max_d1 = float(cfg.get("max_delay1_feedback", 0.012))
    max_d2 = float(cfg.get("max_delay2_feedback", 0.01))
    max_filt = float(cfg.get("max_filter_feedback", 0.008))
    if not patch:
        return max_d1 * 0.5, max_d2 * 0.5, max_filt * 0.5
    d1 = min(max_d1, 0.004 + patch.delay_mix * max_d1)
    d2 = min(max_d2, 0.004 + patch.reverb_mix * max_d2)
    filt = min(max_filt, patch.filter_resonance * max_filt * 0.25)
    return d1, d2, filt


def _silence_flues(port: mido.ports.BaseOutput) -> None:
    for ch in range(16):
        port.send(mido.Message("control_change", channel=ch, control=123, value=0))


def _apply_formant_voice(
    port: mido.ports.BaseOutput,
    patch: Patch | None,
    cfg: dict[str, Any],
) -> None:
    """Program 3 — vowel/formant pitch, gentle breath noise only."""
    p = patch
    _silence_flues(port)
    port.send(mido.Message("program_change", channel=FLUES_CH, program=PROGRAM_FORMANT))

    if p:
        # Map patch tone to formant centers (Hz ranges from Flues docs).
        warm = 1.0 - p.brightness
        f1 = 380.0 + warm * 280.0  # 380–660 Hz
        f2 = 1100.0 + p.brightness * 700.0  # 1100–1800
        f3 = 2000.0 + p.brightness * 500.0
        f4 = 3000.0 + p.brightness * 400.0
        noise = min(
            float(cfg.get("max_noise_level", 0.06)),
            float(cfg.get("min_noise_level", 0.03)) + p.noise_level * 0.03,
        )
        attack = max(p.attack, 0.04)
        release = max(p.release, 0.8)
    else:
        f1, f2, f3, f4 = 500.0, 1500.0, 2400.0, 3400.0
        noise = 0.07
        attack, release = 0.08, 1.5

    targets: list[tuple[int, int]] = [
        (FMT_F1, _hz_to_cc(f1, 200.0, 1000.0)),
        (FMT_F2, _hz_to_cc(f2, 500.0, 3000.0)),
        (FMT_F3, _hz_to_cc(f3, 1500.0, 4000.0)),
        (FMT_F4, _hz_to_cc(f4, 2500.0, 4500.0)),
        (FMT_NOISE, _f_to_cc(noise)),
        (FMT_ATTACK, _f_to_cc(attack, 0.02, 0.5)),
        (FMT_RELEASE, _f_to_cc(release, 0.3, 4.0)),
    ]
    for cc, val in targets:
        _cc(port, cc, val)
    logger.info(
        "Flues formant voice: f1=%.0fHz noise=%.3f patch=%s",
        f1,
        noise,
        p.summary() if p else "(default)",
    )


def _apply_physical_voice(
    port: mido.ports.BaseOutput,
    patch: Patch | None,
    cfg: dict[str, Any],
) -> None:
    """Program 5 — reed/flute, low noise exciter + strong interface intensity."""
    p = patch
    _silence_flues(port)
    port.send(mido.Message("program_change", channel=FLUES_CH, program=PROGRAM_PHYSICAL))

    iface = "reed"
    if p and p.brightness > 0.65:
        iface = "flute"
    attack = p.attack if p else 0.1
    release = p.release if p else 1.8
    d1_fb, d2_fb, filt_fb = _feedback_levels(p, cfg)

    # PM idle hiss = noise exciter level; keep low, push pitch via interface intensity.
    noise_min = float(cfg.get("min_noise_level", 0.035))
    noise_max = float(cfg.get("max_noise_level", 0.055))
    if p:
        intensity = max(0.55, min(0.72, 0.68 - p.brightness * 0.1))
        noise = max(
            noise_min,
            min(noise_max, noise_min + p.noise_level * (noise_max - noise_min) * 0.6),
        )
        filt_hz = max(500.0, min(2200.0, p.filter_cutoff * 0.75))
        filt_q = min(0.22, p.filter_resonance * 0.28)
    else:
        intensity = 0.6
        noise = noise_min
        filt_hz = 1100.0
        filt_q = 0.1

    targets: list[tuple[int, int]] = [
        (PM_INTERFACE, _interface_cc(iface)),
        (PM_INTENSITY, _f_to_cc(intensity)),
        (PM_ATTACK, _f_to_cc(max(attack, 0.05), 0.02, 0.5)),
        (PM_RELEASE, _f_to_cc(max(release, 0.5), 0.3, 4.0)),
        (PM_DELAY1_FB, _f_to_cc(d1_fb)),
        (PM_DELAY2_FB, _f_to_cc(d2_fb)),
        (PM_FILTER_FB, _f_to_cc(filt_fb)),
        (PM_TUNING, _f_to_cc(0.5)),
        (PM_RATIO, _f_to_cc(1.0, 0.5, 2.0)),
        (CC_NOISE_LEVEL, _f_to_cc(noise)),
        (CC_FILTER_FREQ, _hz_to_cc(filt_hz, 80.0, 8000.0)),
        (CC_FILTER_Q, _f_to_cc(filt_q, 0.1, 2.0)),
        (CC_FILTER_SHAPE, _f_to_cc(0.12)),
    ]
    for cc, val in targets:
        _cc(port, cc, val)
    logger.info(
        "Flues PM voice: iface=%s intensity=%.2f noise=%.3f d1_fb=%.3f patch=%s",
        iface,
        intensity,
        noise,
        d1_fb,
        p.summary() if p else "(default)",
    )


def apply_keyboard_voice(
    port: mido.ports.BaseOutput,
    patch: Patch | None = None,
    *,
    config: dict[str, Any] | None = None,
) -> None:
    cfg = _flues_cfg(config)
    prog = keyboard_program(patch, cfg)
    if prog == PROGRAM_FORMANT:
        _apply_formant_voice(port, patch, cfg)
    else:
        _apply_physical_voice(port, patch, cfg)


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
    """Mod wheel opens formant brightness (F3) slightly."""
    v = max(0, min(127, int(value)))
    base = _hz_to_cc(2000.0, 1500.0, 4000.0)
    top = _hz_to_cc(3600.0, 1500.0, 4000.0)
    _cc(port, FMT_F3, int(base + (v / 127.0) * (top - base)))


def open_flues_output() -> mido.ports.BaseOutput | None:
    name = find_flues_output_port()
    if not name:
        logger.warning("No Flues MIDI output port (is pi-flues-synth running?)")
        return None
    return mido.open_output(name)
