# Fast first boot (FluidSynth V1)

## Architecture (systemd-first)

| Layer | Role |
|-------|------|
| **Mac factory sync** | `ssh` file, repo on bootfs, minimal `user-data`, `pi-ambient-firstboot.service` |
| **cloud-init** | SSH on, WiFi (`network-config`), install + start **one** unit only |
| **pi-ambient-firstboot.service** | E-ink POST, rsync, WiFi wait, heavy trigger — explicit state machine |
| **SSH** | Independent of firstboot (enabled before firstboot runs) |

## Mac (before boot)

```bash
sudo ./scripts/wipe_cloud_init_mac.sh
./scripts/build_factory_sd_mac.sh /Volumes/bootfs
./scripts/check_sd_boot_mac.sh /Volumes/bootfs
```

## Status states (boot partition)

`pi-ambient-firstboot-status.txt` should show, in order:

`BOOT` → `FIRSTBOOT_START` → `POST_START` → `POST_DONE` → `RSYNC_*` → `SSH_READY` → `WIFI_*` → `HEAVY_*` → `FIRSTBOOT_DONE`

## Logs on SD

- `pi-ambient-firstboot-status.txt`
- `pi-ambient-synth/boot-logs/firstboot-eink.log`
- `pi-ambient-synth/boot-logs/firstboot-network.log` (every 15s during firstboot)
- `pi-ambient-wifi-debug.txt` (snapshot at end of WiFi wait)

## E-ink

Canonical test only: `scripts/eink_official_minimal_test.py` (white → black → white), run from **boot tree** before rsync.

On Pi: `sudo ./scripts/eink_known_good_direct_test.sh`

## SSH

```bash
ssh sam@raspberrypi.local   # or pi@ — match Pi Imager user
```

Should be up within **2–4 min** when WiFi works — does not wait for apt/heavy.

## Safe mode

After **3** failed firstboot runs, service disables itself (`/etc/pi-ambient-synth/firstboot-disabled`).
