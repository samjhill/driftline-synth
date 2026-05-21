"""MIDI input from Arturia KeyStep with transport/reseed callbacks."""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path
from typing import Any, Callable

import mido

logger = logging.getLogger(__name__)

# KeyStep transport: often MMC or note/CC; fallbacks documented in troubleshooting.
TRANSPORT_CC = {
    102: "play",   # common Arturia mapping (varies by firmware)
    103: "stop",
    104: "record",
}

# Fallback: specific notes used when shift combos unavailable (V1)
RESEED_NOTE = 0   # C-1 — unlikely played
FREEZE_NOTE = 1
EVOLVE_NOTE = 2

# Standard MMC real-time (if KeyStep sends them)
MMC_PLAY = 0xFA
MMC_STOP = 0xFC
MMC_RECORD = 0xF7


class MidiController:
    def __init__(self, config: dict[str, Any]):
        midi = config.get("midi", {})
        self.preferred_keywords = midi.get(
            "preferred_input_keywords", ["KeyStep", "Arturia"]
        )
        self.channel_filter = midi.get("channel")
        self.fallback = midi.get("fallback_to_first_available", True)
        self._port_name: str | None = None
        self._port: mido.ports.BaseInput | None = None
        self._thread: threading.Thread | None = None
        self._running = False
        self._shift_held = False
        self._last_stop_at: float = 0.0
        self._recall_window = midi.get("favorite_recall_window_ms", 600) / 1000.0
        self._weather_cc = midi.get("weather_cc", 1)
        self._split_note = midi.get("split_note", 55)

        self.on_clock: Callable[[], None] | None = None

        self.on_note_on: Callable[[int, int, int], None] | None = None
        self.on_note_off: Callable[[int, int, int], None] | None = None
        self.on_cc: Callable[[int, int, int], None] | None = None
        self.on_transport: Callable[[str], None] | None = None
        self.on_reseed_requested: Callable[[], None] | None = None
        self.on_freeze_requested: Callable[[], None] | None = None
        self.on_evolve_toggle_requested: Callable[[], None] | None = None
        self.on_hold_change: Callable[[bool], None] | None = None
        self.on_recall_favorite: Callable[[], None] | None = None
        self.on_weather_change: Callable[[float], None] | None = None

    @property
    def port_name(self) -> str | None:
        return self._port_name

    @property
    def is_open(self) -> bool:
        return self._port is not None

    @property
    def is_listening(self) -> bool:
        return self._running and self._port is not None

    @staticmethod
    def list_inputs() -> list[str]:
        try:
            return mido.get_input_names()
        except Exception as e:
            logger.error("MIDI port scan failed: %s", e)
            return []

    def select_port(self) -> str | None:
        names = self.list_inputs()
        if not names:
            logger.error("No MIDI input ports found")
            return None
        for keyword in self.preferred_keywords:
            for name in names:
                if keyword.lower() in name.lower():
                    logger.info("Selected MIDI input: %s", name)
                    return name
        if self.fallback:
            logger.warning("Preferred device not found; using: %s", names[0])
            return names[0]
        return None

    def open(self) -> bool:
        name = self.select_port()
        if not name:
            return False
        try:
            self._port = mido.open_input(name)
            self._port_name = name
            return True
        except Exception as e:
            logger.error("Failed to open MIDI port %s: %s", name, e)
            return False

    def _channel_ok(self, channel: int) -> bool:
        if self.channel_filter is None:
            return True
        return channel == self.channel_filter

    def _handle_message(self, msg: mido.Message) -> None:
        if msg.type == "note_on" and msg.velocity > 0:
            ch = getattr(msg, "channel", 0)
            if not self._channel_ok(ch):
                return
            if self._shift_held:
                self._handle_shift_note(msg.note)
                return
            if msg.note in (RESEED_NOTE, FREEZE_NOTE, EVOLVE_NOTE) and msg.velocity > 100:
                self._handle_fallback_note(msg.note)
                return
            if self.on_note_on:
                self.on_note_on(msg.note, msg.velocity, ch)
        elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
            ch = getattr(msg, "channel", 0)
            if not self._channel_ok(ch):
                return
            vel = getattr(msg, "velocity", 0)
            if self.on_note_off:
                self.on_note_off(msg.note, vel, ch)
        elif msg.type == "control_change":
            ch = getattr(msg, "channel", 0)
            if not self._channel_ok(ch):
                return
            if msg.control == 63 and msg.value >= 64:
                self._shift_held = True
            elif msg.control == 63 and msg.value < 64:
                self._shift_held = False
            if msg.control == 64:
                if self.on_hold_change:
                    self.on_hold_change(msg.value >= 64)
            if msg.control in TRANSPORT_CC:
                event = TRANSPORT_CC[msg.control]
                if event == "stop":
                    now = time.time()
                    if now - self._last_stop_at < self._recall_window and self.on_recall_favorite:
                        logger.info("Double STOP → recall favorite")
                        self.on_recall_favorite()
                    self._last_stop_at = now
                if self._shift_held:
                    self._handle_shift_transport(event)
                elif self.on_transport:
                    self.on_transport(event)
            if msg.control == self._weather_cc and self.on_weather_change:
                self.on_weather_change(msg.value / 127.0)
            if self.on_cc:
                self.on_cc(msg.control, msg.value, ch)
        elif msg.type == "clock":
            if self.on_clock:
                self.on_clock()
        elif msg.type == "sysex":
            self._handle_sysex(msg.data)

    def is_duo_low(self, note: int) -> bool:
        return note < self._split_note

    def _handle_shift_note(self, note: int) -> None:
        if note in (RESEED_NOTE, FREEZE_NOTE, EVOLVE_NOTE):
            self._handle_fallback_note(note)

    def _handle_fallback_note(self, note: int) -> None:
        if note == RESEED_NOTE and self.on_reseed_requested:
            self.on_reseed_requested()
        elif note == FREEZE_NOTE and self.on_freeze_requested:
            self.on_freeze_requested()
        elif note == EVOLVE_NOTE and self.on_evolve_toggle_requested:
            self.on_evolve_toggle_requested()

    def _handle_shift_transport(self, event: str) -> None:
        if event == "play" and self.on_reseed_requested:
            logger.info("SHIFT+PLAY → reseed")
            self.on_reseed_requested()
        elif event == "stop" and self.on_freeze_requested:
            logger.info("SHIFT+STOP → freeze/favorite")
            self.on_freeze_requested()
        elif event == "record" and self.on_evolve_toggle_requested:
            logger.info("SHIFT+RECORD → evolve toggle")
            self.on_evolve_toggle_requested()

    def _handle_sysex(self, data: tuple[int, ...]) -> None:
        if not data:
            return
        status = data[0] if len(data) == 1 else None
        if len(data) >= 1:
            b = data[0]
            if b == MMC_PLAY:
                if self._shift_held and self.on_reseed_requested:
                    self.on_reseed_requested()
                elif self.on_transport:
                    self.on_transport("play")
            elif b == MMC_STOP:
                if self._shift_held and self.on_freeze_requested:
                    self.on_freeze_requested()
                elif self.on_transport:
                    self.on_transport("stop")

    def start(self) -> None:
        if not self._port:
            raise RuntimeError("MIDI port not open")
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        logger.info("MIDI listener started on %s", self._port_name)

    def _run(self) -> None:
        assert self._port is not None
        while self._running:
            for msg in self._port.iter_pending():
                self._handle_message(msg)
            time.sleep(0.001)

    def stop(self) -> None:
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)
        if self._port:
            self._port.close()
            self._port = None
        self._port_name = None


def midi_snapshot(config: dict[str, Any]) -> dict[str, Any]:
    """Scan ALSA/MIDI inputs and resolve preferred keyboard port."""
    midi_cfg = config.get("midi", {})
    keywords: list[str] = midi_cfg.get(
        "preferred_input_keywords", ["KeyStep", "Arturia"]
    )
    fallback = midi_cfg.get("fallback_to_first_available", True)
    inputs = MidiController.list_inputs()
    preferred: str | None = None
    for keyword in keywords:
        for name in inputs:
            if keyword.lower() in name.lower():
                preferred = name
                break
        if preferred:
            break
    selected = preferred
    if not selected and inputs and fallback:
        selected = inputs[0]
    return {
        "inputs": inputs,
        "preferred_keywords": keywords,
        "selected_port": selected,
        "preferred_found": preferred is not None,
        "device_present": bool(inputs),
    }


def load_midi_marker(marker_dir: Path | str) -> dict[str, Any] | None:
    path = Path(marker_dir) / "midi-status.json"
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else None
    except (json.JSONDecodeError, OSError):
        return None


def save_midi_status(
    config: dict[str, Any],
    *,
    connected: bool,
    port_name: str | None,
    listening: bool,
) -> Path | None:
    """Persist synth MIDI open state for the LAN monitor (separate process)."""
    marker_dir = Path(
        config.get("app", {}).get("marker_dir", "/var/lib/pi-ambient-synth")
    )
    payload = {
        "connected": connected,
        "port_name": port_name,
        "listening": listening,
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    try:
        marker_dir.mkdir(parents=True, exist_ok=True)
        path = marker_dir / "midi-status.json"
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        return path
    except OSError as e:
        logger.warning("Could not write %s: %s", marker_dir / "midi-status.json", e)
        return None


def midi_status_summary(config: dict[str, Any]) -> dict[str, Any]:
    """Hardware scan plus optional synth marker for monitor UI."""
    marker_dir = config.get("app", {}).get("marker_dir", "/var/lib/pi-ambient-synth")
    synth = load_midi_marker(marker_dir)
    try:
        snap = midi_snapshot(config)
    except Exception as e:
        logger.warning("MIDI port scan failed: %s", e)
        snap = {
            "inputs": [],
            "preferred_keywords": config.get("midi", {}).get(
                "preferred_input_keywords", ["KeyStep", "Arturia"]
            ),
            "selected_port": None,
            "preferred_found": False,
            "device_present": False,
            "scan_error": str(e),
        }
    label, ok = _midi_status_label(snap, synth)
    return {**snap, "synth": synth, "label": label, "ok": ok}


def _midi_status_label(
    snap: dict[str, Any], synth: dict[str, Any] | None
) -> tuple[str, bool | None]:
    if synth and synth.get("listening"):
        port = synth.get("port_name") or snap.get("selected_port") or "MIDI"
        return f"Connected — {port}", True
    if synth is not None and synth.get("connected") is False:
        if snap.get("preferred_found") or snap.get("selected_port"):
            port = snap.get("selected_port") or "?"
            return f"Detected — {port} (synth not listening)", False
        if snap.get("device_present"):
            port = snap.get("selected_port") or (snap.get("inputs") or ["?"])[0]
            return f"Detected — {port} (synth could not open port)", False
        return "Not connected — no MIDI ports (check KeyStep USB data cable)", False
    if snap.get("preferred_found"):
        port = snap.get("selected_port") or "?"
        return f"Detected — {port}", None
    if snap.get("device_present"):
        port = (snap.get("inputs") or ["?"])[0]
        return f"Input available — {port}", None
    return "Not connected — no MIDI inputs", False
