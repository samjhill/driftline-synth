# Pi Ambient Synth — Quick status for ChatGPT (23 May 2026)

## Project

- **Repo:** https://github.com/samjhill/driftline-synth (local uncommitted: fast first-boot + e-ink early boot)
- **Hardware:** Pi 3 B, KeyStep 32, Waveshare 2.13" e-Paper HAT V4 rev 2.1, headphones `plughw:0,0`
- **Production audio (sacred):** FluidSynth V1 only — KeyStep → `pi-ambient-synth-midi` → FluidSynth → ALSA. No SC/JACK/GhostRoll on first boot.
- **Imager user:** **sam** (not `pi`) → `ssh sam@raspberrypi.local`, install dir **`/home/sam/pi-ambient-synth`**

## What works (confirmed earlier)

- **Audio:** FluidSynth path proven audible when enabled on Pi.
- **E-ink hardware:** `scripts/eink_official_minimal_test.py` visibly works after GhostRoll purge; BUSY pin often stuck HIGH (poll + continue, like minimal test).
- **Runtime e-ink:** Single owner `pi-ambient-synth-eink.service` + queue (`eink_enqueue.py`).

## Fast first-boot architecture (in repo)

| Phase | What |
|-------|------|
| **Mac** | `build_factory_sd_mac.sh` → sync repo, wheels (no numpy), Waveshare vendor, `user-data`, WiFi, `FACTORY_BOOT=1`, `AUDIO_MODE=fluidsynth` |
| **cloud-init** | No heavy `packages:`; `bootcmd` runs `eink_boot_early.sh`; `runcmd` enables SSH + `eink-early` + `firstboot-light` |
| **firstboot-light** | rsync SD → home, detect sam/pi, e-ink SSH OK, start **firstboot-heavy** async |
| **firstboot-heavy** | `pi-v1-apt.list` (fluidsynth only), `install-v1-heavy.sh`, `pi_enable_fluidsynth_engine.sh`, systemd drop-ins for sam |

**Validation gate:** `scripts/check_sd_boot_mac.sh` must pass before boot (brutal checks: no `#cloud-config` in `network-config`, no cmdline `systemd.run`, no `/home/pi` in user-data, eink-early files, etc.).

**User sequence:**

```bash
sudo ./scripts/wipe_cloud_init_mac.sh
./scripts/build_factory_sd_mac.sh /Volumes/bootfs
./scripts/check_sd_boot_mac.sh /Volumes/bootfs
```

## First-boot debugging — what we learned (latest boots)

### 1. `network-config` had `#cloud-config` header (critical bug)

- That header is **only** for `user-data`, not `network-config`.
- Symptom: status file only `CLOUD_INIT bootcmd` — **runcmd never ran** (no firstboot-light, no SSH from runcmd).
- **Fix:** strip header in `sync_to_sd_mac.sh`; `check_sd_boot_mac.sh` fails if present; fixed `network-config.local` + example.

### 2. E-ink early boot *ran* but looked blank

- `boot-logs/eink-early.log` showed `eink BOOT ok` ~52s after power-on.
- `No module named 'PIL'` at bootcmd (python3-pil only in firstboot-heavy apt).
- Old fallback: flash black → **clear white → `epd.sleep()`** → panel looks off/blank.
- **Fix:** no-PIL path = official-style **white → black, hold ~4s on BOOT**, skip sleep on BOOT; marker dir `mkdir -p /var/lib/pi-ambient-synth`.

### 3. WiFi never connected on failing boots

- cloud-init: `wlan0 | False`, no IP; `modules-final` stuck “Waiting on external services”.
- **Fix:** valid `network-config` (no `#cloud-config`); mask `NetworkManager-wait-online` in bootcmd; 2.4 GHz SSID `cottage` in secrets.

### 4. SD log forensics (Mac, Pi off)

```bash
sudo ./scripts/read_pi_logs_mac.sh /Volumes/bootfs
```

Read: `pi-ambient-firstboot-status.txt`, `pi-ambient-synth/boot-logs/eink-early.log`, root `cloud-init-output.log`.

**Good boot status file should include:** `bootcmd eink_boot_early`, `runcmd start`, `eink-early + firstboot-light`.

## Acceptance (still in progress)

| Check | Status |
|-------|--------|
| `check_sd_boot_mac.sh` passes before boot | User achieved |
| BOOT visible &lt; 60s | In progress — log OK, visibility fixes need re-sync |
| SSH sam@ 2–4 min | Blocked when WiFi down |
| No SC/JACK apt on first boot | Designed via `pi-v1-apt.list` |
| AUDIO OK after heavy stage | Not verified this session |

## Key files (first boot)

- `deploy/user-data`, `deploy/pi-v1-apt.list`, `deploy/secrets/network-config.local` (no `#cloud-config`)
- `scripts/firstboot-{light,heavy}.sh`, `scripts/install-v1-heavy.sh`
- `scripts/eink_boot_early.sh`, `scripts/eink_early_progress.py`
- `scripts/lib/pi_install_user.sh`, `scripts/check_sd_boot_mac.sh`
- `systemd/pi-ambient-synth-{eink-early,firstboot-light,firstboot-heavy}.service`
- `docs/fast-first-boot.md`, `docs/troubleshooting.md`

## Do not regress

- Do not re-enable SuperCollider/JACK/GhostRoll for V1 production.
- Do not touch GPIO outside `pi-ambient-synth-eink.service` (queue only).
- Audio changes only with user approval; prove with headphone demo + KeyStep.
- Do not use log OK as proof of visible e-ink or audible audio.

## Next steps for ChatGPT

1. User should **re-sync SD** with latest `eink_early_progress.py`, `eink_boot_early.sh`, `user-data`, `network-config` strip.
2. Boot → confirm **full-black BOOT** on panel and status file lines for runcmd.
3. Confirm WiFi/DHCP → `ssh sam@raspberrypi.local`.
4. If SSH works: `systemctl status pi-ambient-synth-firstboot-heavy`, `tail /var/log/pi-ambient-synth-firstboot.log`.
5. Do not change audio/SC/JACK/GhostRoll unless user asks.
