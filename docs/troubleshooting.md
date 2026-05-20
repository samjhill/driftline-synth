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

## E-ink display does not update

- SPI enabled: `ls /dev/spidev*`
- HAT seated firmly on GPIO header
- Waveshare driver installed (`waveshare_epd` importable)
- Run: `python scripts/test_eink.py`
- Use `python src/main.py --no-eink` to run without display

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
journalctl -u pi-ambient-synth -f
```

Re-install services: `./install.sh --enable-services`

## Patch too loud / harsh

Patches are curated in `patch_generator.py`. Lower `audio.default_volume` in config. Use `python src/main.py --panic` for all-notes-off.
