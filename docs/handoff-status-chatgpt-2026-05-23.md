# Pi Ambient Synth — Status Update for ChatGPT (23 May 2026)

Handoff after SD re-image + e-ink boot-path work. Use this to continue in a new session without re-litigating solved threads.

---

## Project

| Item | Value |
|------|--------|
| **Repo** | https://github.com/samjhill/driftline-synth |
| **Tag (audio baseline)** | `v1.0.0-fluidsynth` on `main` |
| **Local tree (Mac)** | `~/Documents/opensource/driftline-synth` @ `6c277a6` (+ uncommitted e-ink/SD/install changes) |
| **Pi path** | `/home/pi/pi-ambient-synth` |
| **SSH** | `pi@raspberrypi.local` — from Mac: `source scripts/lib/pi_ssh.sh && pi_ssh_setup` then `pi_ssh` / `pi_rsync` (uses `.pi-ssh-credentials` + sshpass) |

**Hardware:** Raspberry Pi **3 Model B Rev 1.2**, Arturia **KeyStep 32**, **Waveshare 2.13" e-Paper HAT V4** driver board **rev 2.1** (B/W), headphones on **3.5 mm** (`plughw:0,0`).

---

## What works (user-confirmed)

### Audio — FluidSynth V1 (do not regress)

```text
KeyStep USB → pi-ambient-synth-midi.service (pi_midi_bridge.py)
            → FluidSynth (stdin: noteon / noteoff — not "note")
            → ALSA plughw:0,0
            → headphone jack
```

- **Fix:** FluidSynth 2.4.4 shell mode in `src/fluidsynth_engine.py`.
- **Enable on running Pi:** `./scripts/pi_enable_fluidsynth_engine.sh`
- **Mode file:** `/etc/pi-ambient-synth/audio-mode.conf` → `AUDIO_MODE=fluidsynth`
- **Keep masked/disabled:** `supercollider.service`, `pi-ambient-jack-playback.timer` (timer was restarting SC ~every 12s and breaking MIDI via systemd `Conflicts`).

**Proof policy:** Only **audible** output on the jack counts. Logs / monitor / exit 0 are not proof.

---

## E-ink — status changed (was “dead”, now “works with isolation”)

### User-visible breakthrough

After purging **prior-project** holders (especially **GhostRoll**), user reported the panel **flashed, cleared, went black, cleared** — matching `scripts/eink_official_minimal_test.py` (white → black → white).

**Classification: A** — hardware and V4 driver are fine; **contention from legacy services / GPIO races** was the blocker, not a dead panel.

### Root causes found in software

1. **GhostRoll** had left `ghostroll-eink.service`, `ghostroll-watch.service`, `ghostroll-wifi-setup.service` on the Pi; only `ghostroll-eink` was null-masked early — **watch/wifi stayed “disabled” but not always masked**.
2. **Parallel boot refreshes** — `boot-display`, `network-announce`, `eink-patch`, and **MIDI bridge startup e-ink** raced on one lock → `E-ink lock held — skip` in logs while the user saw a blank panel.
3. **`eink_show_patch_status.sh`** released `flock` **before** Python ran (bug).
4. **`show_status.py`** skipped if lock probe failed instead of **waiting** on the lock.
5. **BUSY BCM24 stuck HIGH** — app used a **10 ms ReadBusy noop**; the **official minimal test** polls BUSY then waits ~15 s. App path was updated to match.
6. **`boot_display` 50 s timeout** killed long refreshes before the panel finished.

### Fixes in repo (may be uncommitted / partially on Pi)

| Script / unit | Purpose |
|---------------|---------|
| `scripts/eink_kill_legacy_holders.sh` | Mask **all** GhostRoll + ingest/e-paper units; kill stray processes; remove `/usr/local` `waveshare_epd` |
| `scripts/eink_prepare_boot.sh` | Calls kill script at boot (systemd prepare unit) |
| `scripts/eink_boot_sequence.sh` | **Serialized:** splash → wait for LAN → network IP → patch |
| `systemd/pi-ambient-synth-eink-prepare.service` | Before display |
| `systemd/pi-ambient-synth-eink-boot.service` | Replaces parallel boot-display / network-announce / eink-patch |
| `scripts/eink_enable_boot_units.sh` | Enables prepare + eink-boot; **masks** legacy parallel units |
| `src/eink_display.py` | Stuck-HIGH ReadBusy like minimal test; optional skip deep sleep; `EINK_SKIP_PURGE` |
| `config/default.yaml` | `busy_active_high: false`, `refresh_wait_ms: 15000`, `boot_sequence_systemd`, `skip_startup_refresh` |
| `scripts/pi_midi_bridge.py` | Skips startup e-ink when systemd boot sequence owns refresh |
| `scripts/eink_purge_legacy_projects.sh` | Default = safe; `--aggressive` stops synth display units too |

**Do not** treat log “OK” as visible success without user eyes.

---

## SD card — fresh image (23 May 2026)

User **re-flashed with Raspberry Pi Imager**, re-inserted Mac **`/Volumes/bootfs`**.

**Completed on Mac** (`./scripts/sync_to_sd_mac.sh /Volumes/bootfs`):

- Project → `bootfs/pi-ambient-synth/` (~89 MB, vendor + wheels bundled)
- `ssh`, `user-data`, Wi‑Fi from `deploy/secrets/network-config.local`
- `dtparam=spi=on`, `country=US`
- `deploy/deploy.conf`: `DEPLOY_SOURCE=boot`, `ENABLE_SERVICES=1`, **`AUDIO_MODE=fluidsynth`**
- cloud-init `instance_id` rotated; **root FS cloud-init cache wiped** (first-boot runcmd will run)
- Card **ejected** — ready to boot Pi

**`install.sh` (local, synced to SD):** reads `AUDIO_MODE` from `deploy.conf`; on `--enable-services` runs **`pi_enable_fluidsynth_engine.sh`** instead of enabling SuperCollider.

**First boot expectation:** ~10–20 min; cloud-init → `pi-deploy-sync.sh bootstrap` → install + FluidSynth enable; e-ink may show BOOT / WIFI / INSTALL steps (user-data still uses older stepped `boot_display` messages; systemd **eink-boot** sequence on Pi depends on units installed by `install.sh`).

---

## Mac tooling

| Command | When |
|---------|------|
| `./scripts/sync_to_sd_mac.sh [/Volumes/bootfs]` | After Imager flash or code change |
| `./scripts/flash_sd_mac.sh diskN` | Full erase + flash (needs Terminal + admin; fixed `disk4` vs `disk5s1` regex bug) |
| `open scripts/FLASH_AND_SYNC_SD.command` | Interactive flash + sync |
| `DEFAULT_AUDIO_MODE=fluidsynth ./scripts/sync_to_sd_mac.sh` | Default for SD sync now |

**Secrets (gitignored):** `deploy/secrets/network-config.local`, `wpa_supplicant.conf.local`

---

## Pi state note

The **live Pi** may still reflect **pre-SD** state until the user boots the **new card**. Last SSH session: GhostRoll units **masked**, minimal test **exit 0**, boot sequence runs logged OK but user sometimes still saw blank when races/timeouts occurred — fixes above address that.

After new SD boot, verify:

```bash
systemctl is-enabled pi-ambient-synth-eink-prepare pi-ambient-synth-eink-boot
systemctl list-unit-files 'ghostroll*'
systemctl is-active pi-ambient-synth-midi
cat /etc/pi-ambient-synth/audio-mode.conf
```

E-ink proof on Pi:

```bash
cd ~/pi-ambient-synth
bash scripts/eink_kill_legacy_holders.sh
rm -f /tmp/pi-ambient-synth-eink.lock
.venv/bin/python scripts/eink_official_minimal_test.py epd2in13_V4
# User: VISIBLE_YES / VISIBLE_NO
sudo systemctl start pi-ambient-synth-eink-boot.service
```

---

## Systemd cheat sheet (FluidSynth production)

| Unit | Intent |
|------|--------|
| `pi-ambient-synth-midi.service` | **Keep active** — KeyStep + FluidSynth |
| `pi-ambient-synth.service` | `main.py --no-eink` |
| `pi-ambient-synth-monitor.service` | HTTP `:8080` |
| `pi-ambient-synth-eink-prepare` + `pi-ambient-synth-eink-boot` | Boot e-ink (new) |
| `supercollider.service` | **masked** |
| `ghostroll-*.service` | **masked** (all three) |

---

## Suggested next steps for ChatGPT

### If user boots new SD first

1. Confirm **audio** (KeyStep → jack) and **SSH**.
2. Confirm **e-ink** after boot: if blank, run kill script + `eink_official_minimal_test.py`; then `eink_enable_boot_units.sh` if units missing.
3. Do **not** re-enable SC/JACK/GhostRoll without user ask.

### If e-ink still blank on new SD

1. Run **only** `eink_kill_legacy_holders.sh` then **minimal test** (no app `show_status` until minimal works).
2. Check **FPC** (24-pin flex HAT PCB → glass) — Pi header reseat does not fix FPC.
3. Confirm HAT SKU (not HAT+ pinout).

### If committing Mac work

Uncommitted areas: `install.sh`, `eink_*` scripts/systemd, `eink_display.py`, `config/default.yaml`, `docs/troubleshooting.md`, `flash_sd_mac.sh`, etc. Commit when user asks.

---

## Open questions

1. Did user **boot the new SD** yet? Audio + e-ink on first boot?
2. After `eink-boot` sequence, does patch name show on glass?
3. Push uncommitted e-ink boot work to `main` or branch?
4. Update `deploy/user-data` to call `eink_boot_sequence.sh` instead of many parallel `boot_display` steps?

---

*Summary: **Audio = production FluidSynth (confirmed).** **E-ink = hardware OK; software needed legacy purge + serialized boot + BUSY/timeout fixes.** **SD = re-imaged + synced with fluidsynth + e-ink boot units; awaiting first boot on new card.*
