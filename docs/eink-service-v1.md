# E-ink V1 — single service architecture

Stabilization mode: one process owns the Waveshare HAT. Audio never waits on the panel.

## Service

`pi-ambient-synth-eink.service` runs `scripts/eink_service.py`:

1. `eink_kill_legacy_holders.sh` (GhostRoll, stray GPIO)
2. Startup splash once
3. Poll `/run/pi-ambient-synth/eink-queue/*.json`
4. Process one message → update → panel sleep
5. Write health to `/var/lib/pi-ambient-synth/eink-service.json`

**Boot order:** `pi-ambient-synth-midi.service` first, then `pi-ambient-synth-eink.service`.

## Clients (queue only)

```bash
.venv/bin/python scripts/eink_enqueue.py startup
.venv/bin/python scripts/eink_enqueue.py status boot "Booting" "Pi Ambient Synth" ""
.venv/bin/python scripts/eink_enqueue.py patch --from-state
```

From Python:

```python
from eink_queue import enqueue_patch, enqueue_status
enqueue_patch(from_state=True)
```

**Do not** call `show_status.py`, `boot_display.sh`, or import `waveshare_epd` outside the service.

## Reseed

`pi_midi_bridge.py` enqueues `patch --from-state` only (no subprocess, no GPIO).

## Legacy units (masked by `eink_install_systemd.sh`)

- `pi-ambient-synth-boot-display`
- `pi-ambient-synth-eink-boot` / `eink-prepare` / `eink-patch`
- `pi-ambient-synth-network-announce` (network still saved; e-ink via queue in `announce_network.py`)
- `pi-ambient-synth-audio-display`

## Monitor

HTTP monitor shows e-ink service active, last OK time, queue depth, last error, and MIDI bridge active.

## Install

```bash
./install.sh --enable-services   # runs eink_install_systemd.sh
# or on Pi:
./scripts/eink_install_systemd.sh
```

## Acceptance (cold boot)

- [ ] KeyStep → sound without waiting for e-ink
- [ ] `systemctl is-active pi-ambient-synth-midi` = active
- [ ] `systemctl is-active pi-ambient-synth-eink` = active
- [ ] No `ghostroll` / `scsynth` / `jackd` holders on SPI
- [ ] Startup visible once; reseed updates patch name
- [ ] Repeated reseeds do not wedge (`queue_depth` returns to 0)
- [ ] Reboot repeats reliably
