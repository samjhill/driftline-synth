# Autonomous Pi iteration (no manual headphone checks)

## Goal

From your Mac, run one command and get **PASS/FAIL** with evidence that:

1. **Audio chain** — jackd → scsynth → JACK → headphones path (OSC beep hits SC)
2. **MIDI note path** — note_on → Python logic → OSC → SC (`playNote` / voice in journal)
3. **Shift+Play reseed** — CC63 + MIDI start → reseed → new patch seed in state + OSC

Human listening is optional; the scripts grep journals and state files.

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

## What still needs the physical keyboard

- Exclusive MIDI port: `pi-ambient-synth` holds the KeyStep input while running.
- E2E tests **the same code paths** via `simulate_midi_e2e.py` (synthetic MIDI messages).
- After E2E PASS, plug in KeyStep and play; if silent, check `pi-ambient-synth` is **active** (not `activating`/SIGBUS).

## Agent workflow

1. Change code on Mac.
2. `./scripts/run_pi_iterate.sh` until PASS.
3. Tell user to play one note + Shift+Play once (sanity); optional.

Saved SSH password: `./scripts/run_pi_verify.sh --save-password` once.
