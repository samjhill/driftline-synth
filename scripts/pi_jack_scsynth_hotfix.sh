#!/usr/bin/env bash
# Pi SC 3.13: external jackd + scsynth JACK client (fixes JackTemporaryException from embedded jackdmp).
#
# Pin raw URLs to a commit (main CDN can lag). Latest jack+audio fix:
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/7018002/scripts/pi_jack_scsynth_hotfix.sh | bash
# Override fetch SHA: GITHUB_REF=<commit> (default below is pinned, not main).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
# Default SHA pins fetched tree (override: GITHUB_REF=main or a branch name).
REF="${GITHUB_REF:-7018002}"
LOG="/var/log/pi-ambient-synth-jack-hotfix.log"

log() { echo "$(date -Iseconds) [jack-hotfix] $*" | tee -a "$LOG"; }

if [[ "$(id -un)" != "pi" && "$(id -un)" != "root" ]]; then
  echo "Run as pi (e.g. curl ... | sudo -u pi bash)" >&2
  exit 1
fi

sudo mkdir -p "$(dirname "$LOG")" /var/lib/pi-ambient-synth
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

log "Resolving ${REPO}@${REF}"
sha="$(resolve_ref)"
short="${sha:0:7}"
base="https://raw.githubusercontent.com/${REPO}/${sha}"
log "Fetching ${short}"

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

log "Stopping PipeWire/JACK grabbers and freeing ALSA"
for svc in pipewire pipewire-pulse wireplumber pulseaudio jackd2; do
  sudo systemctl stop "$svc" 2>/dev/null || true
done
pkill -x scsynth 2>/dev/null || true
pkill -x jackd 2>/dev/null || true
sleep 0.5

log "Installing supercollider.service"
sudo cp "$INSTALL_DIR/systemd/supercollider.service" /etc/systemd/system/supercollider.service
sudo systemctl daemon-reload

log "Starting jackd + scsynth"
if ! "$INSTALL_DIR/scripts/start_scsynth_alsa.sh"; then
  log "ERROR: start_scsynth_alsa failed"
  tail -40 /tmp/scsynth-alsa-start.log | tee -a "$LOG" || true
  exit 1
fi

log "Engine smoke (SC_ENGINE_TEST)"
export PI_AMBIENT_ROOT="$INSTALL_DIR"
export SC_HEADLESS_ALSA=1
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-hw:0,0}"
export JACK_NO_START_SERVER=1
export JACK_NO_AUDIO_RESERVATION=1
if ! "$INSTALL_DIR/scripts/engine_smoke_pi.sh" --restart; then
  log "WARN: engine smoke failed — see /tmp/pi-ambient-engine-smoke.log"
  tail -30 /tmp/pi-ambient-engine-smoke.log | tee -a "$LOG" || true
  exit 1
fi

log "Restarting systemd services"
rm -f /var/lib/pi-ambient-synth/sc-engine-ready 2>/dev/null || true
sudo systemctl restart supercollider.service
sleep 20
sudo systemctl restart pi-ambient-synth.service

log "Done ($short)"
echo "  jackd:    $(pgrep -a jackd || echo MISSING)"
echo "  scsynth:  $(pgrep -a scsynth || echo MISSING)"
echo "  ready:    $(ls -la /var/lib/pi-ambient-synth/sc-engine-ready 2>/dev/null || echo MISSING)"
echo "  log:      tail -30 /tmp/scsynth-alsa-start.log"
echo "  journal:  sudo journalctl -u supercollider -n 25 --no-pager | grep -E 'jackExternal|listening on OSC|ERROR'"
