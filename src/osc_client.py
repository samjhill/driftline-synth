"""OSC client for SuperCollider ambient engine."""

from __future__ import annotations

import logging
from typing import Any

from pythonosc.udp_client import SimpleUDPClient

from patch_model import Patch

logger = logging.getLogger(__name__)

PATCH_OSC_KEYS = (
    "seed",
    "name",
    "scale_name",
    "root_note",
    "oscillator_blend",
    "sub_level",
    "noise_level",
    "filter_cutoff",
    "filter_resonance",
    "attack",
    "decay",
    "sustain",
    "release",
    "drift_amount",
    "lfo_rate",
    "lfo_depth",
    "delay_mix",
    "delay_time",
    "reverb_mix",
    "reverb_size",
    "texture_density",
    "stereo_width",
    "brightness",
    "evolve_enabled",
)


class OscClient:
    def __init__(self, config: dict[str, Any]):
        osc = config.get("osc", {})
        self.host = osc.get("supercollider_host", "127.0.0.1")
        self.port = osc.get("supercollider_port", 57120)
        self.morph_seconds = config.get("audio", {}).get("patch_morph_seconds", 6.0)
        self._client = SimpleUDPClient(self.host, self.port)
        logger.info("OSC client → %s:%s", self.host, self.port)

    def note_on(self, note: int, velocity: int = 100) -> None:
        self._client.send_message("/pi_synth/note_on", [note, velocity])

    def note_off(self, note: int, velocity: int = 0) -> None:
        self._client.send_message("/pi_synth/note_off", [note, velocity])

    def set_param(self, name: str, value: float | int | str | bool) -> None:
        if isinstance(value, bool):
            value = 1 if value else 0
        self._client.send_message("/pi_synth/set", [name, value])

    def send_patch(self, patch: Patch, morph_seconds: float | None = None) -> None:
        morph = morph_seconds if morph_seconds is not None else self.morph_seconds
        self._client.send_message("/pi_synth/morph_time", [morph])
        for key in PATCH_OSC_KEYS:
            self.set_param(key, getattr(patch, key))
        self._client.send_message("/pi_synth/patch_loaded", [patch.seed])
        logger.info("Sent patch: %s", patch.summary())

    def reseed(self, seed: int) -> None:
        self._client.send_message("/pi_synth/reseed", [seed])

    def reseed_transition(self, seconds: float = 2.0) -> None:
        self._client.send_message("/pi_synth/reseed_transition", [seconds])

    def texture_root(self, note: int | None) -> None:
        self._client.send_message("/pi_synth/texture_root", [-1 if note is None else note])

    def arp_active(self, active: bool) -> None:
        self._client.send_message("/pi_synth/arp_active", [1 if active else 0])

    def hold_latch(self, on: bool) -> None:
        self._client.send_message("/pi_synth/hold", [1 if on else 0])

    def evolve(self, enabled: bool) -> None:
        self._client.send_message("/pi_synth/evolve", [1 if enabled else 0])

    def all_notes_off(self) -> None:
        self._client.send_message("/pi_synth/all_notes_off", [])

    def panic(self) -> None:
        self._client.send_message("/pi_synth/panic", [])
        logger.warning("Panic sent to SuperCollider")

    def set_volume(self, level: float) -> None:
        self.set_param("master_volume", level)
