# Recovery mode

Restore a **stable musical instrument** after factory/autobringup experiments.

**In scope:** FluidSynth → headphones, KeyStep MIDI, web monitor, reseed.  
**Out of scope:** e-ink, autobringup, cloud-init SD prep, Mac offline rootfs surgery, SuperCollider, JACK, GhostRoll.

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
- **Reseed:** KeyStep gestures (see `docs/keystep_reseed.md`) or monitor UI

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
