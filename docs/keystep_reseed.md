# KeyStep reseed (no Shift in MIDI Control Center)

On **KeyStep / KeyStep 32**, the **Shift** button is a **local modifier only**. It changes what other buttons and keys do on the unit; it is **not** listed in **MIDI Control Center (MCC)** and does **not** send its own MIDI CC over USB. That is expected Arturia behavior, not a bug in Pi Ambient Synth.

## What works today

| Method | How |
|--------|-----|
| **Monitor button** | http://\<pi-ip\>:8080/ → **New patch (reseed)** |
| **API** | `curl -X POST http://<pi-ip>:8080/api/reseed` |
| **Arp already running → Shift+Play** | Start arp with **Play**, wait until it has been running **at least ~1 second**, then **Shift+Play** (arp restart). The Pi treats the extra **MIDI Start** while the clock is already running as a new patch. Plain **Play** (first start) does **not** reseed. |
| **Pause → Play** | **Stop** (pause), then **Play** again within ~3 seconds |
| **Hold button** | If your unit sends **CC 64** when you press **Hold**, that triggers reseed (tap) |
| **PiSugar button** | **Single tap** on the PiSugar board button (configured on deploy/restart via `pisugar-server`) |

## PiSugar physical button

If you run **PiSugar Power Manager** (`pisugar-server`), a **short single tap** on the PiSugar’s physical button can queue a new patch (same as the monitor **New patch** button). Deploy or restart runs `scripts/pi_setup_pisugar_reseed_button.sh`, which registers `scripts/pi_pisugar_button_reseed.sh` with:

```bash
set_button_shell single /home/pi/pi-ambient-synth/scripts/pi_pisugar_button_reseed.sh
set_button_enable single 1
```

Toggle in `config/default.yaml`: `pisugar.reseed_on_button` (default `true`). **Double** and **long** presses are left to PiSugar defaults (often shutdown) — do not remap them unless you know what Power Manager already assigned.

Manual check on the Pi:

```bash
echo "get button_shell single" | nc -U /tmp/pisugar-server.sock
/home/pi/pi-ambient-synth/scripts/pi_pisugar_button_reseed.sh
ls -l /var/lib/pi-ambient-synth/reseed.request
```

## Assign a custom “reseed” control in MCC

Use something MCC **does** expose:

1. Open **MIDI Control Center** → your **KeyStep 32**.
2. Open the **MIDI Console** (see incoming messages while you move controls).
3. Pick a control you can spare, for example:
   - **Mod strip** → set to a custom CC (e.g. **119**)
   - **Hold** / sustain (often **CC 64** already wired)
4. On the Pi, add that CC to `config/default.yaml`:

```yaml
midi:
  reseed_trigger_ccs: [64, 119]
```

5. Redeploy or restart `pi-ambient-synth-midi`.

## Sniff your KeyStep on the Pi

```bash
# On the Pi (stop the bridge briefly if port is busy):
sudo systemctl stop pi-ambient-synth-midi
cd ~/pi-ambient-synth
PI_MIDI_LOG_TRANSPORT=1 .venv/bin/python scripts/pi_midi_listen.py 30
# Press Hold, Chord, Tap Tempo, knobs — note any control_change lines
sudo systemctl start pi-ambient-synth-midi
```

## Pitch & mod strips in MCC

In MCC you **can** set:

- **Pitch strip** — usually pitch bend (handled by the Pi bridge).
- **Mod strip** — assign **CC 1** (default) for filter; do not remap CC 1 to something else if you want the mod strip to open the filter.

Weather/drift in the synth uses **CC 74**, not CC 1, so mod and weather do not conflict.
