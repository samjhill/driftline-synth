# Recovery mode

Restore a **stable musical instrument** after factory/autobringup experiments.

**In scope:** FluidSynth → headphones, KeyStep MIDI, web monitor, reseed (monitor, KeyStep, **PiSugar button**), **e-ink (optional add-on)**.  
**Out of scope:** autobringup, cloud-init SD prep, Mac offline rootfs surgery, SuperCollider, JACK, GhostRoll.

## Fresh install (manual)

1. Flash **Raspberry Pi OS Lite** with Raspberry Pi Imager (enable SSH, set user e.g. `sam`, WiFi optional).
2. Boot the Pi. Wait for SSH.
3. On your laptop:
   ```bash
   ssh sam@raspberrypi.local
   ```
4. On the Pi:
   ```bash
   sudo apt-get update
   sudo apt-get install -y git
   git clone https://github.com/samjhill/driftline-synth.git ~/pi-ambient-synth
   cd ~/pi-ambient-synth
   ./scripts/install_recovery_mode.sh
   ```
5. Reboot (recommended):
   ```bash
   sudo reboot
   ```
6. SSH back in and validate:
   ```bash
   cd ~/pi-ambient-synth
   ./scripts/recovery_validation.sh
   ```

Expected last line: **`RECOVERY_OK`**

## Daily use

```bash
cd ~/pi-ambient-synth
./scripts/start_recovery_synth.sh
```

- **Monitor:** `http://<pi-ip>:8080/` (or `http://raspberrypi.local:8080/`)
- **Audio:** KeyStep → `pi-ambient-synth-midi` → FluidSynth → `plughw:0,0` → headphones
- **Reseed:** PiSugar **single tap** (if Power Manager installed), KeyStep gestures (`docs/keystep_reseed.md`), or monitor **New patch**

## PiSugar button (optional)

Recovery keeps **e-ink off** but wires the PiSugar physical button to randomize the patch (same as monitor reseed).

1. Install [PiSugar Power Manager](https://docs.pisugar.com/docs/product-wiki/battery/pisugar-power-manager) on the Pi:
   ```bash
   cd ~/pi-ambient-synth
   ./scripts/install_pisugar_server.sh
   ```
   Pick **PiSugar 2 Pro / 2 Plus** (or your board) when `dpkg-reconfigure` prompts.

2. Register the button (after model detect if battery reads `I2C not connected`):
   ```bash
   sudo ./scripts/detect_pisugar_model.sh   # if button still dead after install
   ./scripts/setup_recovery_pisugar_button.sh
   ```

3. Test: single tap on the PiSugar button — you should hear a new GM program within a second or two. Debug:
   ```bash
   journalctl -u pi-ambient-synth-midi -f
   echo "get button_shell single" | nc -U /tmp/pisugar-server.sock
   ```

Re-run `./scripts/start_recovery_synth.sh` after reboot; it re-registers the button if `pisugar-server` is active.

## E-ink display (optional add-on)

Uses the **ingest / GhostRoll known-good pattern**: render a **250×122 PNG**, `pi_eink_waveshare213v4.py` watches it and drives the panel with **stock `waveshare-epd`** (root, no lgpio queue).

```bash
cd ~/pi-ambient-synth
sudo ./scripts/enable_recovery_eink.sh
./scripts/validate_recovery_eink.sh
```

Reseed and monitor updates write `/var/lib/pi-ambient-synth/eink-status.png`; the e-ink service picks up changes within ~2s.

Debug: `journalctl -u pi-ambient-synth-eink -f`

## What gets installed

| Component | Unit / script |
|-----------|----------------|
| MIDI + FluidSynth + reseed | `pi-ambient-synth-midi.service` |
| Web monitor | `pi-ambient-synth-monitor.service` |

**Not** enabled: `pi-ambient-synth.service` (main controller / e-ink path), autobringup, firstboot, e-ink, SuperCollider, Flues, JACK.

## Prove audio without KeyStep

```bash
./scripts/fluidsynth_headphone_demo.sh
```

You should hear a short chord in the headphones.

## If validation fails

```bash
journalctl -u pi-ambient-synth-midi -b --no-pager | tail -40
journalctl -u pi-ambient-synth-monitor -b --no-pager | tail -20
./scripts/list_midi_devices.py
```

| `FAILED_STAGE` | Likely fix |
|----------------|------------|
| `midi_unit_not_active` | `sudo systemctl restart pi-ambient-synth-midi` |
| `alsa_plughw_open` | `sudo ./scripts/setup_pi_audio.sh`; check headphone jack |
| `monitor_http` | `sudo systemctl restart pi-ambient-synth-monitor` |
| `midi_not_fluidsynth_backend` | Re-run `./scripts/install_recovery_mode.sh` |

## Re-run recovery install

Safe to run again on the same SD:

```bash
./scripts/install_recovery_mode.sh
```

It masks legacy units and rewrites recovery systemd drop-ins.

## Philosophy

The **synth** is the product. Unattended SD imaging and e-ink can return after this path is boringly reliable.
