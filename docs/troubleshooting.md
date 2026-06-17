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

## No sound

1. Confirm SuperCollider is running: `systemctl status supercollider` or watch `sclang` output.
2. Check default audio device: `aplay -l`, `speaker-test -t wav -c 2`.
3. Run OSC test: `python scripts/test_osc.py` (with engine running).
4. Verify volume in `config/default.yaml` (`audio.default_volume`).

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
