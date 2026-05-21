#!/usr/bin/env bash
# Clean restart of supercollider + pi-ambient-synth (production deploy + verify).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
READY="$MARKER_DIR/sc-engine-ready"
WAIT_READY_SEC="${WAIT_READY_SEC:-60}"
SYNTH_WAIT_SEC="${SYNTH_WAIT_SEC:-45}"
MIDI_WAIT_SEC="${MIDI_WAIT_SEC:-20}"

# shellcheck source=scripts/lib/audio_stack.sh
source "$INSTALL_DIR/scripts/lib/audio_stack.sh"

log() { echo "$(date -Iseconds) [restart-synth] $*"; }

if [[ -f /etc/pi-ambient-synth/audio-mode.conf ]] \
  && grep -q 'AUDIO_MODE=direct_keys' /etc/pi-ambient-synth/audio-mode.conf 2>/dev/null; then
  log "audio-mode=direct_keys — skip SuperCollider/JACK"
  if [[ -x "$INSTALL_DIR/scripts/pi_enable_direct_keys.sh" ]]; then
    "$INSTALL_DIR/scripts/pi_enable_direct_keys.sh"
    exit 0
  fi
fi

if [[ -f /etc/pi-ambient-synth/audio-mode.conf ]] \
  && grep -q 'AUDIO_MODE=flues' /etc/pi-ambient-synth/audio-mode.conf 2>/dev/null; then
  log "audio-mode=flues — Flues-Synth + MIDI bridge"
  if [[ -x "$INSTALL_DIR/scripts/install_flues_synth.sh" ]]; then
    INSTALL_DIR="$INSTALL_DIR" "$INSTALL_DIR/scripts/install_flues_synth.sh" || true
  fi
  sudo systemctl stop pi-ambient-synth-deploy.timer pi-ambient-synth-midi.service \
    pi-ambient-synth.service supercollider.service pi-ambient-alsa-drone.service pi-flues-synth.service 2>/dev/null || true
  pkill -x sclang 2>/dev/null || true
  free_alsa
  sleep 1.5
  install_flues_systemd_units "$INSTALL_DIR"
  sudo systemctl reset-failed pi-flues-synth.service pi-ambient-synth-midi.service 2>/dev/null || true
  rm -f "$READY" 2>/dev/null || true
  echo "flues" | sudo tee "$MARKER_DIR/audio-backend.txt" >/dev/null

  log "start MIDI bridge (KeyStep) before Flues"
  sudo systemctl start pi-ambient-synth-midi.service
  sleep 2
  log "start pi-flues-synth"
  if [[ ! -x "$INSTALL_DIR/bin/flues-synth" ]]; then
    echo "ERROR: $INSTALL_DIR/bin/flues-synth missing — run install_flues_synth.sh on Pi" >&2
    exit 1
  fi
  sudo systemctl start pi-flues-synth.service
  flues_ok=0
  for _ in $(seq 1 25); do
    if systemctl is-active --quiet pi-flues-synth.service && pgrep -x flues-synth >/dev/null; then
      flues_ok=1
      break
    fi
    sleep 1
  done
  if [[ "$flues_ok" -ne 1 ]]; then
    echo "ERROR: pi-flues-synth.service not active" >&2
    journalctl -u pi-flues-synth -n 25 --no-pager >&2 || true
    exit 1
  fi
  log "start pi-ambient-synth (monitor/e-ink)"
  sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
  sleep 2
  [[ -x "$INSTALL_DIR/scripts/connect_midi_to_flues.sh" ]] && "$INSTALL_DIR/scripts/connect_midi_to_flues.sh" || true
  systemctl is-active pi-flues-synth.service pi-ambient-synth-midi.service 2>/dev/null || true
  if [[ "${PI_SKIP_DEPLOY_TIMER:-0}" != "1" ]]; then
    sudo systemctl start pi-ambient-synth-deploy.timer 2>/dev/null || true
  else
    log "PI_SKIP_DEPLOY_TIMER=1 — leaving deploy timer stopped"
  fi
  exit 0
fi

log "stop deploy timer + synth services"
sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true
sudo systemctl stop pi-ambient-synth-midi.service 2>/dev/null || true
sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
sudo systemctl stop supercollider.service pi-flues-synth.service 2>/dev/null || true
pkill -x sclang flues-synth 2>/dev/null || true
free_alsa
sleep 2.0

install_sc_systemd_units "$INSTALL_DIR"
sudo systemctl reset-failed supercollider.service pi-ambient-synth.service pi-ambient-synth-midi.service 2>/dev/null || true
rm -f "$READY" 2>/dev/null || true

log "start supercollider"
sudo systemctl start supercollider.service
for _ in $(seq 1 "$WAIT_READY_SEC"); do
  if [[ -f "$READY" ]] && systemctl is-active --quiet supercollider.service; then
    log "supercollider active + sc-engine-ready"
    if [[ -x "$INSTALL_DIR/scripts/ensure_jack_playback.sh" ]]; then
      "$INSTALL_DIR/scripts/ensure_jack_playback.sh" || true
    fi
    break
  fi
  sleep 1
done

if ! systemctl is-active --quiet supercollider.service; then
  echo "ERROR: supercollider.service not active" >&2
  journalctl -u supercollider -n 20 --no-pager >&2 || true
  exit 1
fi
j_sc="$(journalctl -u supercollider -n 30 --no-pager 2>/dev/null || true)"
if echo "$j_sc" | grep -qiE 'syntax error|command line parse failed|unexpected.*expecting'; then
  echo "ERROR: supercollider journal shows sclang compile failure — run validate_ambient_engine.py" >&2
  echo "$j_sc" | tail -15 >&2
  exit 1
fi
if ! echo "$j_sc" | grep -q 'Engine synths started'; then
  echo "WARN: supercollider active but 'Engine synths started' not in journal yet" >&2
fi

log "start pi-ambient-synth"
# Brief active window can still be SIGBUS if numpy loads at import; confirm process stays up.
sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
sleep 1
sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
synth_ok=0
for _ in $(seq 1 "$SYNTH_WAIT_SEC"); do
  if systemctl is-active --quiet pi-ambient-synth.service \
    && ! journalctl -u pi-ambient-synth -n 3 --no-pager 2>/dev/null | grep -q 'status=7/BUS'; then
    sleep 2
    if systemctl is-active --quiet pi-ambient-synth.service; then
      synth_ok=1
      break
    fi
  fi
  sleep 1
done
if [[ "$synth_ok" -ne 1 ]]; then
  echo "ERROR: pi-ambient-synth.service not active after ${SYNTH_WAIT_SEC}s" >&2
  journalctl -u pi-ambient-synth -n 25 --no-pager >&2 || true
  systemctl show pi-ambient-synth.service -p Result,NRestarts,ExecMainStatus --no-pager >&2 || true
  exit 1
fi
log "pi-ambient-synth active"

log "start pi-ambient-synth-midi"
sudo systemctl enable pi-ambient-synth-midi.service 2>/dev/null || true
sudo systemctl start pi-ambient-synth-midi.service 2>/dev/null || true
midi_ok=0
for _ in $(seq 1 "$MIDI_WAIT_SEC"); do
  if systemctl is-active --quiet pi-ambient-synth-midi.service; then
    midi_ok=1
    break
  fi
  sleep 1
done
if [[ "$midi_ok" -ne 1 ]]; then
  echo "WARN: pi-ambient-synth-midi.service not active after ${MIDI_WAIT_SEC}s" >&2
  journalctl -u pi-ambient-synth-midi -n 15 --no-pager >&2 || true
fi

sudo systemctl stop pi-ambient-alsa-drone.service 2>/dev/null || true
sudo systemctl disable pi-ambient-alsa-drone.service 2>/dev/null || true

systemctl is-active supercollider.service pi-ambient-synth.service pi-ambient-synth-midi.service 2>/dev/null || true
if [[ "${PI_SKIP_DEPLOY_TIMER:-0}" != "1" ]]; then
  sudo systemctl start pi-ambient-synth-deploy.timer 2>/dev/null || true
else
  log "PI_SKIP_DEPLOY_TIMER=1 — leaving deploy timer stopped"
fi

if [[ ! -f "$READY" ]]; then
  echo "WARN: $READY not present — OSC notes may be silent until engine finishes boot" >&2
fi
