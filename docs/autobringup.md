# Autonomous bring-up (prove on Pi first)

**Strategy:** prove the architecture under normal Linux systemd on the Pi. Defer fully unattended Mac rootfs (`e2cp` / `debugfs`) enablement until this path passes.

## Layers

| Layer | Role |
|--------|------|
| **Boot sentinel** | Linux boot, writable bootfs, `pi-boot-sentinel.txt` — see [boot-sentinel.md](boot-sentinel.md) |
| **cloud-init `user-data.autobringup`** | SSH only (WiFi via `network-config`) — no apt, no bring-up |
| **`pi-ambient-autobringup.service`** | Full pipeline on ext4 root at `multi-user.target` — **install on the Pi** |
| **Mac `install_autobringup_rootfs.sh`** | Optional / deferred (`AUTBRINGUP_ROOTFS=1`) — not required for phase 1 |

Do **not** start long jobs from cmdline `systemd.run` — transient units kill children.

## Phase 1 — Mac SD prep

```bash
sudo ./scripts/wipe_cloud_init_mac.sh
./scripts/build_autobringup_sd_mac.sh /Volumes/bootfs
./scripts/check_autobringup_sd_mac.sh /Volumes/bootfs
```

Boot the Pi until:

- `pi-boot-sentinel.txt` exists (Linux + bootfs)
- SSH works (`ssh` file + WiFi from `network-config`)

## Phase 1 — Install autobringup on the Pi (after SSH)

```bash
cd /boot/firmware/pi-ambient-synth   # or /boot/pi-ambient-synth
sudo ./scripts/install_autobringup_on_pi.sh
sudo reboot
```

Equivalent manual steps:

```bash
sudo cp /boot/firmware/pi-ambient-synth/systemd/pi-ambient-autobringup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pi-ambient-autobringup.service
```

Re-run from scratch: `sudo ./scripts/install_autobringup_on_pi.sh --reset`

## Phase 1 — Validate

**On the Pi:**

```bash
sudo ./scripts/validate_autobringup_on_pi.sh
```

**Or on Mac (Pi off, SD inserted):**

```bash
./scripts/read_autobringup_report_mac.sh /Volumes/bootfs
```

### Acceptance (this phase)

| Check | Pass |
|--------|------|
| `systemctl is-enabled pi-ambient-autobringup` | unit survives reboot |
| `AUTOBRINGUP_START` in `boot-logs/autobringup.log` | systemd launched service |
| `DRIFTLINE_BRINGUP_REPORT.txt` | real report (not Mac placeholder) |
| `eink.log` contains `EINK_SENT_V4` | sent to panel |
| `audio.log` | FluidSynth install stages |
| KeyStep | `KEYSTEP_FOUND` in report/audio log (if plugged in) |

If `AUTOBRINGUP_START` is missing → unit not installed or service failed (`journalctl -u pi-ambient-autobringup -b`).

## Stages (systemd service only)

`SYSTEMD_FORENSICS` → `USER_DETECT` → `RSYNC` → `NETWORK_DIAG` → `SSH_ENABLE` → `EINK_ISOLATED_TEST` → `AUDIO_INSTALL` → `AUDIO_SELF_TEST` → `KEYSTEP_DIAG` → `APP_ENABLE` → `FINAL_REPORT`

FluidSynth V1 only. E-ink: `eink_official_minimal_test.py` only.

## Phase 2 — Factory SD from Mac (later)

When phase 1 passes reliably:

```bash
AUTBRINGUP_ROOTFS=1 ./scripts/build_autobringup_sd_mac.sh /Volumes/bootfs
sudo ./scripts/install_autobringup_rootfs.sh /Volumes/bootfs
```

Treat Mac offline ext4 surgery as best-effort until proven unnecessary.
