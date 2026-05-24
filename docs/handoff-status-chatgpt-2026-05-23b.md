# Pi Ambient Synth — Status Update for ChatGPT (23 May 2026, evening)

Handoff after **fast first-boot redesign** + ongoing **first-boot / e-ink / SSH** debugging. Use this to continue without re-litigating solved threads.

---

## Project

| Item | Value |
|------|--------|
| **Repo** | https://github.com/samjhill/driftline-synth |
| **Tag (audio baseline)** | `v1.0.0-fluidsynth` on `main` |
| **Local tree (Mac)** | `~/Documents/opensource/driftline-synth` — **large uncommitted diff** (first-boot, e-ink service, SD sync) |
| **Pi install path** | **`/home/sam/pi-ambient-synth`** (Imager user is **sam**, not `pi`) |
| **SSH** | **`ssh sam@raspberrypi.local`** — same password as set in Raspberry Pi Imager |
| **Legacy SSH helpers** | `scripts/lib/pi_ssh.sh` may still assume `pi@` — update or override host/user |

**Hardware:** Raspberry Pi **3 Model B**, Arturia **KeyStep 32**, **Waveshare 2.13" e-Paper HAT V4** (rev 2.1 B/W), headphones on **3.5 mm** (`plughw:0,0`).

**WiFi (local, gitignored):** `deploy/secrets/network-config.local` — SSID `cottage`, 2.4 GHz, password has spaces (YAML quoted). Copied to SD `network-config` by `sync_to_sd_mac.sh`.

---

## Production audio stack (sacred — do not regress)

```text
KeyStep USB → pi-ambient-synth-midi.service (pi_midi_bridge.py)
            → FluidSynth (stdin: noteon / noteoff)
            → ALSA plughw:0,0
            → headphone jack
```

- **V1 only:** No SuperCollider, JACK, Qt/Xvfb, GhostRoll, numpy sigils for production.
- **Enable on Pi:** `scripts/pi_enable_fluidsynth_engine.sh`
- **Mode:** `/etc/pi-ambient-synth/audio-mode.conf` → `AUDIO_MODE=fluidsynth`
- **Proof:** Only **audible** jack output counts.

---

## E-ink architecture (current target)

**Single owner:** `pi-ambient-synth-eink.service` → `scripts/eink_service.py` + queue (`scripts/eink_enqueue.py`, `src/eink_queue.py`). Other processes must **enqueue**, not touch GPIO/SPI.

**Boot / first-boot display (separate, dependency-light):**

| Component | Role |
|-----------|------|
| `scripts/eink_early_progress.py` | Phases: BOOT, WIFI, SSH OK, APT, PYTHON, SYNTH, AUDIO OK — stdlib + vendored Waveshare + PIL; init aligned with `eink_official_minimal_test.py` |
| `scripts/eink_boot_early.sh` | Wrapper; logs to `boot-logs/eink-early.log` on boot partition |
| `systemd/pi-ambient-synth-eink-early.service` | Runs after `local-fs`, before `cloud-init` — **replaces unreliable cloud-init `bootcmd` e-ink** |
| `scripts/firstboot-light.sh` | Fast: e-ink, rsync SD → home, SSH status, start heavy |
| `scripts/firstboot-heavy.sh` | Slow background: `deploy/pi-v1-apt.list`, `install-v1-heavy.sh`, FluidSynth enable, e-ink service |

**User-confirmed:** `eink_official_minimal_test.py` **visibly** works when GhostRoll/parallel holders are gone (white → black → white). Blank panel during first boot = **orchestration/timing**, not dead hardware.

**GPIO:** `busy_active_high: false` in `config/default.yaml`; ReadBusy polling like minimal test (not 10 ms noop).

---

## Fast first-boot redesign (implemented in repo, may not be on SD yet)

**Goal:** SSH in ~2–4 min; e-ink BOOT &lt; 60 s; no SC/JACK apt on first boot; full install in background.

### Phase A — Mac (`scripts/build_factory_sd_mac.sh` → `sync_to_sd_mac.sh`)

- Repo + `vendor/waveshare` + V1 wheels (`requirements-pi-v1.txt`, no numpy) on boot partition
- `deploy/user-data` — **no `packages:` block** (apt in cloud-init blocked SSH for 10+ min)
- `deploy/deploy.conf`: `FACTORY_BOOT=1`, `AUDIO_MODE=fluidsynth`
- `pi-ambient-firstboot-status.txt` on boot partition (readable from Mac)
- Strips legacy **`cmdline.txt` `systemd.run=...pi-ambient-synth-firstboot.sh`** if present (from old `flash_sd_mac.sh` — runs full `install.sh` before cloud-init)

### Phase B — Pi

1. **cloud-init** — enable SSH, copy systemd units, start **eink-early** then **firstboot-light**, exit (no inline `install.sh`)
2. **firstboot-light** — detect user **sam** vs **pi** (`scripts/lib/pi_install_user.sh`), rsync to `/home/sam/pi-ambient-synth`, e-ink SSH OK, start heavy
3. **firstboot-heavy** — minimal apt, offline venv, `pi_enable_fluidsynth_engine.sh`, systemd drop-ins for **sam** user paths

**Docs:** `docs/fast-first-boot.md`, `scripts/check_sd_boot_mac.sh`

**Key files:**

- `deploy/user-data`, `deploy/pi-v1-apt.list`
- `systemd/pi-ambient-synth-firstboot-{light,heavy,eink-early}.service`
- `scripts/firstboot-{light,heavy}.sh`, `scripts/install-v1-heavy.sh`
- `scripts/lib/firstboot_status.sh` — appends to boot status file + `/var/log/pi-ambient-synth-firstboot.log`

---

## Current user situation (blocking)

User **re-flashed** with Imager + **fixed** `user-data` (no blocking packages) + confirmed WiFi secrets + Imager user **`sam@raspberrypi.local`**.

**After ~3+ minutes:**

- **No visible BOOT** on e-ink
- **Cannot SSH** (Mac scan: Pi **not in ARP** on LAN — likely WiFi not joined or wrong IP, not only slow install)

**Likely causes identified in session:**

1. **Imager user `sam` vs paths hardcoded to `/home/pi`** — fixed in repo (`pi_install_user.sh`, firstboot + systemd drop-ins); **must re-sync SD**
2. **E-ink in cloud-init `bootcmd` too early** — GPIO/SPI not ready; fails silently — fixed with **`pi-ambient-synth-eink-early.service`**
3. **`eink_early_progress.py` init** — updated to match official minimal test (`module_exit`, `module_init` check, PIL image size `(epd.height, epd.width)`)
4. **SSH command** — use **`ssh sam@raspberrypi.local`**, not `pi@`
5. **WiFi** — Pi not on LAN until `network-config` applies; 2.4 GHz only; check router DHCP

**Not yet verified on hardware after latest fixes** — user needs one more SD sync cycle.

---

## SD prep checklist (Mac, Pi powered off)

```bash
sudo ./scripts/wipe_cloud_init_mac.sh
./scripts/build_factory_sd_mac.sh /Volumes/bootfs
./scripts/check_sd_boot_mac.sh /Volumes/bootfs
```

Confirm:

- `user-data` has **eink-early** + **firstboot-light**, **no** `packages:`
- **No** `pi-ambient-synth-firstboot` in `cmdline.txt`
- `pi-ambient-synth/scripts/firstboot-light.sh` exists
- `vendor/waveshare/waveshare_epd` bundled

Boot Pi → within ~1–2 min expect **BOOT** on panel.

If still blank: power off, read on Mac:

```text
/Volumes/bootfs/pi-ambient-firstboot-status.txt
/Volumes/bootfs/pi-ambient-synth/boot-logs/eink-early.log
```

Paste those for diagnosis (cloud-init ran? `module_init` failed?).

---

## What’s intentionally retired for V1

- SuperCollider / JACK / `pi_enable_ambient_engine.sh` for production
- GhostRoll units — mask all: `ghostroll-eink`, `ghostroll-watch`, `ghostroll-wifi-setup`
- Full `install.sh` apt set on first boot (SC + jackd2) — use `install-v1-heavy.sh` / `pi-v1-apt.list` instead
- `pi-deploy-sync.sh bootstrap` inline in cloud-init — replaced by firstboot services
- numpy / live note display on e-ink for V1

---

## Acceptance criteria (user-defined)

| Check | Target |
|-------|--------|
| E-ink BOOT | &lt; 60 s after power-on |
| SSH | 2–4 min (`sam@raspberrypi.local`) |
| Boot status file | Updates on `/boot/firmware/pi-ambient-firstboot-status.txt` |
| First-boot apt | No supercollider / jackd2 |
| Audio | Eventually **AUDIO OK** on e-ink; audible FluidSynth |
| Second boot | Fast (markers skip full install) |

---

## Mac commands reference

| Command | Purpose |
|---------|---------|
| `./scripts/build_factory_sd_mac.sh /Volumes/bootfs` | Factory SD after Imager |
| `./scripts/check_sd_boot_mac.sh` | Pre-boot SD validation |
| `./scripts/read_pi_logs_mac.sh` | Boot + root logs from SD |
| `./scripts/wipe_cloud_init_mac.sh` | Force cloud-init re-run |

---

## Next steps for ChatGPT

1. Confirm user **re-synced SD after** `sam` user + `eink-early` service commits (not just earlier `user-data` without packages).
2. If e-ink still blank: analyze `eink-early.log` + `pi-ambient-firstboot-status.txt` from boot partition.
3. If SSH fails but e-ink works: WiFi / `network-config` / router DHCP; try Ethernet USB gadget or monitor.
4. After SSH: `systemctl status pi-ambient-synth-eink-early pi-ambient-synth-firstboot-{light,heavy} pi-ambient-synth-midi`; `tail /var/log/pi-ambient-synth-firstboot.log`.
5. Do **not** re-enable SC/JACK or parallel e-ink boot units without user ask.
6. Audio changes only with explicit user approval; prove with headphone demo + KeyStep.

---

## Constraints (do not violate)

- E-ink: one GPIO owner (`pi-ambient-synth-eink.service`); queue from MIDI/monitor only.
- Audio must stay up if e-ink crashes.
- Visible panel = proof for e-ink; audible jack = proof for audio.
- Minimize scope; match existing script style.
