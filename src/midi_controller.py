"""MIDI input from Arturia KeyStep with transport/reseed callbacks."""

from __future__ import annotations

import logging
import threading
import time
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

        self.on_note_on: Callable[[int, int, int], None] | None = None
        self.on_note_off: Callable[[int, int, int], None] | None = None
        self.on_cc: Callable[[int, int, int], None] | None = None
        self.on_transport: Callable[[str], None] | None = None
        self.on_reseed_requested: Callable[[], None] | None = None
        self.on_freeze_requested: Callable[[], None] | None = None
        self.on_evolve_toggle_requested: Callable[[], None] | None = None
        self.on_hold_change: Callable[[bool], None] | None = None

    @staticmethod
    def list_inputs() -> list[str]:
        return mido.get_input_names()

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
                if self._shift_held:
                    self._handle_shift_transport(event)
                elif self.on_transport:
                    self.on_transport(event)
            if self.on_cc:
                self.on_cc(msg.control, msg.value, ch)
        elif msg.type == "sysex":
            self._handle_sysex(msg.data)

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
