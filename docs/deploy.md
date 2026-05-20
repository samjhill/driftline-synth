# Deploy & quick iteration

Automatic install on first boot, plus SHA-based updates from the SD card or GitHub.

## How it works

```text
Mac: ./scripts/sync_to_sd_mac.sh
       → writes deploy/deploy.conf (git SHA)
       → rsyncs code to /Volumes/bootfs/pi-ambient-synth/
       → writes user-data for cloud-init first boot

Pi first boot: cloud-init runs pi-deploy-sync.sh bootstrap
Pi every boot + every 90s: timer runs pi-deploy-sync.sh sync
       → if boot deploy SHA ≠ installed SHA → rsync + install.sh --quick
```

## Mac workflow (fastest iteration)

1. Edit code on your Mac.
2. Insert SD card (or leave in reader).
3. Sync:

```bash
./scripts/sync_to_sd_mac.sh
```

4. On the Pi: **reboot**, or wait ~90 seconds for the deploy timer.
5. Check log on Pi: `tail -f /var/log/pi-ambient-synth-deploy.log`

No `git push` required — the Pi reads from the **boot partition** copy.

## GitHub SHA workflow

Push to GitHub, then either:

**A) Set SHA on SD from Mac**

```bash
DEPLOY_SOURCE=github \
GITHUB_REPO=youruser/driftline-synth \
DEPLOY_SHA=abc1234 \
./scripts/sync_to_sd_mac.sh
```

**B) Edit on SD** `bootfs/pi-ambient-synth/deploy/deploy.conf`:

```ini
DEPLOY_SOURCE=github
DEPLOY_SHA=full40charcommitorshort
GITHUB_REPO=samjhill/driftline-synth
ENABLE_SERVICES=1
```

## WiFi credentials (never in git)

Copy examples and edit locally (gitignored):

```bash
cp deploy/network-config.example deploy/secrets/network-config.local
# edit SSID/password, then:
./scripts/sync_to_sd_mac.sh
```

The Pi downloads `https://github.com/<repo>/archive/<sha>.tar.gz` when the SHA changes.

## deploy.conf fields

| Field | Meaning |
|-------|---------|
| `DEPLOY_SOURCE` | `boot` (default) or `github` |
| `DEPLOY_SHA` | Version id; change triggers reinstall |
| `DEPLOY_SHA_FULL` | Full git hash (informational) |
| `GITHUB_REPO` | `owner/repo` for github mode |
| `ENABLE_SERVICES` | `1` = enable synth systemd units |

## Manual commands on Pi

```bash
sudo /home/pi/pi-ambient-synth/scripts/pi-deploy-sync.sh sync
sudo systemctl start pi-ambient-synth-deploy.service
sudo systemctl status pi-ambient-synth-deploy.timer
```

## Force cloud-init first-boot again

Changing WiFi or `user-data` only re-runs if cloud-init thinks it's a new instance. Edit `meta-data` `instance_id` on the boot partition to a new value, or run deploy sync manually.

## Troubleshooting

- **No auto-install**: Ensure `user-data` exists on boot root (sync script copies it).
- **Updates ignored**: Check `cat /home/pi/pi-ambient-synth/.deploy_sha` vs `boot/firmware/pi-ambient-synth/deploy/deploy.conf`.
- **GitHub fetch fails**: Pi needs network; SHA must exist on GitHub (pushed).
