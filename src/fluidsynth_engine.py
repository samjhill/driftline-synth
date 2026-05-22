"""FluidSynth → direct ALSA (no JACK, no SuperCollider)."""

from __future__ import annotations

import logging
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

try:
    import fluidsynth as _fluidsynth  # type: ignore[import-untyped]

    _HAS_PYFLUIDSYNTH = True
except ImportError:
    _fluidsynth = None
    _HAS_PYFLUIDSYNTH = False


def default_soundfont(cfg: dict[str, Any]) -> Path:
    explicit = cfg.get("soundfont", "").strip()
    if explicit:
        p = Path(explicit)
        if p.is_file():
            return p
    for candidate in (
        "/usr/share/sounds/sf2/FluidR3_GM.sf2",
        "/usr/share/sounds/sf2/default-GM.sf2",
        "/usr/share/soundfonts/FluidR3_GM.sf2",
    ):
        if Path(candidate).is_file():
            return Path(candidate)
    raise FileNotFoundError(
        "No GM soundfont found — install: sudo apt-get install -y fluid-soundfont-gm"
    )


def keystep_note(note: int, channel: int) -> int:
    """Transpose low KeyStep / MPE notes into a playable range."""
    n = int(note)
    while n < 48:
        n += 12
    return min(96, n)


class FluidSynthEngine:
    """One FluidSynth instance with direct ALSA output."""

    def __init__(self, config: dict[str, Any]):
        fs_cfg = config.get("fluidsynth", {})
        self._cfg = fs_cfg
        self._channel = int(fs_cfg.get("channel", 0))
        self._alsa_device = str(fs_cfg.get("alsa_device", "plughw:0,0"))
        self._gain = float(fs_cfg.get("gain", 0.85))
        self._sf2 = default_soundfont(fs_cfg)
        self._sfid: int | None = None
        self._synth: Any = None
        self._proc: subprocess.Popen[str] | None = None
        self._use_py = _HAS_PYFLUIDSYNTH

    @property
    def backend(self) -> str:
        return "pyfluidsynth" if self._use_py else "fluidsynth-stdin"

    def start(self) -> None:
        if self._synth is not None or self._proc is not None:
            return
        if self._use_py:
            self._start_py()
        else:
            self._start_subprocess()

    def _start_py(self) -> None:
        assert _fluidsynth is not None
        synth = _fluidsynth.Synth()
        synth.setting("audio.alsa.device", self._alsa_device)
        synth.setting("synth.gain", str(self._gain))
        synth.start(driver="alsa")
        sfid = synth.sfload(str(self._sf2))
        self._synth = synth
        self._sfid = sfid
        logger.info(
            "FluidSynth started (pyfluidsynth) sf2=%s alsa=%s gain=%.2f",
            self._sf2,
            self._alsa_device,
            self._gain,
        )

    def _start_subprocess(self) -> None:
        if not shutil.which("fluidsynth"):
            raise RuntimeError("fluidsynth binary not found — apt install fluidsynth")
        cmd = [
            "fluidsynth",
            "-s",
            "-a",
            "alsa",
            "-o",
            f"audio.alsa.device={self._alsa_device}",
            "-o",
            f"synth.gain={self._gain}",
            "-g",
            str(self._gain),
            str(self._sf2),
        ]
        self._proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        time.sleep(1.5)
        if self._proc.poll() is not None:
            err = (self._proc.stderr.read() if self._proc.stderr else "") or ""
            raise RuntimeError(f"fluidsynth exited early: {err[:500]}")
        logger.info(
            "FluidSynth started (stdin shell) sf2=%s alsa=%s",
            self._sf2,
            self._alsa_device,
        )

    def _shell(self, line: str) -> None:
        if self._proc is None or self._proc.stdin is None:
            return
        self._proc.stdin.write(line + "\n")
        self._proc.stdin.flush()

    def stop(self) -> None:
        if self._synth is not None:
            try:
                self._synth.delete()
            except Exception:
                pass
            self._synth = None
        if self._proc is not None:
            try:
                self._shell("quit")
            except Exception:
                pass
            self._proc.terminate()
            try:
                self._proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self._proc.kill()
            self._proc = None

    def program_select(self, program: int, bank: int = 0) -> None:
        ch = self._channel
        if self._synth is not None and self._sfid is not None:
            self._synth.program_select(ch, self._sfid, bank, program)
        else:
            self._shell(f"prog {ch} {program}")

    def note_on(self, note: int, velocity: int, channel: int | None = None) -> None:
        ch = self._channel if channel is None else channel
        note = keystep_note(note, ch)
        vel = max(1, min(127, int(velocity)))
        if self._synth is not None:
            self._synth.noteon(ch, note, vel)
        else:
            self._shell(f"noteon {ch} {note} {vel}")

    def note_off(self, note: int, velocity: int = 0, channel: int | None = None) -> None:
        ch = self._channel if channel is None else channel
        note = keystep_note(note, ch)
        if self._synth is not None:
            self._synth.noteoff(ch, note)
        else:
            self._shell(f"noteoff {ch} {note}")

    def cc(self, control: int, value: int, channel: int | None = None) -> None:
        ch = self._channel if channel is None else channel
        val = max(0, min(127, int(value)))
        if self._synth is not None:
            self._synth.cc(ch, control, val)
        else:
            self._shell(f"cc {ch} {control} {val}")

    def all_notes_off(self) -> None:
        self.cc(123, 0)

    def demo_note(self, midi_note: int = 60, velocity: int = 100, hold_sec: float = 1.2) -> None:
        self.start()
        self.note_on(midi_note, velocity)
        time.sleep(hold_sec)
        self.note_off(midi_note)
