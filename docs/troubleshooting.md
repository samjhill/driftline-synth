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

## Synth restarts: `MidiInAlsa::initialize: error creating ALSA sequencer client`

The app should stay running without MIDI (latest code catches this). To fix ALSA MIDI:

```bash
groups pi   # should include audio
sudo modprobe snd-seq
python3 scripts/list_midi_devices.py
```

Re-plug the KeyStep USB data cable, then `sudo systemctl restart pi-ambient-synth`.

## No sound / headphones silent

1. **OS audio first** — you should hear the test tone on the **3.5 mm jack** (not HDMI):

```bash
bash ~/pi-ambient-synth/scripts/setup_pi_audio.sh
```

If bare `speaker-test` fails with **`Playback open error: -524`**, the broken ALSA **`default`** device is usually PulseAudio/PipeWire on headless Pi OS. Use the headphone device explicitly:

```bash
sudo systemctl stop supercollider   # free the sound card
speaker-test -D plughw:0,0 -r 44100 -t pink -c 2 -l 1
```

(`-t wav` uses 48 kHz system WAV files and warns on 44.1 kHz; **`-t pink`** generates noise at the requested rate.)

`setup_pi_audio.sh` installs `/etc/asound.conf` so `default` maps to **card 0 (Headphones)** and sets `SC_AUDIO_DEVICE=plughw:0,0` for SuperCollider.

If `speaker-test` is still silent, fix Pi routing/volume (`raspi-config` → Audio → Headphones, or plug headphones in before boot).

2. **SuperCollider** — must be `active` and log `scsynth running` / `listening on OSC port 57120`:

```bash
bash ~/pi-ambient-synth/scripts/diagnose_audio.sh
sudo systemctl restart supercollider pi-ambient-synth
sudo journalctl -u supercollider -n 30 --no-pager
```

3. **JACK** — `jackd2` must **not** be running (it grabs ALSA). `setup_pi_audio.sh` disables it.

4. **Wrong ALSA device** — if HDMI is default, force the jack:

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

6. **KeyStep keyboard split** — notes **below G3 (MIDI 55)** only shift the drone; play **higher keys** for melody. The idle drone should still be faintly audible when SC is running.

7. Volume in `config/default.yaml` (`audio.default_volume`, default `0.65`).

## SuperCollider won't boot

- Install: `sudo apt install supercollider`
- Run interactively: `sclang synth/ambient_engine.scd` and read errors
- Jack/PipeWire conflicts: try `export SC_JACK_DEFAULT_INPUTS=` as in systemd unit

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

The Arturia KeyStep often does **not** send a distinct "Shift" MIDI message. V1 fallbacks:

1. Run `python src/main.py --debug-midi` and press Play/Stop/Record with and without Shift.
2. Note the CC numbers or SysEx/MMC bytes emitted.
3. Update `TRANSPORT_CC` in `src/midi_controller.py` to match your firmware.

Typical findings:

- Transport may appear as MMC (`0xFA` play, `0xFC` stop) in SysEx/realtime.
- Some units map transport to CC 102–104.
- Shift may only change LED state locally without MIDI.

**Workaround:** Map reseed to Hold or Tap Tempo CC once identified in monitor mode.

## App crashes / no auto-restart

```bash
sudo systemctl status pi-ambient-synth supercollider
sudo journalctl -u pi-ambient-synth -f
```

Re-install services: `./install.sh --enable-services`

## Patch too loud / harsh

Patches are curated in `patch_generator.py`. Lower `audio.default_volume` in config. Use `python src/main.py --panic` for all-notes-off.
