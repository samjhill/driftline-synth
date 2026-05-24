# ChatGPT handoff — Driftline Pi autobringup (please read fully)

Copy everything below the line into a new ChatGPT thread. Attach this file or paste as-is.

---

## Who I am and what I need

I'm building **driftline-synth**: an ambient synth on a **Raspberry Pi 3 B** with a **Waveshare 2.13" e-Paper HAT V4** and **Arturia KeyStep** over USB MIDI. Production audio is **FluidSynth V1 only** — no SuperCollider, JACK, or GhostRoll.

I need **one unattended SD card boot** that ends with a readable report on the boot partition (`DRIFTLINE_BRINGUP_REPORT.txt`), SSH working, e-ink showing something, and FluidSynth running. I'm exhausted; **Mac-side rootfs install of a systemd unit keeps failing** even though **Linux boots and the boot sentinel works**.

Please help me either (a) **reliably install `pi-ambient-autobringup.service` on the ext4 root partition from macOS**, or (b) **accept a simpler path** (e.g. install the unit only on first Pi boot via sentinel) without sending me back to cloud-init rabbit holes.

---

## Repo and hardware

| Item | Value |
|------|--------|
| Repo | `https://github.com/samjhill/driftline-synth` (local: `~/Documents/opensource/driftline-synth`) |
| Pi | Raspberry Pi 3 B, Raspberry Pi OS (Debian Trixie-based image) |
| Boot partition | `/Volumes/bootfs` when SD in Mac reader (also `/boot/firmware` on Pi) |
| Root partition | `/dev/rdisk4s2` (example; resolved from boot volume) |
| WiFi | SSID `cottage` in `deploy/secrets/network-config.local` |
| Imager user | `sam` (UID ≥ 1000; scripts detect first user under `/home`, not hardcoded `pi`) |

---

## Intended architecture (current design)

We **pivoted away** from long-running work in **cmdline `systemd.run`** because the transient unit **kills child processes** when it exits.

| Layer | What it does |
|--------|----------------|
| **`pi_boot_sentinel.sh`** (cmdline `systemd.run`) | Short: write `pi-boot-sentinel.txt`, probe bootfs, optionally verify autobringup unit, **exit** |
| **`pi-ambient-autobringup.service`** (ext4 **rootfs**, `multi-user.target`) | Runs `pi_ambient_autobringup.sh` from FAT tree; `Restart=on-failure`; full pipeline |
| **cloud-init `user-data`** | **SSH only** — must **not** install bring-up or apt packages |
| **Bring-up script** | `scripts/pi_ambient_autobringup.sh` — stages: USER_DETECT, RSYNC, NETWORK, SSH, EINK, AUDIO (fluidsynth), KEYSTEP, FINAL_REPORT |

**Acceptance after boot:** `AUTOBRINGUP_START` in logs/status, non-empty `autobringup.log`, real `DRIFTLINE_BRINGUP_REPORT.txt` (not Mac placeholder), `EINK_SENT_V4` in `eink.log`.

---

## What actually works today

1. **Pi boots Linux** — confirmed in `pi-boot-sentinel.txt` on bootfs (aarch64, `/boot/firmware` rw).
2. **Boot sentinel via cmdline** — writes sentinel file across multiple boots.
3. **Boot partition sync from Mac** — `rsync` / `build_autobringup_sd_mac.sh` puts `pi-ambient-synth/` tree on FAT.
4. **Pre-boot checks** (partial) — `check_autobringup_sd_mac.sh` validates FAT contents, `user-data`, `deploy.conf` with `AUDIO_MODE=fluidsynth`.

---

## What is broken (core blocker)

**`pi-ambient-autobringup.service` is not reliably installed/enabled on the ext4 root partition from macOS.**

Bring-up **never reaches `AUTOBRINGUP_START`**. `DRIFTLINE_BRINGUP_REPORT.txt` stays a Mac placeholder. Older boots showed `autobringup pid=…` from **nohup under cmdline** (dead child) — that path was removed.

### Latest Mac install failure (copy-paste verbatim)

```text
sudo ./scripts/fix_autobringup_sd_boot.sh /Volumes/bootfs
==> user-data + deploy.conf on bootfs
Installing pi-ambient-autobringup.service on /dev/rdisk4s2 ...
Error copying file .../systemd/pi-ambient-autobringup.service to /dev/rdisk4s2:/etc/systemd/system/
Error encountered copying files
debugfs:
debugfs:  Allocated inode: 32375
debugfs:  ext2fs_mkdir2: Ext2 directory already exists while creating directory "multi-user.target.wants"
mkdir: Ext2 directory already exists
debugfs:  rm: File not found by ext2_lookup while trying to resolve filename
debugfs:  ext2fs_symlink: Ext2 file already exists while creating symlink "pi-ambient-autobringup.service"
symlink: Ext2 file already exists
debugfs:  ext2fs_close: Invalid argument
ERROR: could not install unit on root FS (e2cp and debugfs failed).
```

**Interpretation I'm asking you to validate:**

- **`e2cp` / e2tools** cannot copy into this **Trixie ext4** root from macOS (known pain point).
- **`debugfs write`** may succeed (`Allocated inode: 32375`) for the unit file.
- **`debugfs symlink`** is inconsistent: `rm` says **file not found**, then `symlink` says **file already exists** for `pi-ambient-autobringup.service` under `multi-user.target.wants`.
- Earlier `ls` of wants dir from Mac **did not list** `pi-ambient-autobringup.service` among enabled units (NetworkManager, ssh, userconfig, etc.).
- **`e2ls` verification** may disagree with **debugfs** (false negatives on pass/fail).
- Past scripts used **`grep` patterns containing `->`** on macOS → `grep: invalid option -- >` (fixed in repo, but may have caused false "link present: no").

---

## cloud-init status (do not send me here first)

On this image, cloud-init is **broken/unreliable** (Trixie): `DataSourceNone`, boot path issues, `user-data` / `runcmd` often never run. That's why we moved bring-up to **rootfs systemd only**.

Reference on SD: `pi-ambient-synth/results.txt` (if present). **`deploy/user-data.autobringup`** is intentionally minimal (SSH + timezone only).

---

## Key files and scripts

| Path | Role |
|------|------|
| `systemd/pi-ambient-autobringup.service` | systemd unit (runs bring-up script from FAT) |
| `scripts/pi_ambient_autobringup.sh` | Full bring-up pipeline |
| `scripts/pi_boot_sentinel.sh` | Minimal cmdline sentinel |
| `scripts/install_autobringup_rootfs.sh` | **Mac install unit on ext4** (BLOCKED) |
| `scripts/install_boot_sentinel_rootfs.sh` | Mac install sentinel unit (similar tooling; basic.target) |
| `scripts/fix_autobringup_sd_boot.sh` | user-data + deploy.conf + install + check |
| `scripts/build_autobringup_sd_mac.sh` | Factory SD sync |
| `scripts/check_autobringup_sd_mac.sh` | Pre-boot validation |
| `scripts/wipe_cloud_init_mac.sh` | Clear cloud-init state on bootfs |
| `deploy/user-data.autobringup` | SSH-only cloud-init template |
| `docs/autobringup.md` | Architecture + acceptance criteria |

**Mac tools:** Homebrew `e2tools`, `e2fsprogs` (`debugfs`, `e2cp`, `e2ln`, `e2ls`).

**Factory flow (intended):**

```bash
sudo ./scripts/wipe_cloud_init_mac.sh
sudo ./scripts/install_autobringup_rootfs.sh /Volumes/bootfs
./scripts/build_autobringup_sd_mac.sh /Volumes/bootfs
./scripts/check_autobringup_sd_mac.sh /Volumes/bootfs
# Boot Pi 10–15 min unattended
./scripts/read_autobringup_report_mac.sh /Volumes/bootfs
```

---

## Evidence from SD after Pi boots (when I had a partially working card)

| File | Typical content |
|------|------------------|
| `pi-boot-sentinel.txt` | Linux booted, sentinel OK |
| `DRIFTLINE_BRINGUP_REPORT.txt` | Still placeholder from Mac — **bring-up never finished** |
| `pi-ambient-firstboot-status.txt` | `BOOT_SENTINEL kick autobringup`, `autobringup pid=…` — **no `AUTOBRINGUP_START`** |
| `boot-logs/autobringup-kick.log` | 0 bytes — cmdline child died |

---

## What we've already tried

1. cloud-init / firstboot units → unreliable on Trixie.
2. cmdline `systemd.run` + nohup bring-up → child killed when transient unit exits.
3. Move long bring-up to **`pi-ambient-autobringup.service`** on rootfs.
4. Mac install via **e2cp** → fails on ext4.
5. Mac install via **debugfs write + symlink** → unit inode allocated; symlink conflicts (`already exists` vs `rm not found`).
6. Fix **grep `->`** false failures in install verification.
7. Use **full path** in `debugfs symlink` (like boot-sentinel installer) vs relative `../`.
8. Bootfs marker `pi-ambient-autobringup-root-installed.txt` for check script when e2ls is flaky.

---

## Concrete asks for ChatGPT

1. **Diagnose** the debugfs contradiction (`rm: not found` then `symlink: already exists`) on **macOS + Raspberry Pi OS Trixie ext4 root**. Is there a stale inode, wrong path, or need `cd` into `wants` before `rm`/`symlink`?
2. Provide a **working Mac install procedure** OR say honestly if **offline ext4 editing from macOS is a dead end** for this image.
3. If Mac install is unreliable, design **Plan B**: e.g. sentinel on first boot runs `install_autobringup_unit.sh` from FAT **once** (not cloud-init), then reboot — minimal, testable.
4. **Do not** recommend debugging Waveshare, FluidSynth, or GitHub sync until **`AUTOBRINGUP_START`** appears in Pi-written logs.

---

## Pi-side workaround (if Mac install keeps failing)

After SSH works (sentinel + manual or old user-data):

```bash
sudo cp /boot/firmware/pi-ambient-synth/systemd/pi-ambient-autobringup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pi-ambient-autobringup.service
sudo systemctl start pi-ambient-autobringup.service
```

Then verify `journalctl -u pi-ambient-autobringup` and bootfs report files.

---

## Emotional context

I've spent many cycles on SD imaging, cloud-init, and Mac ext4 tooling. **I need one clear win:** either Mac install passes `check_autobringup_sd_mac.sh` and the next boot shows `AUTOBRINGUP_START`, or a **single documented fallback** that doesn't depend on cloud-init. Please be direct about dead ends.

---

## Latest repo fix attempt (may not be on SD yet)

`install_autobringup_rootfs.sh` was updated to:

- Write unit with **debugfs** when e2cp fails
- Create enable symlink via **`cd` into `multi-user.target.wants`** then `rm` / `unlink` / `symlink` (relative name)
- Fall back to **e2ln** after debugfs unit write
- Verify with **debugfs `ls -l`** as well as e2ls

Re-run after pull:

```bash
sudo ./scripts/install_autobringup_rootfs.sh /Volumes/bootfs
```

If it still fails, capture:

```bash
sudo debugfs -R "ls -l /etc/systemd/system/pi-ambient-autobringup.service" /dev/rdisk4s2
sudo debugfs -R "ls -l /etc/systemd/system/multi-user.target.wants" /dev/rdisk4s2
e2ls -l /dev/rdisk4s2:/etc/systemd/system/multi-user.target.wants
```

Paste all output back.

---

*End of handoff — generated for driftline-synth autobringup debugging.*
