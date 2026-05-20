# Usage

## Daily Operation

1. Power on the Raspberry Pi.
2. Wait ~15 seconds for SuperCollider and the orchestrator to start (if systemd enabled).
3. Play the KeyStep — notes route to the ambient synth immediately.
4. Use KeyStep transport combos to change scenes (see below).

## Controls (V1)

| Action | Primary mapping | Fallback |
|--------|-----------------|----------|
| Reseed / new patch | SHIFT + PLAY | CC 102 with shift, or debug mapping |
| Save favorite | SHIFT + STOP | CC 103 with shift |
| Toggle evolve | SHIFT + RECORD | CC 104 with shift |

The KeyStep may **not** transmit Shift over MIDI. Run debug mode to learn your unit's messages:

```bash
python src/main.py --debug-midi
python scripts/list_midi_devices.py --monitor
```

Document observed messages and adjust `src/midi_controller.py` if needed.

## Manual Run

```bash
# Terminal 1 — SuperCollider
sclang synth/ambient_engine.scd

# Terminal 2 — Python
python src/main.py --no-eink   # without display
python src/main.py             # with display on Pi
```

Or use `scripts/run_dev.sh`.

## CLI

```bash
python src/main.py
python src/main.py --debug-midi
python src/main.py --no-eink
python src/main.py --generate-visual ./out.png
python src/main.py --panic
```

## Evolve Mode

When enabled, SuperCollider slowly drifts filter, LFO, and texture parameters. Toggle with SHIFT+RECORD (or fallback). The e-ink display shows `~evolve` when active.

## Favorites

SHIFT+STOP saves the current patch to `state/favorites.json`. A `*` marker appears on the display after freeze.
