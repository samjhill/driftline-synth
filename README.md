# Pi Ambient Synth

A small-box ambient music instrument: plug in power, connect a keyboard, and play calm, evolving sounds. No computer screen, no menus, no patch lists to scroll through.

Each new “scene” gets its own abstract drawing on a small e-ink screen — like a postcard for that sound.

## What you get

- **Instant play** — Power on, wait for boot, play keys. The Pi handles the rest.
- **New landscapes on demand** — One button combo gives you a fresh sound world (still musical, not random noise).
- **A quiet display** — Shows the name of the scene and a unique black-and-white “map” for it.
- **Hands-on control** — An Arturia KeyStep keyboard (with arp/sequencer) is the whole interface.

Good for: bedside ambient, living-room noodling, a dedicated object that isn’t another app.

## What you need


| Thing                                                 | Why                                                  |
| ----------------------------------------------------- | ---------------------------------------------------- |
| **Raspberry Pi 4 or 5**                               | The brains (Pi 3 may work but is slower)             |
| **Arturia KeyStep**                                   | Keys and transport buttons                           |
| **USB cable (data, not charge-only)**                 | Connects keyboard to Pi                              |
| **Speakers or headphones**                            | Pi headphone jack or a small USB audio interface     |
| **Waveshare 2.13″ e-ink HAT** (optional but intended) | Shows the scene “sigil” — install on the GPIO header |


```text
  KeyStep ──USB──▶ Raspberry Pi + e-ink hat ──▶ speakers
```

More wiring detail: [docs/hardware_setup.md](docs/hardware_setup.md)

## How it works (simple version)

Inside the Pi, two programs cooperate:

1. **Sound engine** — Makes the actual audio (layers, reverb, gentle motion).
2. **Helper** — Listens to the keyboard, picks new scenes, updates the display, saves your last sound.

You only touch the KeyStep. The Pi is meant to stay out of the way.

## First-time setup

### Easiest path (Mac + microSD card)

1. Flash Raspberry Pi OS onto the card (or use a card that already boots).
2. On your Mac, with the card’s `bootfs` volume mounted, from this project folder run:

```bash
chmod +x scripts/sync_to_sd_mac.sh
./scripts/sync_to_sd_mac.sh
```

That copies the synth, Wi‑Fi settings (from a local file you create — see below), and auto-install instructions. **Wi‑Fi passwords are not stored in GitHub** — they live only in `deploy/secrets/` on your Mac.

1. Eject the card, put it in the Pi, power on, connect speakers and the KeyStep.
2. **First boot** — use `./scripts/build_factory_sd_mac.sh` (FluidSynth V1). Expect **SSH in ~2–4 minutes**; apt/venv run in the background (`firstboot-heavy`). E-ink shows `BOOT`, `SSH OK`, `APT`, `AUDIO OK`. See [docs/fast-first-boot.md](docs/fast-first-boot.md).
3. When it’s ready, play the keyboard. If you need SSH: try `ssh pi@raspberrypi.local` (default password `raspberry` — change it).

After setup, code updates can arrive from GitHub automatically about once a minute when you push changes. Details: [docs/deploy.md](docs/deploy.md).

### Wi‑Fi file (one-time on your Mac)

```bash
cp deploy/network-config.example deploy/secrets/network-config.local
# Edit deploy/secrets/network-config.local with your network name and password
```

Run `sync_to_sd_mac.sh` again whenever you change code or Wi‑Fi. It pre-downloads Pi **aarch64 Python wheels** onto the card (`vendor/wheels/`) so first boot skips slow PyPI downloads. Refresh with `FORCE_BUNDLE=1 ./scripts/sync_to_sd_mac.sh` (uses `pip3.11` from Homebrew).

## Playing it


| What you want                            | On the KeyStep (usual mapping)                   |
| ---------------------------------------- | ------------------------------------------------ |
| **Play normally**                        | Keys, arp, or sequencer — same as any synth      |
| **New sound scene**                      | **SHIFT + PLAY**                                 |
| **Save this scene as a favorite**        | **SHIFT + STOP**                                 |
| **Bring back last favorite**             | Press **STOP** twice quickly                     |
| **Living, slowly changing sound**        | **SHIFT + RECORD** (toggles “evolve”)            |
| **Fog ↔ clear blend**                    | Mod wheel (CC1) — “weather”                      |
| **Low keys = drone, high keys = melody** | Notes below middle C# (55) vs above — “duo” mode |


If **SHIFT + button** doesn’t work, your KeyStep may not send Shift over USB. See [docs/troubleshooting.md](docs/troubleshooting.md) and run debug mode (developers section below).

More detail on the fun features: [docs/fun-phase-1.md](docs/fun-phase-1.md), [docs/fun-phase-2.md](docs/fun-phase-2.md), [docs/fun-phase-3.md](docs/fun-phase-3.md).

## Everyday use

1. Power on the Pi.
2. When Wi‑Fi connects, the e-ink shows **your Pi’s IP** (e.g. `192.168.1.50`).
3. On a phone or laptop on the same network, open **`http://<that-ip>:8080/`** to monitor the synth (patch, services, logs). mDNS: `http://raspberrypi.local:8080/`.
4. Play the KeyStep.

The monitor has no password — for your home LAN only.

You do **not** need a laptop connected while playing.

## If something’s wrong


| Symptom                         | Start here                                                                            |
| ------------------------------- | ------------------------------------------------------------------------------------- |
| Keyboard lights up but no sound | USB cable might be power-only — use a data cable                                      |
| Can’t find Pi on network        | Check router device list; see [docs/troubleshooting.md](docs/troubleshooting.md)      |
| E-ink stays blank               | Check HAT seated and SPI enabled — [docs/troubleshooting.md](docs/troubleshooting.md) |
| New scene button does nothing   | [docs/troubleshooting.md](docs/troubleshooting.md) — MIDI debug                       |


Full guide: [docs/usage.md](docs/usage.md)

---

## For developers

Technical architecture, manual install, tests, and service units.

### Architecture

```text
KeyStep (USB MIDI) → Python → OSC → SuperCollider → audio
                      ↓
                 E-ink (patch sigil)
```

### Manual install on the Pi

```bash
git clone git@github.com:samjhill/driftline-synth.git ~/pi-ambient-synth
cd ~/pi-ambient-synth
chmod +x install.sh scripts/run_dev.sh
./install.sh --enable-services
sudo reboot
```

### Dev / test commands

**Before pushing `synth/ambient_engine.scd` changes** (catches SC syntax without deploying to the Pi):

```bash
./scripts/validate_ambient_engine.sh          # static only (fast, no SuperCollider)
./scripts/validate_ambient_engine.sh --sclang # full smoke test on Linux; on macOS runs static only
pytest tests/test_ambient_engine_scd.py -v
```

Install SuperCollider locally: `brew install --cask supercollider` (macOS) or `sudo apt install supercollider` (Linux).

```bash
./scripts/run_dev.sh --no-eink
python scripts/list_midi_devices.py --monitor
python src/main.py --debug-midi
python src/main.py --panic
pytest tests/ -v
```

### Boot services

```bash
./install.sh --enable-services
sudo systemctl status supercollider pi-ambient-synth
```

### Project layout

```text
config/     Settings and scales
synth/      SuperCollider engine
src/        Python app
scripts/    SD sync, tests, deploy
docs/       Setup and troubleshooting
```

## License

MIT — use and adapt for your own projects.