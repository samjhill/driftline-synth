#!/usr/bin/env bash
# Pi SC 3.13: external jackd + scsynth JACK client + sclang engine (one-shot deploy).
#
# Pin everything to PINNED_SHA (raw CDN + fetched files). Example:
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/86d275b/scripts/pi_jack_scsynth_hotfix.sh | bash
set -euo pipefail

PINNED_SHA="86d275b"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
REF="${GITHUB_REF:-$PINNED_SHA}"
LOG="/var/log/pi-ambient-synth-jack-hotfix.log"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"

log() { echo "$(date -Iseconds) [jack-hotfix] $*" | tee -a "$LOG"; }

if [[ "$(id -un)" != "pi" && "$(id -un)" != "root" ]]; then
  echo "Run as pi (e.g. curl ... | sudo -u pi bash)" >&2
  exit 1
fi

sudo mkdir -p "$(dirname "$LOG")" "$MARKER_DIR"
sudo touch "$LOG"
sudo chown pi:pi "$LOG" 2>/dev/null || true

resolve_ref() {
  if [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "$REF"
    return
  fi
  curl -fsSL "https://api.github.com/repos/${REPO}/commits/${REF}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])"
}

stack_looks_up() {
  pgrep -x jackd >/dev/null && pgrep -x scsynth >/dev/null || return 1
  if command -v ss >/dev/null && ss -uln 2>/dev/null | grep -qE ':57110[[:space:]]'; then
    return 0
  fi
  command -v jack_lsp >/dev/null && jack_lsp 2>/dev/null | grep -qi supercollider
}

free_alsa() {
  log "Stopping PipeWire/JACK grabbers"
  for svc in pipewire pipewire-pulse wireplumber pulseaudio jackd2; do
    sudo systemctl stop "$svc" 2>/dev/null || true
  done
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  sleep 0.5
}

log "Resolving ${REPO}@${REF}"
sha="$(resolve_ref)"
short="${sha:0:7}"
base="https://raw.githubusercontent.com/${REPO}/${sha}"
log "Fetching ${short} (bootstrap PINNED_SHA=${PINNED_SHA})"

mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/synth" "$INSTALL_DIR/systemd"

fetch() {
  local rel="$1"
  local dest="$INSTALL_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  curl -fsSL "${base}/${rel}" -o "$dest"
  log "  got $rel"
}

for rel in \
  scripts/start_scsynth_alsa.sh \
  scripts/run_sclang_engine.sh \
  scripts/engine_smoke_pi.sh \
  scripts/diagnose_scsynth_audio.sh \
  synth/ambient_engine.scd \
  systemd/supercollider.service; do
  fetch "$rel"
done

chmod +x \
  "$INSTALL_DIR/scripts/start_scsynth_alsa.sh" \
  "$INSTALL_DIR/scripts/run_sclang_engine.sh" \
  "$INSTALL_DIR/scripts/engine_smoke_pi.sh" \
  "$INSTALL_DIR/scripts/diagnose_scsynth_audio.sh"

if ! grep -q 'sc313-jackFork' "$INSTALL_DIR/synth/ambient_engine.scd"; then
  log "ERROR: ambient_engine.scd missing sc313-jackFork marker"
  exit 1
fi

free_alsa

log "Installing supercollider.service"
sudo cp "$INSTALL_DIR/systemd/supercollider.service" /etc/systemd/system/supercollider.service
sudo mkdir -p /etc/systemd/system/supercollider.service.d
sudo tee /etc/systemd/system/supercollider.service.d/audio.conf >/dev/null <<EOF
[Service]
LimitMEMLOCK=infinity
Environment=JACK_NO_START_SERVER=1
Environment=JACK_NO_AUDIO_RESERVATION=1
Environment=SC_HEADLESS_ALSA=1
Environment=SC_AUDIO_DEVICE=hw:0,0
EOF
sudo systemctl daemon-reload

log "Starting jackd + scsynth"
if ! "$INSTALL_DIR/scripts/start_scsynth_alsa.sh"; then
  log "ERROR: start_scsynth_alsa failed"
  tail -40 /tmp/scsynth-alsa-start.log | tee -a "$LOG" || true
  exit 1
fi

if ! stack_looks_up; then
  log "ERROR: audio stack not up after start_scsynth_alsa"
  exit 1
fi

log "Engine smoke (SC_ENGINE_TEST, reuse running jackd/scsynth)"
export PI_AMBIENT_ROOT="$INSTALL_DIR"
export SC_HEADLESS_ALSA=1
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-hw:0,0}"
export JACK_NO_START_SERVER=1
export JACK_NO_AUDIO_RESERVATION=1
export ENGINE_SMOKE_TIMEOUT="${ENGINE_SMOKE_TIMEOUT:-120}"
if ! "$INSTALL_DIR/scripts/engine_smoke_pi.sh" --reuse-audio; then
  log "ERROR: engine smoke failed"
  tail -40 /tmp/pi-ambient-engine-smoke.log | tee -a "$LOG" || true
  exit 1
fi

log "Restarting systemd services"
rm -f "$MARKER_DIR/sc-engine-ready" 2>/dev/null || true
sudo systemctl restart supercollider.service
sleep 25
if ! systemctl is-active supercollider.service >/dev/null; then
  log "WARN: supercollider.service not active"
  sudo journalctl -u supercollider -n 30 --no-pager | tee -a "$LOG" || true
fi
sudo systemctl restart pi-ambient-synth.service

if [[ -x "$INSTALL_DIR/.venv/bin/python" && -f "$INSTALL_DIR/scripts/test_osc.py" ]]; then
  log "OSC test (optional)"
  if ! "$INSTALL_DIR/.venv/bin/python" "$INSTALL_DIR/scripts/test_osc.py"; then
    log "WARN: test_osc.py failed (MIDI path may still work after ready marker)"
  fi
fi

log "Done ($short)"
echo "  jackd:    $(pgrep -a jackd || echo MISSING)"
echo "  scsynth:  $(pgrep -a scsynth || echo MISSING)"
echo "  ready:    $(ls -la $MARKER_DIR/sc-engine-ready 2>/dev/null || echo MISSING)"
echo "  smoke:    grep ENGINE_TEST /tmp/pi-ambient-engine-smoke.log"
echo "  journal:  sudo journalctl -u supercollider -n 30 --no-pager | grep -E 'jackFork|listening on OSC|ERROR'"
