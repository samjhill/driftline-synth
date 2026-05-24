# Boot sentinel (prove Pi boots this SD)

Stop cloud-init / firstboot / e-ink debugging until **`pi-boot-sentinel.txt`** exists on the boot partition.

## Factory SD (Mac)

```bash
sudo ./scripts/wipe_cloud_init_mac.sh
./scripts/build_factory_sd_mac.sh /Volumes/bootfs
sudo ./scripts/install_boot_sentinel_rootfs.sh /Volumes/bootfs   # if not run by sync
./scripts/check_sd_boot_mac.sh /Volumes/bootfs
```

`build_factory_sd_mac.sh` installs the sentinel on the **root** partition via e2tools when `sudo` works. If not, it adds a **cmdline** `systemd.run` fallback automatically.

**If check fails “NOT on SD root”:** run one of:

```bash
sudo ./scripts/install_boot_sentinel_rootfs.sh /Volumes/bootfs   # preferred
# or double-click scripts/INSTALL_BOOT_SENTINEL.command in Finder
# or cmdline only:
./scripts/install_boot_sentinel_cmdline.sh /Volumes/bootfs
```

**If `e2cp` fails on ext4** (common on Trixie images): the install script retries with `debugfs` from `brew install e2fsprogs`. Enable **Full Disk Access** for Terminal in System Settings → Privacy if you see permission errors on `/dev/rdisk*s2`.

## After 3–5 minutes powered on

Re-insert SD and check:

```bash
cat /Volumes/bootfs/pi-boot-sentinel.txt
# also try:
cat /Volumes/bootfs/pi-boot-sentinel.txt 2>/dev/null || true
```

| Result | Meaning |
|--------|---------|
| **File exists with date + `uname`** | Linux ran; bootfs writable — proceed to SSH / autobringup on Pi |
| **No file** | Pi not booting this SD, wrong arch, or boot not mounted |

## HDMI / serial (do this on one boot)

Connect **HDMI** (and keyboard if you have one). Note what you see:

- Rainbow splash only, then black?
- Kernel text scrolling?
- Login prompt (`sam` or `pi`)?
- `cloud-init` errors?
- `Emergency mode` / `Entering rescue shell`?

Serial (USB-UART on GPIO 14/15): `115200 8N1` — same questions.

## 32-bit vs 64-bit (Pi 3)

If **64-bit** never produces a sentinel, flash **32-bit** Lite:

```bash
FLASH_ARCH=armhf ./scripts/flash_sd_mac.sh diskN
# then factory sync as usual
```

If **32-bit** produces `pi-boot-sentinel.txt` and 64-bit does not, use **32-bit** for this appliance.

## Report template

```
sentinel file appeared? yes/no
HDMI output? yes/no — (rainbow / kernel / login / emergency / blank)
image: 64-bit or 32-bit
green LED: (solid / blink / off)
bootfs path in file: /boot or /boot/firmware
```

## Order of debugging

1. `pi-boot-sentinel.txt`
2. SSH / WiFi (`user-data.autobringup` + `network-config`)
3. **Autobringup on Pi:** [autobringup.md](autobringup.md) — `install_autobringup_on_pi.sh`
4. e-ink / FluidSynth only after autobringup report exists
