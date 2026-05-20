# Pi Ambient Synth

A headless Raspberry Pi generative ambient synthesizer controlled by an **Arturia KeyStep** over USB MIDI, with a **Waveshare 2.13" E-Ink** display showing a deterministic “patch sigil” for each curated sound scene.

Power on → connect KeyStep → play immediately. No menus, no laptop required after setup.

## What It Is

Two-process architecture:

- **SuperCollider** — polyphonic synth, texture drone, delay, reverb, limiter
- **Python** — MIDI, curated patch generation, OSC, e-ink visuals, state

```text
KeyStep (USB MIDI) → Python → OSC → SuperCollider → Audio
                      ↓
                 E-Ink display (patch sigil)
```

## Hardware

| Item | Purpose |
|------|---------|
| Raspberry Pi 4B/5 | Brain |
| Arturia KeyStep | Keys, arp, sequencer, transport |
| USB data cable | KeyStep ↔ Pi (not power-only) |
| Waveshare 2.13" E-Ink HAT V4 | Patch identity display |
| USB audio interface or Pi jack | Output |

See [docs/hardware_setup.md](docs/hardware_setup.md) for wiring.

```text
     ┌──────────┐  USB   ┌─────────────┐
     │ KeyStep  │───────▶│ Raspberry Pi│
     └──────────┘        │  + E-Ink HAT│──▶ speakers
                         └─────────────┘
```

## Install (Raspberry Pi)

### Automatic (recommended)

On your Mac, with the SD card mounted as `bootfs`:

```bash
chmod +x scripts/sync_to_sd_mac.sh scripts/pi-deploy-sync.sh
./scripts/sync_to_sd_mac.sh
```

Eject, boot the Pi on Wi‑Fi. First boot runs **cloud-init** → installs deps, enables services.  
After code changes, run `sync_to_sd_mac.sh` again and **reboot** (or wait ~90s). See [docs/deploy.md](docs/deploy.md).

### Manual SSH install

```bash
git clone <repo-url> ~/pi-ambient-synth
cd ~/pi-ambient-synth
chmod +x install.sh scripts/run_dev.sh
./install.sh --enable-services
sudo reboot
```

Adjust paths in `systemd/*.service` if the repo lives outside `/home/pi/pi-ambient-synth`.

## First Sound Test

```bash
# 1. Start engine
sclang synth/ambient_engine.scd

# 2. In another terminal
python3 -m venv .venv && .venv/bin/pip install mido python-rtmidi python-osc PyYAML Pillow numpy
.venv/bin/python scripts/test_osc.py
```

You should hear a test note. Then:

```bash
.venv/bin/python src/main.py --no-eink
```

Play the KeyStep.

## MIDI Debug

```bash
.venv/bin/python scripts/list_midi_devices.py
.venv/bin/python scripts/list_midi_devices.py --monitor
.venv/bin/python src/main.py --debug-midi
```

## E-Ink Test (on Pi with HAT)

```bash
.venv/bin/python scripts/test_eink.py
.venv/bin/python src/main.py --generate-visual /tmp/sigil.png
```

## Manual Run

```bash
./scripts/run_dev.sh --no-eink
# or separately:
sclang synth/ambient_engine.scd
python src/main.py
```

## Boot Startup

```bash
./install.sh --enable-services
sudo systemctl start supercollider pi-ambient-synth
sudo systemctl status supercollider pi-ambient-synth
```

Services restart automatically on crash.

## Controls

| Action | Mapping |
|--------|---------|
| Play notes | KeyStep keyboard / arp / seq |
| New patch (reseed) | SHIFT + PLAY |
| Save favorite | SHIFT + STOP |
| Evolve mode | SHIFT + RECORD |
| Panic | `python src/main.py --panic` |

If Shift is not transmitted over MIDI, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Project Layout

```text
config/          YAML config and scales
synth/           SuperCollider ambient_engine.scd
src/             Python orchestration
scripts/         Dev and hardware test scripts
systemd/         Service units
tests/           Unit tests
docs/            Setup, usage, troubleshooting
state/           Runtime patch persistence (gitignored)
```

## Tests

```bash
.venv/bin/pip install pytest PyYAML Pillow numpy
.venv/bin/pytest tests/ -v
```

## Troubleshooting

| Problem | See |
|---------|-----|
| No MIDI | [troubleshooting.md](docs/troubleshooting.md#keystep-lights-up-but-no-midi) |
| No sound | [troubleshooting.md](docs/troubleshooting.md#no-sound) |
| E-ink blank | [troubleshooting.md](docs/troubleshooting.md#e-ink-display-does-not-update) |
| Shift combos | [troubleshooting.md](docs/troubleshooting.md#random--shift-button-combo-not-detected) |

## License

MIT — use and modify for your own ambient appliance.
