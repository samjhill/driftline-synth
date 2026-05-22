# Troubleshooting

## Wi‑Fi never connects (wlan0 down in cloud-init logs)

If `cloud-init-output.log` shows `wlan0 | False` with no IP:

1. Confirm the network is **2.4 GHz** (Pi cannot use 5 GHz–only APs).
2. Re-sync the SD after editing `deploy/secrets/network-config.local` and `wpa_supplicant.conf.local`.
3. On the Mac with the card inserted, wipe cloud-init cache then re-sync:
   ```bash
   sudo ./scripts/wipe_cloud_init_mac.sh
   ./scripts/sync_to_sd_mac.sh
   ```
4. If logs show `Datasource DataSourceNone` or `Used fallback datasource`, cloud-init did **not** read `user-data` — run the wipe script above and boot again.

## cloud-init did not run our install (empty boot-logs/)

`boot-logs/first-boot.log` is created by `user-data` `runcmd`. If the folder is empty:

- cloud-init fell back to `DataSourceNone` (see above), or
- `instance_id` on the SD was changed without wiping `/var/lib/cloud` on the root partition.

Fix: `sudo ./scripts/wipe_cloud_init_mac.sh` then `./scripts/sync_to_sd_mac.sh`, eject, boot.

# Troubleshooting

## KeyStep lights up but no MIDI

The USB cable is likely **power-only**. Use a proper USB-A to USB-B data cable.

## No MIDI input found

```bash
python scripts/list_midi_devices.py
```

Confirm the KeyStep appears. If not, unplug/replug and check `dmesg` on the Pi.

If the monitor shows **Midi Through** instead of **KeyStep** / **Arturia**, the keyboard is **not** on USB-MIDI (power-only cable, wrong port, or not plugged in). Fix USB, then:

```bash
sudo systemctl restart pi-ambient-synth
```

Play keys **above G3 (MIDI note 55+)** for melody; lower keys only move the drone root.

## Synth restarts: `MidiInAlsa::initialize: error creating ALSA sequencer client`

The app should stay running without MIDI (latest code catches this). To fix ALSA MIDI:

```bash
groups pi   # should include audio
sudo modprobe snd-seq
python3 scripts/list_midi_devices.py
```

Re-plug the KeyStep USB data cable, then `sudo systemctl restart pi-ambient-synth`.

## V1 FluidSynth (production — no JACK / no SuperCollider)

Stack: **KeyStep → `pi_midi_bridge` → FluidSynth → ALSA `plughw:0,0` → headphone jack.**

```bash
# 1) Prove FluidSynth audio (user must hear notes)
INSTALL_DIR=~/pi-ambient-synth ./scripts/fluidsynth_headphone_demo.sh

# 2) Enable V1 on Pi
INSTALL_DIR=~/pi-ambient-synth ./scripts/pi_enable_fluidsynth_engine.sh

# 3) Play KeyStep; reseed changes GM program; e-ink updates on reseed only
```

Acceptance: heard demo → heard keys → reseed changes patch/program → e-ink on reseed.

Do not use `pi_enable_ambient_engine.sh` or SuperCollider smoke tests for V1.

## Hardware isolation (ALSA → JACK → SuperCollider) — archived

User heard **silence** on SuperCollider smoke → stop synth/MIDI/OSC work until the jack is proven layer by layer.

| Step | Script | User confirms |
|------|--------|----------------|
| 1 ALSA | `scripts/alsa_headphone_smoke_test.sh` | `ALSA_HEADPHONE_TEST_DONE_USER_MUST_CONFIRM` → **heard** / **silence** |
| 2 Report | `scripts/audio_device_report.sh` | (inventory only) |
| 3 JACK | `scripts/jack_headphone_smoke_test.sh` | `JACK_HEADPHONE_TEST_DONE_USER_MUST_CONFIRM` → **heard** / **silence** |
| 4 SC | `scripts/sc_jack_known_good_test.sh` | `SC_JACK_KNOWN_GOOD_TEST_DONE_USER_MUST_CONFIRM` → **heard** / **silence** |

From Mac (`.pi-ssh-credentials`): `./scripts/run_audio_isolation_on_pi.sh alsa` then `report` then `jack` then `sc`.

If Step 1 is **silence**, the fault is Pi output, cable, headphones, or mixer — not the synth app.

## Phased audio rebuild (headphone jack proof first)

Do **not** treat `REAL_SYNTH_PATH_READY` or monitor “Test note” as proof you hear sound. Milestone order:

1. **Direct SuperCollider** — from your Mac (needs `.pi-ssh-credentials` + `sshpass`):
   ```bash
   ./scripts/run_sc_direct_smoke_on_pi.sh
   ```
   Stops/masks production units, runs `jackd` + `scsynth` + `xvfb-run sclang` (`synth/sc_direct_smoke.scd`), prints `SC_DIRECT_AUDIO_HEARD_QUESTION`. Reply **tone** / **chord** / **silence**. If silence, stop — do not debug MIDI, OSC, or e-ink yet.

2. **Minimal engine** — default `synth/minimal_ambient_engine.scd` (`piWarmPad` → bus 0). After restart:
   ```bash
   INSTALL_DIR=~/pi-ambient-synth ./scripts/restart_synth_services.sh
   INSTALL_DIR=~/pi-ambient-synth ./scripts/minimal_proof_note.sh
   ```
   Confirm **pad** audibly on the jack.

3. **KeyStep** — only after step 2; one key, same pad.

4. **E-ink** — `./scripts/disable_eink_for_audio_debug.sh` during audio work; fix display separately later.

Legacy full engine: `PI_LEGACY_ENGINE=1` in `run_sclang_engine.sh` → `synth/ambient_engine.scd`.

## No sound / headphones silent

1. **OS audio first** — you should hear the test tone on the **3.5 mm jack** (not HDMI):

```bash
bash ~/pi-ambient-synth/scripts/setup_pi_audio.sh
```

If bare `speaker-test` fails with **`Playback open error: -524`**, the broken ALSA **`default`** device is usually PulseAudio/PipeWire on headless Pi OS. Use the headphone device explicitly:

```bash
sudo systemctl stop supercollider   # free the sound card
python3 ~/pi-ambient-synth/scripts/play_headphone_test.py -D plughw:0,0
```

(`setup_pi_audio.sh` uses this by default — a soft tone that slowly pans left ↔ right. Fallback: `speaker-test -D plughw:0,0 -r 44100 -t pink -c 2 -l 1`.)

`setup_pi_audio.sh` installs `/etc/asound.conf` so `default` maps to **card 0 (Headphones)** and sets `SC_AUDIO_DEVICE=plughw:0,0` for SuperCollider.

If `speaker-test` is still silent, fix Pi routing/volume (`raspi-config` → Audio → Headphones, or plug headphones in before boot).

2. **SuperCollider** — `systemctl is-active` must be **`active`** and **`pgrep scsynth`** must show a process. The journal must include `Booting Pi Ambient Synth engine...`, `scsynth running`, and `listening on OSC port 57120`. If you only see `Welcome to SuperCollider` with no `scsynth`, the audio server never started — update `ambient_engine.scd` and restart.

```bash
bash ~/pi-ambient-synth/scripts/diagnose_audio.sh
sudo systemctl restart supercollider pi-ambient-synth
sudo journalctl -u supercollider -n 30 --no-pager
```

3. **Stable Pi audio (do not alternate ALSA/JACK modes)** — Production uses **one** stack only: `jackd` on `plughw:0,0` → `scsynth` JACK client → `ensure_jack_playback.sh` links `SuperCollider:out_*` to `system:playback_*`. Do **not** toggle `SC_USE_NATIVE_ALSA`, hybrid `aplay` key blips, or a named JACK server (`jackd -n …`); those caused silent headphones while checks still passed. After deploy: `sudo systemctl restart supercollider pi-ambient-synth-midi` and confirm `jack_lsp -c | grep SuperCollider`.

4. **JACK / scsynth crash** — On Pi **SC 3.13**, `scsynth -H hw:0` still embeds **jackdmp**, prints `SuperCollider 3 server ready`, then dies with `JackTemporaryException` / `JackEngine::XRun`. Fix: start **our** `jackd` on ALSA first, then `scsynth` as a JACK client (`scripts/start_scsynth_alsa.sh` does this). Do **not** use systemd `jackd2` (wrong config); do stop PipeWire/Pulse so ALSA is free:

```bash
sudo systemctl stop jackd2 pipewire pipewire-pulse 2>/dev/null || true
bash ~/pi-ambient-synth/scripts/setup_pi_audio.sh
~/pi-ambient-synth/scripts/start_scsynth_alsa.sh
tail -30 /tmp/scsynth-alsa-start.log   # want: jackd ready + scsynth ready (no JackTemporaryException)
```

If XRuns persist, try larger buffers: `SC_JACK_PERIOD=4096 SC_JACK_NPERIODS=3 ~/pi-ambient-synth/scripts/start_scsynth_alsa.sh`

5. **Wrong ALSA device** — if HDMI is default, force the jack:

```bash
# List devices
aplay -L | head -20
# Try in /etc/systemd/system/supercollider.service.d/device.conf :
# [Service]
# Environment=SC_AUDIO_DEVICE=hw:0,0
sudo systemctl daemon-reload
sudo systemctl restart supercollider
```

5. **OSC test** (bypasses MIDI):

```bash
cd ~/pi-ambient-synth
.venv/bin/python scripts/test_osc.py
```

6. **KeyStep keyboard split** — on the full `main.py` path, notes **below G3 (MIDI 55)** only shift the drone; play **higher keys** for melody. The headless MIDI bridge sends all notes to SuperCollider. The idle drone should still be faintly audible when SC is running.

7. **Keys silent after SHIFT+PLAY (reseed)** — if Shift (CC 63) stays ≥ 64, older builds swallowed all `note_on` while shift was held. Release Shift, or upgrade `midi_controller.py` (melody keys pass through with shift held). Enable `PI_MIDI_LOG_NOTES=1` on `pi-ambient-synth-midi.service` and `journalctl -u pi-ambient-synth-midi -f` while playing keys to confirm MIDI reaches the bridge.

8. **MIDI logs show `ch=14` and very low velocity (e.g. vel 11)** — Arturia KeyStep **MPE** mode sends per-note MIDI on channel 15 (`ch=14` in logs) with weak velocity. Either disable MPE in **MIDI Control Center** (use single MIDI channel), or rely on `midi.velocity_floor` (default 72) in `config/default.yaml`. After deploy, logs should show `vel 11 → floored to 72` and `playNote` with `used 72`.

9. **Sound tab “Test note” silent but journal shows `playNote`** — JACK may have dropped `SuperCollider:out → system:playback`. Run `~/pi-ambient-synth/scripts/ensure_jack_playback.sh`, raise headphone PCM (`amixer -c 0 set PCM 95%`), and use the updated **Test note** button (plays a loud beep + C4 and sets master volume to 100%).

10. **Shift reseed does nothing** — **Shift is not in MIDI Control Center** on KeyStep (hardware modifier only). See **`docs/keystep_reseed.md`**. Working options: monitor **New patch (reseed)**; **PiSugar single tap** (if `pisugar-server` is running); **Shift+Play** after arp has run ~1s (extra MIDI Start while clock active); **Pause→Play** within 3s; **Hold** if it sends CC 64; or assign a custom CC in MCC (mod strip → CC 119, add to `midi.reseed_trigger_ccs`). Debug: `journalctl -u pi-ambient-synth-midi -f`.

11. **Notes on e-ink but silent headphones** — Python may be sending OSC before SuperCollider registers handlers. Check `/var/lib/pi-ambient-synth/sc-engine-ready` exists after boot and journal has `listening on OSC port 57120`. Restart: `sudo systemctl restart supercollider && sleep 15 && sudo systemctl restart pi-ambient-synth`. Orphan `scsynth` processes are killed on each SC start in current `run_sclang_engine.sh`.

12. **Audio modes (Pi 3 headphone jack)** — Set in `/etc/pi-ambient-synth/audio-mode.conf` (fresh install defaults to **`ambient`**):
    - **`ambient`** (production) — KeyStep → `pi-ambient-synth-midi` → OSC → **SuperCollider** on `plughw:0,0`: `bash scripts/pi_enable_ambient_engine.sh`, then `bash scripts/prove_ambient_engine_pi.sh` or `bash scripts/verify_audible_pi.sh`. Journal should show `bridge → OSC note_on` with **different `note=` per key** and `playNote: midi` in `supercollider`. If you still hear identical noise per key, confirm `pi-flues-synth` is **stopped** and `aconnect -l` has **no** KeyStep→Flues link (`scripts/disconnect_midi_from_flues.sh`).
    - **`direct_keys`** — short `aplay` blips only (no SC): `bash scripts/pi_enable_direct_keys.sh`.
    - **`flues`** (experimental) — Flues-Synth instead of SC: `bash scripts/pi_enable_flues_engine.sh`. Same hiss on every key usually means MPE on ch 15 or KeyStep wired directly to Flues; use `connect_midi_to_flues.sh` and disable MPE in Arturia MCC.

### One-command verify (audio + engine)

From your **Mac** (rsync this repo — no commit-pinned curl chain):

```bash
./scripts/run_pi_verify.sh --save-password   # once: stores ~/.gitignored creds + needs sshpass
brew install hudochenkov/sshpass/sshpass
./scripts/run_pi_verify.sh
# PASS or FAIL + log tails; result: /var/lib/pi-ambient-synth/verify-last.txt
```

Password is stored in repo-root `.pi-ssh-credentials` (chmod 600, gitignored). Without sshpass, SSH uses a single shared connection (one password prompt per run).

On the **Pi** only (pulls `main` from GitHub):

```bash
curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/pi_verify.sh | bash
```

Includes up to 5 audio retries (4096→8192 buffers), then engine smoke. Restart services after PASS:

```bash
./scripts/run_pi_verify.sh --full
```

Engine file must contain build marker `sc313-jackExternal` (external jackd + scsynth). On SC 3.13 Pi, never use C-style `if(x) { }`, `&&`/`||` in `if` tests, or `if(x and: { ... }, ...)` (and:/or: return non-Boolean values).

7. Volume in `config/default.yaml` (`audio.default_volume`, default `0.65`).

## SuperCollider won't boot

- Install: `sudo apt install supercollider`
- Run interactively: `sclang synth/ambient_engine.scd` and read errors
- Jack/PipeWire conflicts: try `export SC_JACK_DEFAULT_INPUTS=` as in systemd unit

### Journal: `syntax error` at `if(companionOn and {`

The engine file on disk is **stale**. SuperCollider needs `and:` (with a colon), not `and {`.

**Do not** rely on `curl …/main/synth/ambient_engine.scd` alone — GitHub’s `raw.githubusercontent.com` **`main`** URL can lag behind the real branch for hours and may still serve an old file after `main` is fixed. Prefer a full deploy:

```bash
curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_from_github.sh | bash
```

Or fetch the engine by **commit SHA** (check `https://api.github.com/repos/samjhill/driftline-synth/commits/main` for the current `sha`), then verify line 381:

```bash
SHA=e686042   # replace with current main sha
curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/${SHA}/synth/ambient_engine.scd" \
  -o ~/pi-ambient-synth/synth/ambient_engine.scd
sed -n '381p' ~/pi-ambient-synth/synth/ambient_engine.scd
# must show: if(companionOn and: { companionSynth.isNil }, {
```

Quick one-line patches if you cannot redeploy:

```bash
sed -i 's/companionOn and {/companionOn and: {/' ~/pi-ambient-synth/synth/ambient_engine.scd
sed -i 's/msg\[\([0-9]\)\] ? msg\[\1\] :/msg[\1] ??/g' ~/pi-ambient-synth/synth/ambient_engine.scd
```

### Journal: `unexpected ':'` at `msg[1] ? msg[1] : 120`

JavaScript-style ternary does not exist in SuperCollider. Use nil-coalescing: `msg[1] ?? 120`.

## SuperCollider crashes: `qt.qpa.xcb: could not connect to display`

The Pi has no desktop/X11. `sclang` was built with Qt and aborts unless told to run headless.

```bash
sudo systemctl stop supercollider
sudo systemctl reset-failed supercollider
sudo cp ~/pi-ambient-synth/systemd/supercollider.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start supercollider
sleep 5
systemctl is-active supercollider
sudo journalctl -u supercollider -n 20 --no-pager
```

The unit runs `scripts/run_sclang_engine.sh`, which sets `QT_QPA_PLATFORM=offscreen` and unsets `DISPLAY`. Verify the running unit:

```bash
systemctl cat supercollider | grep -E 'ExecStart|QT_QPA|run_sclang'
```

You should see `run_sclang_engine.sh` in `ExecStart`. If you still see bare `sclang ...ambient_engine.scd`, the unit file on disk was not updated.

You should see `Pi Ambient Synth listening on OSC port 57120` in the journal.

If the journal shows `SCLang Input: Operation not supported` then quit, the unit was likely
using `sclang -l script.scd` (wrong). Use `scripts/run_sclang_engine.sh`, which runs
`sclang /path/to/ambient_engine.scd` with stdin closed.

## Synth crashes: `NameError: name 'Path' is not defined` in eink_display

Pull latest `main` — `Path` must be imported at the top of `src/eink_display.py`.

## LAN monitor missing MIDI keyboard rows

The status page at `http://<pi-ip>:8080/` only shows **MIDI keyboard** / **MIDI inputs** when `monitor_server.py` includes that feature (commit `2b4a018` and later). If `/api/status` has no `"midi"` key, the Pi is still running an older copy — often because the deploy timer keeps syncing from the **boot partition** SD image instead of GitHub.

Check:

```bash
curl -s http://127.0.0.1:8080/api/status | python3 -c "import sys,json; print('midi' in json.load(sys.stdin))"
```

**Fix on a running Pi** (SSH):

```bash
bash ~/pi-ambient-synth/scripts/enable_github_auto_pull.sh
# wait ~1–2 min, then verify:
curl -s http://127.0.0.1:8080/api/status | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('midi',{}).get('label'))"
sudo systemctl restart pi-ambient-synth-monitor
```

**Fix from your Mac** (re-copy latest code to the SD boot partition, then reboot or trigger deploy):

```bash
./scripts/sync_to_sd_mac.sh /Volumes/bootfs
```

After the Pi pulls `main`, the monitor table should list MIDI keyboard status again.

### Deploy log: `Fetching .../archive/Network: 192.168...` / `archive did not extract`

The deploy timer captured **network status log text** as the GitHub SHA (stdout pollution). Pull `main` (fix in `6998d6e+`) or run recovery:

```bash
curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_from_github.sh | bash
```

Then confirm deploy log shows `Fetching https://github.com/samjhill/driftline-synth/archive/<40-char-sha>.tar.gz` and **Deploy SHA** updates to a real commit (e.g. `6998d6e`).

If **Deploy SHA** still shows `boot-sd` after GitHub pull, the marker file was never updated (SD bootstrap placeholder). Clear it and redeploy:

```bash
rm -f ~/pi-ambient-synth/.deploy_sha /var/lib/pi-ambient-synth/last_deploy_sha
bash ~/pi-ambient-synth/scripts/enable_github_auto_pull.sh
```

The page should then show a 7–12 character Git commit id (e.g. `281a96c`).

## rsync errors: `cannot delete ... dev/`, `boot/`, `Permission denied` on install

This means **`rsync --delete` targeted the wrong directory** — often `/`, `/home/pi`, or `home/pi` (missing leading `/`) when `INSTALL_DIR` was inherited from the shell as `/home/pi` instead of `/home/pi/pi-ambient-synth`. That tries to delete `~/.local`, `.bashrc`, etc.

**Do not** run manual `rsync --delete` to `~`, `/home/pi`, `/`, or `/boot`.

Recovery (uses **staging deploy**, no `--delete`):

```bash
sudo systemctl stop pi-ambient-synth-deploy.timer
unset INSTALL_DIR
curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/fix_install_permissions.sh | bash
curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_from_github.sh | bash
```

If `pip` under `~/.local` was damaged: `python3 -m ensurepip --user` or re-run recover after the fix above.

Deploy scripts now **`unset INSTALL_DIR`** before running and copy via `scripts/lib_deploy_sync.sh` (staging + atomic rename only).

## Deploy log shows `source=boot` every minute / SuperCollider `ABRT`

If the deploy log repeats `Mode=sync source=boot` and `Rsync from boot`, the Pi was re-loading **boot** `deploy.conf` on top of `/etc/pi-ambient-synth/deploy.conf` (fixed in recent `pi-deploy-sync.sh`). Until GitHub pull runs, `supercollider.service` may still point at bare `sclang` (no headless Qt) and crash with `signal=ABRT`.

On the Pi (recommended — fetches latest scripts from GitHub even if the SD copy is stale):

```bash
curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_from_github.sh | bash
```

Then verify:

```bash
systemctl cat supercollider.service | grep ExecStart   # run_sclang_engine.sh
sudo journalctl -u supercollider -n 30 --no-pager     # OSC port 57120
curl -s http://127.0.0.1:8080/api/status | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('deploy_sha'), d.get('midi',{}).get('label'))"
```

If you already have current scripts on disk:

```bash
sudo systemctl stop pi-ambient-synth-deploy.timer
bash ~/pi-ambient-synth/scripts/recover_pi_from_github.sh
```

Look for `Pi Ambient Synth listening on OSC port 57120` in the journal.

## MIDI inputs show `—` on the monitor

No ALSA MIDI ports were detected. Use a **data** USB cable (not charge-only), re-plug the KeyStep, then:

```bash
sudo modprobe snd-seq
groups pi   # should include audio
.venv/bin/python scripts/list_midi_devices.py
sudo systemctl restart pi-ambient-synth
```

## SuperCollider stuck on `activating`

Usually `sclang` exits right after the script finishes (or the boot `fork` errors before the keep-alive loop), so systemd keeps restarting and `systemctl is-active` stays `activating` or flips `activating`/`failed`. The engine script must block the **main** thread (`while { true } { 1.wait }` after the boot `fork` in `synth/ambient_engine.scd`). `Restart=on-failure` in `systemd/supercollider.service` avoids a tight restart loop on clean exit; `Restart=always` would restart even on exit code 0 and can make `activating` worse.

`journalctl` without `sudo` often fails for the `pi` user (`insufficient permissions`); use `sudo journalctl` or add `pi` to the `adm` group (`sudo usermod -aG adm pi`, then log in again).

After updating the repo on the Pi:

```bash
cd ~/pi-ambient-synth
git pull   # or re-run your deploy sync
sudo cp systemd/supercollider.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart supercollider
sleep 4
systemctl is-active supercollider
sudo journalctl -u supercollider -n 40 --no-pager
```

Look for `Pi Ambient Synth listening on OSC port 57120` in the journal. If missing, read the last lines for `ERROR`, `scsynth`, or audio device failures; try `aplay -l` and run `sclang synth/ambient_engine.scd` interactively once to see boot errors.

## E-ink shows old project text (“ghosting”) mixed with new content

E-ink keeps a faint image of the previous full-screen drawing until a **full** refresh (white → black → white, then redraw). Partial updates only change the new text region.

```bash
cd ~/pi-ambient-synth
EINK_FORCE=1 .venv/bin/python scripts/announce_network.py
# or, after sync:
.venv/bin/python scripts/refresh_eink.py
```

Wait ~15s for the flash cycle to finish. Stop other services first if GPIO is busy:

```bash
sudo systemctl stop pi-ambient-synth
```

## E-ink log: `module 'waveshare_epd.epd2in13' has no attribute 'epd2in13'`

The bundled Waveshare driver exposes `class EPD` inside each module (e.g. `epd2in13_V4`), not a class named `epd2in13_V4`. Pull latest `main` (fixes `src/eink_display.py`), then on the Pi:

```bash
cd ~/pi-ambient-synth
git pull
./scripts/ensure_waveshare_vendor.sh
EINK_FORCE=1 ./scripts/boot_display.sh ready "Test" "driver OK" ""
```

If the error persists, remove a conflicting system install so Python loads `vendor/waveshare` only:

```bash
sudo rm -rf /usr/local/lib/python3.*/dist-packages/waveshare_epd
```

## Headphones silent but status page / SC journal look OK

SuperCollider often runs with **JACK ports up but not wired** to `system:playback_*` (the bcm2835 headphone jack). Check:

```bash
jack_lsp -c | head -20
# Need: system:playback_1  →  SuperCollider:out_1
```

Fix immediately:

```bash
~/pi-ambient-synth/scripts/ensure_jack_playback.sh
~/pi-ambient-synth/.venv/bin/python ~/pi-ambient-synth/scripts/test_osc.py
```

Then restart supercollider so the reconnect watchdog is active:

```bash
sudo systemctl restart supercollider.service
sleep 20
~/pi-ambient-synth/scripts/ensure_jack_playback.sh
```

Also confirm ALSA PCM is not muted: `amixer -c 0 sget PCM` (should show `[on]` and reasonable %).

KeyStep: play notes **above G3 (MIDI note 55+)** for melody; lower keys only move the texture drone.

## `pi-ambient-synth` exits with SIGBUS (`status=7/BUS`)

On some Pi images, **`import numpy` alone can SIGBUS**. Production `pi-ambient-synth.service` runs `main.py --no-eink` with `PI_NO_MIDI=1` and must **not** load `visual_generator` / numpy at import time (MIDI runs in `pi-ambient-synth-midi.service` instead).

Quick check on the Pi:

```bash
PI_NO_MIDI=1 ~/pi-ambient-synth/.venv/bin/python -c \
  'import sys; sys.path.insert(0,"~/pi-ambient-synth/src"); import main; print("ok")'
# or:
~/pi-ambient-synth/scripts/pi_headless_import_check.sh
```

If this still SIGBUSes, reinstall numpy for the venv ABI (`pip install --force-reinstall numpy`) or run E2E from the Mac (`./scripts/run_pi_e2e.sh`) after rsyncing the latest `src/`.

Autonomous agents: use `.pi-e2e-status-page.txt` after `./scripts/run_pi_iterate.sh` — journal checks only inspect the **last 8 lines** so old crash loops do not fail a healthy run.

## E-ink display does not update

- SPI enabled: `ls /dev/spidev*`
- HAT seated firmly on GPIO header
- Waveshare driver installed (`waveshare_epd` importable)
- Run: `python scripts/test_eink.py`
- Use `python src/main.py --no-eink` to run without display
- Check the e-ink log (also shown on the LAN monitor page):
  ```bash
  tail -30 /var/log/pi-ambient-synth-eink.log
  ```
  Early first-boot may mirror the last lines to `boot-logs/eink.log` on the SD boot partition; routine updates always append to `/var/log/pi-ambient-synth-eink.log`.
- Force a status screen and log line:
  ```bash
  EINK_FORCE=1 ./scripts/boot_display.sh ready "Test" "e-ink OK" ""
  ```

## E-ink: `GPIO busy` — GhostRoll still running

If diagnostics show `ghostroll-eink-waveshare213v4.py` or `ghostroll-watch.service`, GhostRoll (SD ingest) owns the HAT:

```bash
curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/disable_ghostroll_on_boot.sh" | bash
```

That stops GhostRoll, **disables** it, and **masks** units so they do not start on boot. Then test e-ink:

```bash
curl -fsSL "https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/free_eink_for_ambient.sh" | bash
```

**Display keeps flash-clearing (white flashes) but synth art appears briefly:** the deploy timer was updating e-ink every 60s even when already up to date, each time running a full ghost-clear purge. Current `main` skips e-ink on routine polls and only shows deploy progress when a real update runs. After pulling, restart the synth service once: `sudo systemctl restart pi-ambient-synth`.

**GPIO busy / `got root` in e-ink log:** never run `boot_display.sh` or `eink_pull_and_refresh.sh` as root. Use `sudo -u pi` or the curl scripts (they re-exec as `pi` automatically). Example:

```bash
sudo -u pi env SKIP_SYNC=1 EINK_FORCE=1 /home/pi/pi-ambient-synth/scripts/boot_display.sh ready "Test" "as pi" ""
```

Re-enable GhostRoll when you need it:

```bash
sudo systemctl unmask ghostroll-watch.service
sudo systemctl enable --now ghostroll-watch.service
```

## E-ink: `GPIO busy` after another project on this Pi (e.g. ingest)

A previous app on the same Pi often leaves **systemd units**, **Python processes**, or a **second copy of `waveshare_epd`** installed under `/usr/local`. A one-shot `kill-ingest` (or similar) may stop running processes but still leave:

- An **enabled** service that restarts on boot and grabs GPIO again
- A **system-wide** Waveshare install that shadows `vendor/waveshare`
- **Stuck lgpio** state until reboot (if an old process was killed with `SIGKILL` / `timeout`)

On the Pi:

```bash
bash ~/pi-ambient-synth/scripts/diagnose_eink_gpio.sh
```

Then disable anything ingest-related you still see active:

```bash
systemctl list-units --all | grep -i ingest
sudo systemctl disable --now <name>.service   # each leftover unit
sudo rm -rf /usr/local/lib/python3.*/dist-packages/waveshare_epd
sudo reboot
```

After reboot, before starting the synth:

```bash
cd ~/pi-ambient-synth
SKIP_SYNC=1 EINK_FORCE=1 ./scripts/boot_display.sh ready "Test" "after reboot" ""
```

## E-ink: `lgpio.error: 'GPIO busy'`

Another process already claimed the HAT GPIO lines (often a leftover from an earlier e-ink script or a duplicate Waveshare install).

1. Stop anything that might hold the display:
   ```bash
   sudo systemctl stop pi-ambient-synth pi-ambient-synth-boot-display pi-ambient-synth-network-announce
   ```
2. Prefer the **bundled** driver under `vendor/waveshare` (not `/usr/local/.../waveshare_epd`). Remove a system copy if you installed one:
   ```bash
   sudo rm -rf /usr/local/lib/python3.*/dist-packages/waveshare_epd
   ```
3. Pull latest project code (lazy GPIO init + `display.release()` after one-shot scripts), then:
   ```bash
   cd ~/pi-ambient-synth
   sudo cp systemd/*.service /etc/systemd/system/
   sudo systemctl daemon-reload
   .venv/bin/python scripts/announce_network.py
   ```
4. If it still fails, reboot once, then run `announce_network.py` before starting `pi-ambient-synth`.

## Random / Shift button combo not detected

The KeyStep **Shift** button is **not** a MIDI-assignable control in MCC. See **`docs/keystep_reseed.md`** for reseed options (monitor button, Shift+Play while arp running, Hold/CC 64, custom CC from mod strip).

To learn what your unit sends: `PI_MIDI_LOG_TRANSPORT=1` and `scripts/pi_midi_listen.py 30` on the Pi while pressing **Hold**, **Chord**, transport, and knobs.

## App crashes / no auto-restart

```bash
sudo systemctl status pi-ambient-synth supercollider
sudo journalctl -u pi-ambient-synth -f
```

Re-install services: `./install.sh --enable-services`

## Patch too loud / harsh

Patches are curated in `patch_generator.py`. Lower `audio.default_volume` in config. Use `python src/main.py --panic` for all-notes-off.
