# Deploy — GitHub auto-pull

The Pi **polls GitHub every 60 seconds**. When `main` has a new commit, it downloads the tarball, runs `install.sh --quick`, and **restarts** `supercollider` + `pi-ambient-synth`.

## Default appliance behavior

| Setting | Value |
|---------|--------|
| `DEPLOY_SOURCE` | `github` |
| `AUTO_PULL` | `1` |
| `GITHUB_REPO` | `samjhill/driftline-synth` |
| `GITHUB_BRANCH` | `main` |
| Poll interval | 60s (`pi-ambient-synth-deploy.timer`) |

## Your workflow

```bash
# On Mac — edit, commit, push
git add -A && git commit -m "..." && git push

# Pi picks it up within ~60s — no SD sync required
```

Watch on the Pi:

```bash
tail -f /var/log/pi-ambient-synth-deploy.log
journalctl -u pi-ambient-synth-deploy.service -f
```

The **e-ink display** shows boot and deploy progress:

`BOOT` (power on) → `WIFI` / `NET` → stepped `1/12`…`12/12` through `INSTALL` → `AUDIO` → `SYNTH` → `READY` → patch sigil.

First boot shows a **step counter** (e.g. `5/12`) and progress bar on the e-ink.

## First-time SD setup

```bash
./scripts/sync_to_sd_mac.sh   # writes deploy.conf with AUTO_PULL=1
```

Eject, boot Pi on Wi‑Fi. First boot installs; timer keeps pulling from GitHub.

Config is copied to `/etc/pi-ambient-synth/deploy.conf` so pulls work without re-reading the SD tree.

## Mac-only iteration (no push)

Override for one SD sync:

```bash
DEPLOY_SOURCE=boot AUTO_PULL=0 ./scripts/sync_to_sd_mac.sh
```

## Private repo

Create `deploy/secrets/github_token` (gitignored), sync to SD:

```bash
echo "ghp_xxxx" > deploy/secrets/github_token
./scripts/sync_to_sd_mac.sh
```

## Manual pull on Pi

```bash
sudo /home/pi/pi-ambient-synth/scripts/pi-deploy-sync.sh sync
```

## WiFi credentials

Never in git — see `deploy/secrets/network-config.local` and [deploy.md](deploy.md#wifi-credentials-never-in-git).
