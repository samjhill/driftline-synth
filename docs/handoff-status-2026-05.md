# Pi Ambient Synth — Status Update (May 2026)

Handoff for continuing work in ChatGPT or another session.

---

## Project

- **Repo:** https://github.com/samjhill/driftline-synth  
- **Release:** `v1.0.0-fluidsynth` on `main` (pushed)  
- **Pi path:** `/home/pi/pi-ambient-synth`  
- **SSH:** `pi@raspberrypi.local` — use repo `scripts/lib/pi_ssh.sh` + `.pi-ssh-credentials` (sshpass) from dev Mac; plain `ssh` may fail if keychain has no keys.

**Hardware:** Raspberry Pi **3 Model B Rev 1.2**, Arturia KeyStep 32, **Waveshare 2.13" e-Paper HAT V4 driver board rev 2.1** (user-confirmed silkscreen), headphones on **3.5 mm jack**.

---

## What works (user-confirmed)

### Audio — FluidSynth V1 (production)

```text
KeyStep USB → pi-ambient-synth-midi.service (pi_midi_bridge.py)
            → FluidSynth (stdin shell; pyfluidsynth optional)
            → ALSA plughw:0,0 (bcm2835 Headphones)
            → 3.5 mm jack
```

- **Critical fix:** FluidSynth **2.4.4** stdin must use **`noteon` / `noteoff`**, not `note` (`src/fluidsynth_engine.py`).
- **Mode file:** `/etc/pi-ambient-synth/audio-mode.conf` → `AUDIO_MODE=fluidsynth`
- **Enable on Pi:** `./scripts/pi_enable_fluidsynth_engine.sh`
- **Do not re-enable** SuperCollider / JACK for production until user hears a regression.

### Systemd (fluidsynth mode)

| Unit | State / intent |
|------|----------------|
| `pi-ambient-synth-midi.service` | KeyStep + FluidSynth child — **must stay active** |
| `pi-ambient-synth.service` | `main.py --no-eink`, patch/PiSugar — no MIDI in-process |
| `pi-ambient-synth-monitor.service` | HTTP status `:8080` |
| `supercollider.service` | **masked / disabled** |
| `pi-ambient-jack-playback.timer` | **disabled** (was restarting SC every ~12s and killing MIDI) |
| `pi-flues-synth.service` | May still be **enabled on Pi** — unrelated to FluidSynth path; consider disabling to reduce confusion |

**Policy:** Audible success = user hears sound on the jack. Logs, monitor “proof” chords, and exit code 0 are **not** proof.

---

## What does NOT work — E-ink (blocked on hardware)

### User report

- **No visible change** on the panel after:
  - `scripts/eink_official_waveshare_v4_test.py` (Waveshare-equivalent demo)
  - `scripts/eink_sanity_flash.sh` (black → white → bars)
  - `scripts/eink_show_patch_status.sh` / `show_status.py --restore-patch`
  - `EINK_USE_DEV_SO=1` (C `DEV_Config.so` SPI path)
- User **reseat Pi 40-pin header**, power cycle — **still no change**.

### Software evidence (Pi 3, post-reseat)

| Observation | Value |
|-------------|--------|
| SPI | `/dev/spidev0.0` present, `dtparam=spi=on` |
| spidev smoke test | `xfer2` OK |
| Driver | `waveshare_epd.epd2in13_V4` (250×122, panel class 122×250) |
| BUSY GPIO 24 | **Reads 1 constantly** (stuck HIGH) |
| Init / tests | Exit **0**, logs say “initialized”, “Clear BLACK”, “Display bar” |
| Visual | **User sees nothing** |

**Conclusion:** Software sends commands; the **glass does not update**. Treat as **hardware / FPC / wrong HAT variant / dead panel** until a test produces a visible black flash or image.

### Likely causes (priority order)

1. **24-pin FPC ribbon** (driver PCB → e-ink glass) not seated — reseating the **Pi GPIO header does not fix this**.
2. Wrong product variant (**HAT (B)** tricolor, **HAT+** different pins) — user says **V4 rev 2.1** B&W HAT.
3. Dead panel, broken FPC, or faulty HAT — try another Pi or replacement HAT.
4. BUSY stuck HIGH is consistent with **no panel response** (not a software-only quirk we can patch around if SPI reaches nothing).

### E-ink software already in repo (for when hardware works)

| Item | Purpose |
|------|---------|
| `scripts/eink_show_patch_status.sh` | Canonical refresh: user `pi`, lock, 35s timeout |
| `scripts/eink_stop_competing_services.sh` | Stop `pi-ambient-synth-audio-display`, boot-display races |
| `scripts/eink_official_waveshare_v4_test.py` | Waveshare V4 demo (user must see black/white) |
| `scripts/eink_sanity_flash.sh` | High-contrast black/white/bars |
| `scripts/eink_hardware_report.sh` | SPI/BUSY report → `/tmp/eink-hardware-report.txt` |
| `src/eink_display.py` | Busy bypass when stuck HIGH, `refresh_wait_ms` (~8s) |
| `src/eink_lock.py` | Lock `/tmp/pi-ambient-synth-eink.lock` |
| `src/eink_status.py` | `eink-status.json` for monitor |
| `pi_midi_bridge._spawn_eink_restore()` | Detached `eink_show_patch_status.sh` on startup/reseed only |

**Config:** `eink.show_playing_note: false` (no live note labels). `skip_numpy_sigil: true` (avoid SIGBUS). Production `main.py` runs `--no-eink`.

**Marker dir:** `/var/lib/pi-ambient-synth/` — ensure owned by `pi` (was root-owned `last_eink_status` once, blocking JSON status).

### Do not do (e-ink)

- Do not treat e-ink log success as panel success.
- Do not re-enable SuperCollider/JACK to “fix” display.
- Do not block MIDI/audio on e-ink refresh (spawn detached subprocess only).
- Claiming GPIO **8** (CS) with `lgpio` **fails** (`GPIO busy`) — CS is hardware SPI CE0; upstream Waveshare leaves CS to spidev.

---

## Archived: SuperCollider / JACK path

Long iteration; user heard **silence** on Pi headphones despite logs showing `playNote` / monitor proof. Path abandoned for production in favor of FluidSynth V1. Isolation scripts remain: `scripts/alsa_headphone_smoke_test.sh`, `jack_headphone_smoke_test.sh`, etc.

---

## Pinout reference (standard 2.13" V4 HAT on Pi, BCM)

| Signal | BCM |
|--------|-----|
| RST | 17 |
| DC | 25 |
| CS | 8 (SPI CE0) |
| BUSY | 24 |
| PWR | 18 |

**HAT+** uses different pins (e.g. RST 11, BUSY 18) — wrong if user truly has standard V4.

---

## Commands cheat sheet (Pi)

```bash
cd ~/pi-ambient-synth

# Audio
systemctl is-active pi-ambient-synth-midi pi-ambient-synth
journalctl -u pi-ambient-synth-midi -f

# E-ink — stop races, then prove panel (USER EYES)
bash scripts/eink_stop_competing_services.sh
GPIOZERO_PIN_FACTORY=lgpio .venv/bin/python scripts/eink_official_waveshare_v4_test.py

# Hardware report
bash scripts/eink_hardware_report.sh
cat /tmp/eink-hardware-report.txt

# Production e-ink refresh (only after visible official test works)
./scripts/eink_show_patch_status.sh
```

From Mac:

```bash
cd driftline-synth && source scripts/lib/pi_ssh.sh && pi_ssh_setup
pi_ssh pi@raspberrypi.local '...'
pi_rsync ... pi@raspberrypi.local:/home/pi/pi-ambient-synth/...
```

---

## Suggested next steps for ChatGPT

### If continuing e-ink

1. User must confirm **FPC reseat** (24-pin on HAT, not Pi header) and run `eink_official_waveshare_v4_test.py` again.
2. If still blank → **hardware RMA / replacement HAT** or test on another Pi; stop software iteration.
3. When panel **visibly** updates: verify `eink_show_patch_status.sh` on reseed; monitor `:8080` e-ink row; keep audio services active.
4. Optionally disable `pi-ambient-synth-audio-display.service` permanently in deploy/enable scripts (already in `pi_enable_fluidsynth_engine.sh`).

### If focusing on product

- Reseed → GM program change + e-ink patch screen (once hardware works).
- PiSugar button → reseed (already wired via `reseed.request`).
- Monitor page fluidsynth-aware alerts (partially done in `monitor_server.py`).

---

## Open questions

1. After FPC reseat, does **official V4 test** show any full-black or full-white flash?
2. Exact product SKU on packaging (HAT vs HAT (B) vs HAT+)?
3. Should `pi-flues-synth.service` be disabled on this Pi to avoid confusion?
4. Commit unpushed e-ink work (busy wait, scripts, `epdconfig` vendor tweaks) or wait until panel confirmed?

---

*Audio: user-confirmed working (`v1.0.0-fluidsynth`). E-ink: software path exhausted; awaiting hardware fix or replacement.*
