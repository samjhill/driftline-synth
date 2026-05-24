# Handoff: Pi Ambient Synth (May 2026)

Use this document to continue work in a fresh chat (e.g. ChatGPT). **Next priority: get the Waveshare e-ink display working reliably on the Pi.**

---

## Project

- **Repo:** https://github.com/samjhill/driftline-synth  
- **Release tag (audible Pi path):** `v1.0.0-fluidsynth` on `main` (pushed May 2026)  
- **Install on Pi:** `/home/pi/pi-ambient-synth`  
- **SSH:** `pi@raspberrypi.local` (credentials via repo `scripts/lib/pi_ssh.sh` + `.pi-ssh-credentials` on dev Mac)

**Goal:** Headless ambient instrument — Arturia **KeyStep 32** → sound on **Pi 3.5 mm headphone jack**, patch **reseed** changes timbre, **e-ink** shows patch/status (reseed only for live note labels until display is stable).

---

## What works now (user-confirmed)

**FluidSynth V1** is the production audio path:

```text
KeyStep USB MIDI → pi-ambient-synth-midi.service (pi_midi_bridge.py)
                 → FluidSynth (stdin shell or pyfluidsynth)
                 → ALSA plughw:0,0 (bcm2835 Headphones)
                 → 3.5 mm jack
```

- **Root bug fixed:** FluidSynth **2.4.4** rejects stdin command `note`; must use **`noteon` / `noteoff`** (`src/fluidsynth_engine.py`).
- **SuperCollider / JACK** are **masked/disabled** on the Pi. Do not re-enable for production until FluidSynth path regresses.
- **`pi-ambient-jack-playback.timer`** was stopping MIDI every ~12s by starting `supercollider.service` (Conflicts with fluidsynth MIDI unit). Fix: mask SC, disable jack timer (`scripts/pi_enable_fluidsynth_engine.sh`).

**Enable on Pi after deploy:**

```bash
INSTALL_DIR=/home/pi/pi-ambient-synth ./scripts/pi_enable_fluidsynth_engine.sh
```

**Smoke:**

```bash
./scripts/fluidsynth_headphone_demo.sh   # C–E demo; user must hear
sudo systemctl restart pi-ambient-synth-midi
journalctl -u pi-ambient-synth-midi -f
```

**Config:** `config/default.yaml` → `audio.backend: fluidsynth`, `fluidsynth.alsa_device: plughw:0,0`, GM soundfont `/usr/share/sounds/sf2/FluidR3_GM.sf2`. Mode file: `/etc/pi-ambient-synth/audio-mode.conf` → `AUDIO_MODE=fluidsynth`.

**Reseed:** PiSugar button or KeyStep modifiers → `reseed.request` → bridge applies new GM program via `fluidsynth_client.apply_patch_voice` and spawns e-ink refresh (see below).

---

## Systemd layout (production)

| Unit | Role |
|------|------|
| `pi-ambient-synth-midi.service` | KeyStep → FluidSynth (holds fluidsynth child) |
| `pi-ambient-synth.service` | `main.py --no-eink`, patch state, PiSugar, reseed consumer — **no MIDI, no numpy/sigil import** |
| `pi-ambient-synth-monitor.service` | HTTP status on `:8080` |
| `supercollider.service` | **masked** in fluidsynth mode |
| `pi-ambient-jack-playback.timer` | **disabled** in fluidsynth mode |
| `pi-ambient-synth-boot-display.service` | Boot splash on e-ink |
| `pi-ambient-synth-audio-display.service` | Optional audio-phase display |

Drop-ins: `deploy/systemd/pi-ambient-synth-midi.fluidsynth.conf`, `pi-ambient-synth.fluidsynth.conf`.

---

## Archived / failed path (do not treat logs as success)

**SuperCollider + JACK** on Pi 3 headphones: long iteration, user heard **silence** despite `playNote` / monitor “proof” in logs. Policy: **audible confirmation only**; stop SC iteration when silent.

Isolation scripts (still in repo for hardware debug): `scripts/alsa_headphone_smoke_test.sh`, `jack_headphone_smoke_test.sh`, `sc_jack_known_good_test.sh`, `run_audio_isolation_on_pi.sh`.

---

## E-ink: current state and next task

### Intended behavior

- **On reseed:** `pi_midi_bridge._spawn_eink_restore()` runs `scripts/show_status.py --restore-patch` in a **detached subprocess** (main synth runs with `--no-eink` to avoid SIGBUS).
- **Config** (`config/default.yaml` → `eink:`):
  - `enabled: true`
  - `skip_numpy_sigil: true` — use text/status renderer, not numpy sigils (SIGBUS risk).
  - `show_playing_note: false` — live note labels were ~25s per refresh; leave off until panel is stable.
  - `update_on_reseed: true`
  - Waveshare **2.13" V4**, 250×122, `busy_active_high: true`, `GPIOZERO_PIN_FACTORY=lgpio`.

### Likely failure modes (documented in `docs/troubleshooting.md`)

1. **GPIO busy** — another process owns SPI (historically **GhostRoll** / ingest): `ghostroll-watch.service`, `ghostroll-eink-waveshare213v4.py`. Fix: `scripts/disable_ghostroll_on_boot.sh`, `scripts/free_eink_for_ambient.sh`.
2. **Running e-ink scripts as root** — causes `got root` / busy pin issues; always **`sudo -u pi`**.
3. **SIGBUS** if `main.py` or monitor imports **numpy** / `visual_generator` in the long-lived synth process — production uses `--no-eink` and `skip_sigil` / `skip_numpy_sigil`.
4. **Deploy timer** used to full-flash e-ink every 60s — should be fixed in current `main`; verify after pull.
5. **Stuck busy pin** after kill -9 — may need reboot.
6. **Wrong Waveshare driver** — bundled driver uses `class EPD` inside module; vendor copy under `vendor/waveshare`.

### Key files for e-ink work

| Path | Purpose |
|------|---------|
| `src/eink_display.py` | Waveshare wrapper |
| `src/eink_lock.py` | Exclusive lock for SPI |
| `src/status_display.py` | Text/status rendering |
| `src/eink_note_display.py` | Live note labels (currently disabled) |
| `src/visual_generator.py` | Sigil art (numpy — avoid in Pi production process) |
| `scripts/show_status.py` | CLI: phases, `--restore-patch` |
| `scripts/boot_display.sh` | Boot / forced status |
| `scripts/test_eink.py` | Basic panel test |
| `scripts/test_eink_patch_display.py` | Patch restore test |
| `scripts/diagnose_eink_gpio.sh` | Who holds GPIO |
| `scripts/disable_eink_for_audio_debug.sh` | Stop display services during audio debug |
| `scripts/refresh_eink.py` | Manual refresh |
| `/var/log/pi-ambient-synth-eink.log` | Runtime log on Pi |

### Suggested e-ink acceptance criteria

1. `python scripts/test_eink.py` on Pi shows a visible update, no GPIO busy.
2. `EINK_FORCE=1 ./scripts/boot_display.sh ready "Test" "OK" ""` as user **pi**.
3. Reseed (PiSugar or KeyStep) updates the panel with patch name / status within ~30s (no white flash loop).
4. `pi-ambient-synth` and `pi-ambient-synth-midi` stay **active**; no SIGBUS in `journalctl -u pi-ambient-synth`.
5. Optional later: enable `eink.show_playing_note` with sane `note_refresh_seconds`.

### First commands on Pi for e-ink debug

```bash
cd ~/pi-ambient-synth
bash scripts/diagnose_eink_gpio.sh
ls /dev/spidev*
tail -40 /var/log/pi-ambient-synth-eink.log
.venv/bin/python scripts/test_eink.py
sudo -u pi env EINK_FORCE=1 ./scripts/boot_display.sh ready "Test" "e-ink" ""
.venv/bin/python scripts/show_status.py --restore-patch
```

Monitor page: `http://<pi-ip>:8080/` (also tails e-ink log).

---

## Dev machine → Pi

```bash
./scripts/deploy_to_pi.sh          # rsync + restart (if used)
source scripts/lib/pi_ssh.sh && pi_ssh_setup
pi_ssh pi@raspberrypi.local '...'
pi_ssh_sudo pi@raspberrypi.local '...'
```

**Do not** rely on GitHub auto-pull on the Pi unless explicitly re-enabled (`scripts/disable_github_auto_pull.sh` may have been used).

---

## Human verification policy

Automated checks and journal lines (**`playNote`**, monitor proof chord, `FLUIDSYNTH_HEADPHONE_DEMO_DONE_USER_MUST_CONFIRM`) are **not** proof of sound. User must confirm **heard** vs **silence** on the physical jack.

---

## Recent git history (context)

- `v1.0.0-fluidsynth` — FluidSynth V1 + noteon fix + enable/isolation scripts  
- Prior tags: `v0.3.0-gentle-genres`, `v0.2.0-pi-ambient-alsa`, etc.  
- Commits before fluidsynth tag still mention SC/Flues paths; **Pi production intent is fluidsynth** until e-ink + audio are both stable.

---

## Open questions for e-ink session

1. Does `test_eink.py` work on the Pi **right now** after fluidsynth work (GPIO still free)?
2. Does `--restore-patch` run on reseed and log errors to `/var/log/pi-ambient-synth-eink.log`?
3. Is GhostRoll or another ingest project still installed on this SD card?
4. Should sigils stay text-only permanently on Pi 3, or is a numpy SIGBUS fix (venv ABI / separate process only) desired?

---

## E-ink implementation (May 2026)

- Canonical refresh: `scripts/eink_show_patch_status.sh` (user `pi`, lock `/tmp/pi-ambient-synth-eink.lock`, 35s timeout).
- Reseed/startup: `pi_midi_bridge` spawns that script detached; skips if lock held.
- Busy pin: cache at `/var/lib/pi-ambient-synth/eink-busy-active-high`; `EINK_BUSY_TIMEOUT` on failure.
- Monitor: `eink-status.json` + last update row on `:8080`.

*Audio user-confirmed; e-ink requires visible panel confirmation.*
