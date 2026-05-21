# Autonomous Pi iteration (no manual headphone checks)

## Goal

From your Mac, run one command and get **PASS/FAIL** with evidence that:

1. **Audio chain** — jackd → scsynth → JACK → headphones path (OSC beep hits SC)
2. **MIDI note path** — note_on → Python logic → OSC → SC (`playNote` / voice in journal)
3. **Shift+Play reseed** — CC63 + MIDI start → reseed → new patch seed in state + OSC

Human listening is optional; the scripts grep journals and state files.

E2E also runs **`assert_monitor_status.py`**, which calls the same **`collect_status()`** as the LAN status page (`http://<pi-ip>:8080/`), saves snapshots under `/var/lib/pi-ambient-synth/`, and pulls them back to the Mac as `.pi-e2e-status-page.txt` / `.pi-e2e-status.json`.

## Commands

```bash
# One-shot (verify audio + restart services + e2e)
./scripts/run_pi_e2e.sh

# Retry until pass (for agents / flaky Pi audio)
./scripts/run_pi_iterate.sh 8

# On the Pi only (after git pull or curl sync)
curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/recover_pi_audio.sh | bash
export INSTALL_DIR=~/pi-ambient-synth
~/pi-ambient-synth/scripts/pi_e2e_verify.sh
```

## What PASS means (~95% confidence)

| Check | Evidence |
|-------|----------|
| supercollider active | `systemctl` |
| Engine ready | `/var/lib/pi-ambient-synth/sc-engine-ready` |
| JACK → headphones | `jack_lsp` / `SC_JACK_DEFAULT_OUTPUTS` |
| OSC beep | journal: `pi_test_beep 440 Hz` |
| Shift+Play reseed | `simulate_midi_e2e.py`: seed changes, reseed OSC |
| MIDI note | same script: `note_on ok`, SC journal activity |
| Status page | `assert_monitor_status.py`: services active, no SIGBUS, SC ready, deploy SHA, MIDI label, journals match UI |
| SC syntax | `validate_ambient_engine.py` on Mac + Pi; journal must not contain `syntax error` / `Command line parse failed`; must contain `Engine synths started` |
| Audible | `verify_audible_pi.sh`: JACK linked, `play_headphone_test.py` (ALSA), `test_osc` beep; engine plays **startup chime** on boot |

After each run, on the Mac:

- `.pi-e2e-status-page.txt` — human-readable status page dump
- `.pi-e2e-status.json` — full `collect_status()` JSON from the Pi
- `.pi-e2e-api-status.json` — optional curl of `/api/status` (when monitor is up)

On the Pi: `/var/lib/pi-ambient-synth/e2e-status-snapshot.json` and `e2e-status-page.txt`.

Optional: `PI_EXPECT_DEPLOY_SHA=<7-char>` when running assert on the Pi to fail on stale deploy SHA.

`run_pi_e2e.sh` also writes `last_deploy_sha` on the Pi from the Mac rsync ref so the status page SHA matches the code under test (deploy timer may still show an older GitHub SHA until the next pull).

## What still needs the physical keyboard

- Exclusive MIDI port: `pi-ambient-synth` holds the KeyStep input while running.
- E2E tests **the same code paths** via `simulate_midi_e2e.py` (synthetic MIDI messages).
- After E2E PASS, plug in KeyStep and play; if silent, check `pi-ambient-synth` is **active** (not `activating`/SIGBUS).

### Pi production SIGBUS (`status=7/BUS`)

`pi-ambient-synth.service` runs `main.py --no-eink` with `PI_NO_MIDI=1`. **Do not import `numpy` / `visual_generator` in that process** — on some Pi images `import numpy` alone SIGBUSes. MIDI runs in `pi-ambient-synth-midi.service` (`pi_midi_bridge.py`). E-ink rendering uses numpy only when the display is enabled.

## Agent workflow

1. Change code on Mac.
2. `./scripts/run_pi_iterate.sh` until PASS.
3. Tell user to play one note + Shift+Play once (sanity); optional.

Saved SSH password: `./scripts/run_pi_verify.sh --save-password` once.
