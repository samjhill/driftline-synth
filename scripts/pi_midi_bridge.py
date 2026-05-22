#!/usr/bin/env python3
"""Headless MIDI → OSC bridge (separate from main.py to avoid Pi rtmidi SIGBUS)."""

from __future__ import annotations

import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import mido

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import install_root, load_config, resolve_data_path  # noqa: E402
from logging_setup import setup_logging  # noqa: E402
from midi_controller import MidiController, save_midi_status  # noqa: E402
from flues_client import (  # noqa: E402
    apply_keyboard_voice,
    forward_mod_wheel,
    forward_pitch_bend,
    open_flues_output,
)
from osc_client import OscClient  # noqa: E402
from patch_generator import PatchGenerator  # noqa: E402
from patch_prefs import load_patch_prefs  # noqa: E402
from patch_model import Patch  # noqa: E402
from patch_resolve import resolve_current_patch  # noqa: E402
from reseed_trigger import consume_reseed_request, reseed_request_path  # noqa: E402
from state_store import StateStore  # noqa: E402

logger = logging.getLogger("pi_midi_bridge")
_running = True


def _spawn_eink_restore(config: dict, root: Path) -> None:
    """Refresh patch art on e-ink (main.py runs with --no-eink in production)."""
    if not config.get("eink", {}).get("enabled", True):
        return
    script = root / "scripts" / "show_status.py"
    vpy = root / ".venv/bin/python"
    if not script.is_file() or not vpy.is_file():
        return
    env = os.environ.copy()
    env.setdefault("HOME", "/home/pi")
    env["PYTHONPATH"] = str(root / "src")
    subprocess.Popen(
        [str(vpy), str(script), "--restore-patch"],
        cwd=str(root),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def main() -> int:
    global _running
    setup_logging(os.environ.get("LOG_LEVEL", "INFO"))
    config = load_config()
    root = install_root()
    app_cfg = config.get("app", {})
    store = StateStore(
        resolve_data_path(app_cfg.get("state_path", "./state/current_patch.json"), root),
        resolve_data_path(app_cfg.get("favorites_path", "./state/favorites.json"), root),
    )
    gen = PatchGenerator(config)
    morph = float(config.get("audio", {}).get("patch_morph_seconds", 6.0))
    patch: Patch | None = resolve_current_patch(config, store, gen)
    reseed_req = reseed_request_path(app_cfg.get("marker_dir", "/var/lib/pi-ambient-synth"))

    audio_mode = ""
    mode_conf = Path("/etc/pi-ambient-synth/audio-mode.conf")
    if mode_conf.is_file():
        audio_mode = mode_conf.read_text(encoding="utf-8")
    flues_backend = os.environ.get("PI_MIDI_BACKEND", "").strip().lower() == "flues" or (
        "AUDIO_MODE=flues" in audio_mode
    )

    osc: OscClient | None = None
    flues_out = None
    if flues_backend:
        for _ in range(30):
            flues_out = open_flues_output()
            if flues_out is not None:
                break
            time.sleep(0.5)
        if flues_out and patch is not None:
            apply_keyboard_voice(flues_out, patch, config=config)
    else:
        osc = OscClient(config)
        osc.set_param("master_volume", 1.0)

    midi = MidiController(config)

    direct_keys = os.environ.get("PI_DIRECT_ALSA_KEYS", "").strip().lower() in (
        "1",
        "true",
        "yes",
    )
    hybrid_keys = os.environ.get("PI_HYBRID_ALSA_KEYS", "").strip().lower() in (
        "1",
        "true",
        "yes",
    )
    blip_device = os.environ.get("PI_BLIP_ALSA_DEVICE", "plughw:0,0")
    blip_py = root / "scripts" / "play_keyboard_blip.py"
    py = root / ".venv/bin/python"
    jack_script = root / "scripts" / "ensure_jack_playback.sh"
    _jack_ticks = 0

    flues_min_vel = 100
    if flues_backend:
        try:
            flues_min_vel = int(os.environ.get("PI_FLUES_MIN_VELOCITY", "100"))
        except ValueError:
            flues_min_vel = 100

    def on_note_on(note: int, velocity: int, ch: int) -> None:
        nonlocal _jack_ticks
        if flues_out is not None and velocity > 0:
            velocity = max(velocity, flues_min_vel)
        logger.info("bridge → note_on ch=%s note=%s vel=%s", ch, note, velocity)
        if (direct_keys or hybrid_keys) and blip_py.is_file() and py.is_file():
            subprocess.Popen(
                [str(py), str(blip_py), str(note), str(velocity), "-D", blip_device, "-d", "0.22"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        if flues_out is not None:
            flues_out.send(
                mido.Message("note_on", note=int(note), velocity=int(velocity), channel=0)
            )
        elif not direct_keys and osc is not None:
            logger.info("bridge → OSC note_on ch=%s note=%s vel=%s", ch, note, velocity)
            osc.note_on(note, velocity)
            _jack_ticks += 1
            if jack_script.is_file() and (_jack_ticks <= 3 or _jack_ticks % 12 == 0):
                subprocess.run(["bash", str(jack_script)], check=False, timeout=6)

    def on_note_off(note: int, velocity: int, ch: int) -> None:
        if os.environ.get("PI_MIDI_LOG_NOTES", "").strip() in ("1", "true", "yes"):
            logger.info("note_off ch=%s note=%s", ch, note)
        if flues_out is not None:
            flues_out.send(
                mido.Message("note_off", note=int(note), velocity=int(velocity), channel=0)
            )
        elif not direct_keys and osc is not None:
            osc.note_off(note, velocity)

    def on_reseed() -> None:
        nonlocal patch
        import random

        prefs = load_patch_prefs(config)
        new = gen.generate(
            seed=random.randint(0, 2**31 - 1),
            genre=prefs.genre,
            reseed_scope=prefs.reseed_scope,
        )
        store.save_current(new)
        patch = new
        if flues_out is not None:
            apply_keyboard_voice(flues_out, new, config=config)
            logger.info("Flues voice updated for reseed")
        elif osc is not None:
            osc.reseed_transition(2.0)
            osc.reseed(new.seed)
            osc.send_patch(new, morph_seconds=morph)
        logger.info("Reseed → %s", new.summary())
        _spawn_eink_restore(config, root)

    def on_clock() -> None:
        if flues_out is not None:
            flues_out.send(mido.Message("clock"))

    def on_pitch_bend(pitch: int, ch: int) -> None:
        if flues_out is not None:
            forward_pitch_bend(flues_out, pitch)

    def on_cc(control: int, value: int, ch: int) -> None:
        if flues_out is not None and control == midi._mod_wheel_cc:
            forward_mod_wheel(flues_out, value)

    midi.on_note_on = on_note_on
    midi.on_note_off = on_note_off
    midi.on_reseed_requested = on_reseed
    midi.on_clock = on_clock
    midi.on_pitch_bend = on_pitch_bend
    midi.on_cc = on_cc

    if not midi.open():
        logger.error("No MIDI input — bridge exiting")
        save_midi_status(config, connected=False, port_name=None, listening=False)
        return 1

    midi.start()
    save_midi_status(
        config,
        connected=True,
        port_name=midi.port_name,
        listening=True,
        state="running",
    )
    if flues_backend:
        port = flues_out.name if flues_out else "(no Flues port yet)"
        logger.info("MIDI bridge FLUES on %s → %s", midi.port_name, port)
        if flues_out is not None:
            connect_sh = root / "scripts" / "connect_midi_to_flues.sh"
            if connect_sh.is_file():
                subprocess.run(["bash", str(connect_sh)], check=False, timeout=8)
    elif direct_keys:
        logger.info("MIDI bridge DIRECT ALSA on %s (hw:0,0 blips; SuperCollider off)", midi.port_name)
    elif hybrid_keys:
        logger.info(
            "MIDI bridge HYBRID on %s (%s blips + OSC → SuperCollider)",
            midi.port_name,
            blip_device,
        )
    else:
        logger.info("MIDI bridge running on %s → OSC", midi.port_name)

    _spawn_eink_restore(config, root)

    def stop(_s=None, _f=None):
        global _running
        _running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    jack_every = 0
    jack_script = root / "scripts" / "ensure_jack_playback.sh"
    try:
        while _running:
            if consume_reseed_request(reseed_req):
                logger.info("Reseed requested (monitor, PiSugar button, or API)")
                on_reseed()
            if flues_backend and flues_out is None:
                flues_out = open_flues_output()
                if flues_out and patch is not None:
                    apply_keyboard_voice(flues_out, patch, config=config)
                if flues_out is not None:
                    connect_sh = root / "scripts" / "connect_midi_to_flues.sh"
                    if connect_sh.is_file():
                        subprocess.run(["bash", str(connect_sh)], check=False, timeout=8)
            midi.poll()
            if not flues_backend and jack_script.is_file():
                jack_every += 1
                if jack_every >= 1500:
                    jack_every = 0
                    subprocess.run(["bash", str(jack_script)], check=False, timeout=8)
            time.sleep(0.002)
    finally:
        midi.stop()
        save_midi_status(config, connected=False, port_name=None, listening=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
