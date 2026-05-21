#!/usr/bin/env python3
"""Pi Ambient Synth — orchestration layer."""

from __future__ import annotations

import argparse
import logging
import random
import signal
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from config_loader import install_root, load_config, resolve_data_path
from eink_display import EInkDisplay
from logging_setup import setup_logging
from midi_controller import MidiController, save_midi_status
from osc_client import OscClient
from note_names import format_active_notes
from patch_generator import PatchGenerator
from patch_resolve import resolve_current_patch
from patch_model import Patch
from midi_clock import MidiClock
from play_tracker import PlayTracker
from sigil_export import export_sigil
from state_store import StateStore
from pisugar_battery import BatterySnapshot, read_battery_snapshot
from visual_generator import VisualGenerator

logger = logging.getLogger("pi_ambient_synth")


class PiAmbientSynth:
    def __init__(self, config: dict, no_eink: bool = False, debug_midi: bool = False):
        self.config = config
        self.debug_midi = debug_midi
        if no_eink:
            self.config.setdefault("eink", {})["enabled"] = False

        app = config.get("app", {})
        root = install_root()
        self._marker_dir = Path(app.get("marker_dir", "/var/lib/pi-ambient-synth"))
        self._sc_ready_marker = self._marker_dir / "sc-engine-ready"
        self.state_store = StateStore(
            resolve_data_path(app.get("state_path", "./state/current_patch.json"), root),
            resolve_data_path(app.get("favorites_path", "./state/favorites.json"), root),
        )
        self.patch_gen = PatchGenerator(config)
        self.osc = OscClient(config)
        self._visual: VisualGenerator | None = None
        self.eink = EInkDisplay(config)
        self.midi = MidiController(config)
        self.play = PlayTracker()
        self.clock = MidiClock()
        self._sigils_dir = resolve_data_path(
            config.get("midi", {}).get("sigils_dir", "./state/sigils"), root
        )
        self._export_sigil = config.get("midi", {}).get("export_sigil_on_reseed", True)
        self._patch: Patch | None = None
        self._running = True
        self._reseed_morph = config.get("audio", {}).get("patch_morph_seconds", 6.0)
        self._last_note_eink_time = 0.0
        self._last_battery_poll = 0.0
        self._last_charge_poll = 0.0
        self._battery_snapshot: BatterySnapshot | None = None

    @property
    def visual(self) -> VisualGenerator:
        if self._visual is None:
            self._visual = VisualGenerator(self.config)
        return self._visual

    def _battery_for_display(self) -> BatterySnapshot | None:
        ps = self.config.get("pisugar", {})
        if not ps.get("enabled", False) or not ps.get("show_on_display", True):
            return None
        snap = read_battery_snapshot(self.config)
        if snap.available:
            self._battery_snapshot = snap
            return snap
        return self._battery_snapshot if self._battery_snapshot else None

    def _resolve_patch(self) -> Patch:
        had_saved = self.state_store.load_current() is not None
        patch = resolve_current_patch(self.config, self.state_store, self.patch_gen)
        if had_saved:
            logger.info("Loaded saved patch: %s", patch.summary())
        else:
            logger.info("Generated default patch: %s", patch.summary())
            self.state_store.save_current(patch)
        return patch

    def _wait_for_sc_engine(self, timeout: float = 55.0) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self._sc_ready_marker.is_file():
                logger.info("SuperCollider engine ready (%s)", self._sc_ready_marker)
                return True
            time.sleep(0.25)
        logger.warning(
            "SuperCollider engine not ready after %.0fs — notes may be silent until SC loads",
            timeout,
        )
        return False

    def startup(self) -> None:
        vol = self.config.get("audio", {}).get("default_volume", 0.65)
        self.osc.set_volume(vol)
        if self.config.get("eink", {}).get("enabled", True):
            self.eink.init()
            self.eink.show_status(
                "synth",
                "Loading synth",
                "patch + MIDI",
                "",
                config=self.config,
                battery=self._battery_for_display(),
            )
        self._patch = self._resolve_patch()
        save_midi_status(
            self.config,
            connected=False,
            port_name=None,
            listening=False,
            state="starting",
        )
        self._wait_for_sc_engine()
        self.osc.send_patch(self._patch)
        self._update_display(self._patch)
        self._wire_midi()
        if not self.midi.open():
            logger.warning("MIDI unavailable — OSC/visual still active")
            save_midi_status(self.config, connected=False, port_name=None, listening=False)
        else:
            self.midi.start()
            save_midi_status(
                self.config,
                connected=True,
                port_name=self.midi.port_name,
                listening=True,
                state="running",
            )

    def _wire_midi(self) -> None:
        self.midi.on_note_on = self._on_note_on
        self.midi.on_note_off = self._on_note_off
        self.midi.on_hold_change = self._on_hold_change
        self.midi.on_reseed_requested = self.reseed
        self.midi.on_freeze_requested = self.freeze
        self.midi.on_evolve_toggle_requested = self.toggle_evolve
        self.midi.on_recall_favorite = self.recall_favorite
        self.midi.on_weather_change = self._on_weather
        self.midi.on_clock = self._on_clock

        if self.debug_midi:
            orig_cc = self.midi.on_cc

            def debug_cc(c, v, ch):
                logger.info("MIDI CC ch=%s cc=%s val=%s", ch, c, v)
                if orig_cc:
                    orig_cc(c, v, ch)

            self.midi.on_cc = debug_cc

            def debug_note_on(n, v, ch):
                logger.info("MIDI note_on ch=%s note=%s vel=%s", ch, n, v)
                self._on_note_on(n, v, ch)

            def debug_note_off(n, v, ch):
                logger.info("MIDI note_off ch=%s note=%s", ch, n)
                self._on_note_off(n, v, ch)

            self.midi.on_note_on = debug_note_on
            self.midi.on_note_off = debug_note_off

    def _sync_texture(self, root: int | None) -> None:
        self.osc.texture_root(root)
        self.osc.arp_active(self.play.arp_active)

    def _on_hold_change(self, on: bool) -> None:
        if self.play.set_hold(on):
            self.osc.hold_latch(on)
            self.osc.texture_root(self.play.lowest_active_note())
            logger.info("Hold latch: %s", on)

    def _on_clock(self) -> None:
        bpm = self.clock.tick()
        self.osc.clock_bpm(bpm)

    def _refresh_playing_note_display(
        self,
        velocity: int | None = None,
        *,
        force: bool = False,
    ) -> None:
        eink_cfg = self.config.get("eink", {})
        if not eink_cfg.get("show_playing_note", True):
            return
        if not eink_cfg.get("enabled", True) or not self._ensure_eink():
            return

        now = time.monotonic()
        interval = float(eink_cfg.get("note_refresh_seconds", 0.5))
        if not force and now - self._last_note_eink_time < interval:
            return
        self._last_note_eink_time = now

        active = self.play.active_notes
        if not active:
            if self._patch:
                self._update_display(self._patch)
            return

        title = format_active_notes(active)
        subtitle = f"vel {velocity}" if velocity is not None else ""
        if self._patch:
            patch_line = self._patch.name[:22]
            subtitle = f"{subtitle}  {patch_line}".strip() if subtitle else patch_line
        self.eink.show_status(
            "playing",
            title,
            subtitle,
            "",
            config=self.config,
            battery=self._battery_for_display(),
        )

    def _on_note_on(self, note: int, velocity: int, channel: int) -> None:
        root, arp_changed = self.play.note_on(note)
        if arp_changed:
            self.osc.arp_active(self.play.arp_active)
        if root is not None:
            self.osc.texture_root(root)
        if self.midi.is_duo_low(note):
            self._refresh_playing_note_display(velocity)
            return
        self.osc.note_on(note, velocity)
        self._refresh_playing_note_display(velocity)

    def _on_note_off(self, note: int, velocity: int, channel: int) -> None:
        root = self.play.note_off(note)
        if not self.play.hold_latched:
            self.osc.texture_root(root)
        if self.midi.is_duo_low(note):
            self._refresh_playing_note_display(force=not self.play.active_notes)
            return
        self.osc.note_off(note, velocity)
        self._refresh_playing_note_display(force=not self.play.active_notes)

    def _ensure_eink(self) -> bool:
        if not self.config.get("eink", {}).get("enabled", True):
            return False
        if self.eink.available:
            return True
        return self.eink.init()

    def _update_display(self, patch: Patch, favorite: bool = False) -> None:
        if not self._ensure_eink():
            return
        img = self.visual.render_patch(patch, battery=self._battery_for_display())
        if favorite:
            from PIL import ImageDraw

            draw = ImageDraw.Draw(img)
            draw.text((img.width - 14, img.height - 12), "*", fill=0)
        if self.config.get("eink", {}).get("update_on_reseed", True):
            self.eink.show_patch(patch, img)

    def reseed(self) -> None:
        old = self._patch
        seed = random.randint(0, 2**31 - 1)
        evolve = self._patch.evolve_enabled if self._patch else False
        if self._patch:
            self._patch = self.patch_gen.morph_from(self._patch, seed, evolve)
        else:
            self._patch = self.patch_gen.generate(seed=seed, evolve_enabled=evolve)

        if self.config.get("eink", {}).get("enabled", True) and old:
            wipe = self.visual.render_reseed_wipe(old, self._patch)
            self.eink.show_image(wipe)
            time.sleep(0.35)

        self.state_store.save_current(self._patch)
        self.osc.reseed_transition(2.0)
        self.osc.reseed(seed)
        morph = max(self._reseed_morph, 7.0)
        self.osc.send_patch(self._patch, morph_seconds=morph)
        self._update_display(self._patch)
        if self._export_sigil:
            path = export_sigil(self._patch, self.visual, self._sigils_dir)
            self.osc.tape_grit(0.2, 3.0)
            if self.config.get("eink", {}).get("enabled", True):
                self.eink.show_status(
                    "ready",
                    "Sigil saved",
                    path.name[:22],
                    "",
                    config=self.config,
                    battery=self._battery_for_display(),
                )
            logger.info("Sigil exported: %s", path)
        logger.info("Reseeded: %s", self._patch.summary())

    def freeze(self) -> None:
        if not self._patch:
            return
        self.state_store.add_favorite(self._patch)
        self._update_display(self._patch, favorite=True)

    def recall_favorite(self) -> None:
        fav = self.state_store.load_last_favorite()
        if not fav:
            logger.info("No favorite to recall")
            return
        self._patch = fav
        self.state_store.save_current(self._patch)
        self.osc.send_patch(self._patch, morph_seconds=4.0)
        self._update_display(self._patch, favorite=True)
        logger.info("Recalled favorite: %s", self._patch.summary())

    def _on_weather(self, amount: float) -> None:
        self.osc.weather(amount)
        if self.config.get("eink", {}).get("enabled", True):
            label = "clear" if amount > 0.66 else ("mist" if amount > 0.33 else "fog")
            self.eink.show_status(
                "idle",
                "Weather",
                label,
                f"{int(amount * 100)}%",
                config=self.config,
                battery=self._battery_for_display(),
            )

    def toggle_evolve(self) -> None:
        if not self._patch:
            return
        self._patch.evolve_enabled = not self._patch.evolve_enabled
        self.osc.evolve(self._patch.evolve_enabled)
        self.osc.companion(self._patch.evolve_enabled)
        self.state_store.save_current(self._patch)
        self._update_display(self._patch)
        logger.info("Evolve mode: %s", self._patch.evolve_enabled)

    def panic(self) -> None:
        self.osc.panic()
        self.osc.all_notes_off()
        self.osc.panic_bloom()

    def shutdown(self) -> None:
        self._running = False
        self.midi.stop()
        save_midi_status(self.config, connected=False, port_name=None, listening=False)
        if self.config.get("eink", {}).get("clear_on_shutdown", False):
            self.eink.clear()
        else:
            self.eink.sleep()

    def _battery_power_changed(
        self, prev: BatterySnapshot | None, snap: BatterySnapshot
    ) -> bool:
        if prev is None:
            return True
        return (
            prev.charging != snap.charging
            or prev.plugged != snap.plugged
            or prev.shows_charging_indicator != snap.shows_charging_indicator
        )

    def _redraw_patch_on_eink(self, *, force: bool = False) -> None:
        if not self._patch or not self.config.get("eink", {}).get("enabled", True):
            return
        if (
            not force
            and self.play.active_notes
            and self.config.get("eink", {}).get("show_playing_note", True)
        ):
            return
        self._update_display(self._patch)

    def _maybe_refresh_battery_display(self) -> None:
        ps = self.config.get("pisugar", {})
        if not ps.get("enabled", False):
            return
        now = time.monotonic()
        prev = self._battery_snapshot

        charge_interval = float(ps.get("charge_poll_seconds", 5))
        if now - self._last_charge_poll >= charge_interval:
            self._last_charge_poll = now
            snap = read_battery_snapshot(self.config)
            if snap.available and self._battery_power_changed(prev, snap):
                self._battery_snapshot = snap
                state = "charging" if snap.shows_charging_indicator else "on battery"
                logger.info(
                    "PiSugar %s%% (%s, %sV)",
                    snap.display_percent,
                    state,
                    f"{snap.voltage_v:.2f}" if snap.voltage_v else "?",
                )
                self._redraw_patch_on_eink(force=True)

        interval = float(ps.get("poll_seconds", 90))
        if now - self._last_battery_poll < interval:
            return
        self._last_battery_poll = now
        prev = self._battery_snapshot
        snap = read_battery_snapshot(self.config)
        if not snap.available:
            return
        self._battery_snapshot = snap
        if prev is None or prev.display_percent == snap.display_percent:
            return
        if not self._patch:
            return
        self._redraw_patch_on_eink(force=False)

    def run(self) -> None:
        self.startup()
        logger.info("Pi Ambient Synth running — Ctrl+C to exit")
        try:
            while self._running:
                if self.midi.is_listening:
                    self.midi.poll()
                self._maybe_refresh_battery_display()
                time.sleep(0.002)
        except KeyboardInterrupt:
            pass
        finally:
            self.shutdown()


def main() -> int:
    global config
    parser = argparse.ArgumentParser(description="Pi Ambient Synth")
    parser.add_argument("--config", type=Path, default=None)
    parser.add_argument("--debug-midi", action="store_true")
    parser.add_argument("--no-eink", action="store_true")
    parser.add_argument("--generate-visual", type=Path, metavar="PATH")
    parser.add_argument("--panic", action="store_true")
    args = parser.parse_args()

    config = load_config(args.config)
    setup_logging(config.get("app", {}).get("log_level", "INFO"))

    if args.generate_visual:
        gen = PatchGenerator(config)
        patch = gen.generate()
        vis = VisualGenerator(config)
        img = vis.render_patch(patch)
        args.generate_visual.parent.mkdir(parents=True, exist_ok=True)
        img.save(args.generate_visual)
        logger.info("Saved visual for %s → %s", patch.summary(), args.generate_visual)
        return 0

    if args.panic:
        OscClient(config).panic()
        return 0

    app = PiAmbientSynth(config, no_eink=args.no_eink, debug_midi=args.debug_midi)

    def handle_sig(_sig, _frame):
        app.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sig)
    signal.signal(signal.SIGTERM, handle_sig)
    app.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
