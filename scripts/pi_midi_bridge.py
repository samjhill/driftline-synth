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
def keystep_to_osc_note(note: int, channel: int) -> int:
    """Transpose low KeyStep / MPE notes into a clear keyboard register for SC."""
    n = int(note)
    while n < 60:
        n += 12
    return min(88, n)


from flues_client import (  # noqa: E402
    apply_keyboard_voice,
    forward_mod_wheel,
    forward_pitch_bend,
    keystep_to_flues_note,
    open_flues_output,
)
from fluidsynth_client import apply_patch_voice, open_engine  # noqa: E402
from fluidsynth_engine import FluidSynthEngine, keystep_note  # noqa: E402
from osc_client import OscClient  # noqa: E402
from patch_generator import PatchGenerator  # noqa: E402
from patch_prefs import load_patch_prefs  # noqa: E402
from patch_model import Patch  # noqa: E402
from patch_resolve import resolve_current_patch  # noqa: E402
from midi_clock import MidiClock  # noqa: E402
from play_tracker import PlayTracker  # noqa: E402
from reseed_trigger import consume_reseed_request, reseed_request_path  # noqa: E402
from state_store import StateStore  # noqa: E402
logger = logging.getLogger("pi_midi_bridge")
_running = True


def _ambient_audio_mode() -> bool:
    conf = Path("/etc/pi-ambient-synth/audio-mode.conf")
    if conf.is_file():
        return "AUDIO_MODE=ambient" in conf.read_text(encoding="utf-8")
    return True


def _sc_playback_ready(root: Path) -> bool:
    marker_dir = Path("/var/lib/pi-ambient-synth")
    if not (marker_dir / "sc-engine-ready").is_file():
        return False
    linked = marker_dir / "jack-playback-linked"
    if linked.is_file():
        try:
            age = time.monotonic() - linked.stat().st_mtime
            if age < 45.0:
                return True
        except OSError:
            pass
    return False


def _alsa_key_tone_mode(*, flues_backend: bool, direct_keys: bool) -> str:
    """off | always | fallback — ALSA pad on plughw:0,0 (same path that worked for you)."""
    if flues_backend or direct_keys or not _ambient_audio_mode():
        return "off"
    v = os.environ.get("PI_ALSA_KEY_TONE", "").strip().lower()
    if v in ("1", "true", "yes"):
        return "always"
    if v in ("0", "false", "no"):
        fb = os.environ.get("PI_ALSA_KEY_TONE_FALLBACK", "").strip().lower()
        if fb in ("1", "true", "yes"):
            return "fallback"
        return "off"
    return "always"


def _ensure_flues_disconnected(root: Path) -> None:
    script = root / "scripts" / "disconnect_midi_from_flues.sh"
    if script.is_file():
        subprocess.run(["bash", str(script)], check=False, timeout=10)


def _spawn_alsa_key_tone(
    *,
    py: Path,
    blip_py: Path,
    note: int,
    velocity: int,
    device: str,
    duration: str,
    pad: bool = True,
) -> None:
    if not blip_py.is_file() or not py.is_file():
        return
    cmd = [str(py), str(blip_py), str(note), str(velocity), "-D", device, "-d", duration]
    if pad:
        cmd.append("--pad")
    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def _enqueue_eink_patch(config: dict, root: Path) -> None:
    """Request patch screen via e-ink service queue (never touches GPIO)."""
    if not config.get("eink", {}).get("enabled", True):
        return
    if not config.get("eink", {}).get("update_on_reseed", True):
        return
    try:
        sys.path.insert(0, str(root / "src"))
        from eink_queue import enqueue_patch

        if enqueue_patch(from_state=True) is None:
            logger.debug("e-ink queue enqueue failed")
        else:
            logger.debug("e-ink patch queued")
    except Exception as e:
        logger.debug("e-ink queue unavailable: %s", e)


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
    env_backend = os.environ.get("PI_MIDI_BACKEND", "").strip().lower()
    fluidsynth_backend = env_backend == "fluidsynth" or (
        env_backend not in ("osc", "flues", "direct_keys")
        and "AUDIO_MODE=fluidsynth" in audio_mode
    )
    flues_backend = not fluidsynth_backend and (
        env_backend == "flues" or (env_backend != "osc" and "AUDIO_MODE=flues" in audio_mode)
    )
    if fluidsynth_backend:
        logger.info(
            "AUDIO_MODE=fluidsynth (MIDI → FluidSynth → ALSA %s)",
            config.get("fluidsynth", {}).get("alsa_device", "plughw:0,0"),
        )
        _ensure_flues_disconnected(root)
        subprocess.run(["pkill", "-x", "jackd"], check=False)
        subprocess.run(["pkill", "-x", "scsynth"], check=False)
        subprocess.run(["pkill", "-x", "sclang"], check=False)
    elif flues_backend:
        logger.info("AUDIO_MODE=flues (MIDI → Flues-Synth)")
    elif os.environ.get("PI_DIRECT_ALSA_KEYS", "").strip().lower() in ("1", "true", "yes"):
        logger.info("AUDIO_MODE=direct_keys (aplay blips)")
    else:
        logger.info("AUDIO_MODE=ambient (MIDI → OSC → SuperCollider)")
        _ensure_flues_disconnected(root)

    osc: OscClient | None = None
    flues_out = None
    fs_engine: FluidSynthEngine | None = None
    if fluidsynth_backend:
        try:
            fs_engine = open_engine(config)
            if patch is not None:
                apply_patch_voice(fs_engine, patch, config)
        except Exception as exc:
            logger.error("FluidSynth failed to start: %s", exc)
            return 1
    elif flues_backend:
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
        if patch is not None:
            osc.send_patch(patch, morph_seconds=0.0)

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
    alsa_tone_mode = _alsa_key_tone_mode(
        flues_backend=flues_backend, direct_keys=direct_keys
    )
    blip_device = os.environ.get("PI_BLIP_ALSA_DEVICE", "").strip() or "plughw:0,0"
    blip_duration = os.environ.get("PI_BLIP_DURATION", "0.52")
    blip_pad = os.environ.get("PI_BLIP_PAD", "1").strip().lower() not in ("0", "false", "no")
    blip_py = root / "scripts" / "play_keyboard_blip.py"
    py = root / ".venv/bin/python"
    jack_script = root / "scripts" / "ensure_jack_playback.sh"
    jack_env = os.environ.copy()
    play = PlayTracker()
    clock = MidiClock()
    _jack_ticks = 0
    patch_name = (patch.name if patch else "") or ""

    flues_min_vel = 100
    if flues_backend:
        try:
            flues_min_vel = int(os.environ.get("PI_FLUES_MIN_VELOCITY", "100"))
        except ValueError:
            flues_min_vel = 100

    def on_note_on(note: int, velocity: int, ch: int) -> None:
        nonlocal _jack_ticks
        if fs_engine is not None and velocity > 0:
            play_note = keystep_note(note, ch)
            logger.info(
                "bridge → fluidsynth note_on midi=%s play=%s vel=%s ch=%s",
                note,
                play_note,
                velocity,
                ch,
            )
            fs_engine.note_on(note, velocity, channel=0)
            return
        if flues_out is not None and velocity > 0:
            velocity = max(velocity, flues_min_vel)
        if flues_out is not None:
            flues_note = keystep_to_flues_note(note, ch)
            logger.info(
                "bridge → flues note_on midi=%s flues=%s vel=%s ch_in=%s",
                note,
                flues_note,
                velocity,
                ch,
            )
        else:
            osc_note = keystep_to_osc_note(note, ch)
            if osc_note != note:
                logger.info(
                    "bridge → note_on ch=%s midi=%s → osc=%s vel=%s",
                    ch,
                    note,
                    osc_note,
                    velocity,
                )
            else:
                logger.info("bridge → note_on ch=%s note=%s vel=%s", ch, note, velocity)
            note = osc_note
        play_alsa = alsa_tone_mode == "always" or (
            alsa_tone_mode == "fallback" and not _sc_playback_ready(root)
        )
        if play_alsa and blip_py.is_file() and py.is_file():
            _spawn_alsa_key_tone(
                py=py,
                blip_py=blip_py,
                note=note,
                velocity=velocity,
                device=blip_device,
                duration=blip_duration,
                pad=blip_pad,
            )
        if flues_out is not None:
            flues_out.send(
                mido.Message(
                    "note_on",
                    note=flues_note,
                    velocity=int(velocity),
                    channel=0,
                )
            )
        elif not direct_keys and osc is not None:
            if _jack_ticks == 0 and jack_script.is_file():
                subprocess.Popen(
                    ["bash", str(jack_script)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=jack_env,
                    start_new_session=True,
                )
            alsa_on = alsa_tone_mode != "off"
            logger.info(
                "bridge → OSC note_on note=%s vel=%s ch=%s dest=%s:%s alsa_fallback=%s",
                note,
                velocity,
                ch,
                osc.host,
                osc.port,
                alsa_on,
            )
            root, arp_changed = play.note_on(note)
            if arp_changed:
                osc.arp_active(play.arp_active)
            if root is not None:
                osc.texture_root(root)
            osc.note_on(note, velocity)
            _jack_ticks += 1
            if jack_script.is_file() and (_jack_ticks <= 4 or _jack_ticks % 8 == 0):
                subprocess.Popen(
                    ["bash", str(jack_script)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=jack_env,
                    start_new_session=True,
                )

    def on_note_off(note: int, velocity: int, ch: int) -> None:
        if fs_engine is not None:
            fs_engine.note_off(note, velocity, channel=0)
            return
        if flues_out is None:
            note = keystep_to_osc_note(note, ch)
        if os.environ.get("PI_MIDI_LOG_NOTES", "").strip() in ("1", "true", "yes"):
            logger.info("note_off ch=%s note=%s", ch, note)
        if flues_out is not None:
            flues_note = keystep_to_flues_note(note, ch)
            flues_out.send(
                mido.Message(
                    "note_off",
                    note=flues_note,
                    velocity=int(velocity),
                    channel=0,
                )
            )
        elif not direct_keys and osc is not None:
            root = play.note_off(note)
            if root is not None and not play.hold_latched:
                osc.texture_root(root)
            osc.note_off(note, velocity)

    def on_reseed() -> None:
        nonlocal patch, patch_name
        import random

        prefs = load_patch_prefs(config)
        new = gen.generate(
            seed=random.randint(0, 2**31 - 1),
            genre=prefs.genre,
            reseed_scope=prefs.reseed_scope,
        )
        store.save_current(new)
        patch = new
        patch_name = patch.name
        if fs_engine is not None:
            apply_patch_voice(fs_engine, new, config)
            logger.info("FluidSynth program updated for reseed")
        elif flues_out is not None:
            apply_keyboard_voice(flues_out, new, config=config)
            logger.info("Flues voice updated for reseed")
        elif osc is not None:
            osc.reseed_transition(2.0)
            osc.reseed(new.seed)
            osc.send_patch(new, morph_seconds=morph)
        logger.info("Reseed → %s", new.summary())
        _enqueue_eink_patch(config, root)

    def on_clock() -> None:
        if fs_engine is not None:
            return
        if osc is not None:
            osc.clock_bpm(clock.tick())
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
    if fluidsynth_backend:
        logger.info(
            "MIDI bridge FLUIDSYNTH on %s → %s (%s)",
            midi.port_name,
            fs_engine.backend if fs_engine else "?",
            config.get("fluidsynth", {}).get("alsa_device", "plughw:0,0"),
        )
    elif flues_backend:
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
        if alsa_tone_mode == "always":
            logger.info(
                "MIDI bridge on %s → OSC + ALSA pad (%s, %ss)",
                midi.port_name,
                blip_device,
                blip_duration,
            )
        elif alsa_tone_mode == "fallback":
            logger.info(
                "MIDI bridge on %s → OSC + ALSA pad if JACK unlinked",
                midi.port_name,
            )
        else:
            logger.info("MIDI bridge running on %s → OSC", midi.port_name)

    # E-ink: startup + reseed only (detached; never blocks note handling).
    if fluidsynth_backend and config.get("eink", {}).get("enabled", True):
        _enqueue_eink_patch(config, root)

    # JACK watchdog (ambient SC path only).
    if not (direct_keys or hybrid_keys or fluidsynth_backend):
        if jack_script.is_file():
            subprocess.run(
                ["bash", str(jack_script)],
                check=False,
                timeout=8,
                env=jack_env,
            )

    def stop(_s=None, _f=None):
        global _running
        _running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    jack_every = 0
    flues_guard = 0
    reconnect_tick = 0
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
            reconnect_tick += 1
            if reconnect_tick >= 500:
                reconnect_tick = 0
                midi.maybe_reconnect_preferred()
            midi.poll()
            if not flues_backend and fs_engine is None:
                flues_guard += 1
                if flues_guard >= 2000:
                    flues_guard = 0
                    _ensure_flues_disconnected(root)
                if jack_script.is_file():
                    jack_every += 1
                    if jack_every >= 1500:
                        jack_every = 0
                        subprocess.Popen(
                            ["bash", str(jack_script)],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            env=jack_env,
                            start_new_session=True,
                        )
            time.sleep(0.002)
    finally:
        midi.stop()
        save_midi_status(config, connected=False, port_name=None, listening=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
