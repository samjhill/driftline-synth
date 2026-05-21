#!/usr/bin/env bash
# Pi SC 3.13: external jackd + scsynth + sclang (SSH-safe: progress pings, optional phases).
#
# Full run (use tmux/screen if SSH is flaky):
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/ef14375/scripts/pi_jack_scsynth_hotfix.sh | bash
#
# Split phases (recommended over SSH):
#   HOTFIX_FETCH_ONLY=1  curl -fsSL .../pi_jack_scsynth_hotfix.sh | bash
#   HOTFIX_AUDIO_ONLY=1  curl -fsSL .../pi_jack_scsynth_hotfix.sh | bash
#   HOTFIX_SMOKE_ONLY=1  curl -fsSL .../pi_jack_scsynth_hotfix.sh | bash
#   HOTFIX_SERVICES_ONLY=1 curl -fsSL .../pi_jack_scsynth_hotfix.sh | bash
set -euo pipefail

PINNED_SHA="ef14375"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
REF="${GITHUB_REF:-$PINNED_SHA}"
LOG="/var/log/pi-ambient-synth-jack-hotfix.log"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"

log() { echo "$(date -Iseconds) [jack-hotfix] $*" | tee -a "$LOG"; }
ping() { echo "[jack-hotfix] $*"; }

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
  curl -fsSL --connect-timeout 15 --max-time 60 \
    "https://api.github.com/repos/${REPO}/commits/${REF}" \
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
  log "Stopping grabbers + orphan SC/JACK"
  for svc in pipewire pipewire-pulse wireplumber pulseaudio jackd2; do
    sudo systemctl stop "$svc" 2>/dev/null || true
  done
  pkill -x sclang 2>/dev/null || true
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  sleep 0.5
}

do_fetch() {
  ping "Resolving ${REPO}@${REF} ..."
  local sha short base
  sha="$(resolve_ref)"
  short="${sha:0:7}"
  base="https://raw.githubusercontent.com/${REPO}/${sha}"
  log "Fetching ${short} (PINNED_SHA=${PINNED_SHA})"

  mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/synth" "$INSTALL_DIR/systemd"

  fetch() {
    local rel="$1" dest="$INSTALL_DIR/$rel"
    ping "  curl $rel ..."
    mkdir -p "$(dirname "$dest")"
    curl -fsSL --connect-timeout 20 --max-time 120 "${base}/${rel}" -o "$dest"
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
}

do_install_unit() {
  ping "Installing supercollider.service ..."
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
  ping "systemd unit installed"
}

do_audio() {
  free_alsa
  do_install_unit
  ping "Starting jackd + scsynth ..."
  if ! "$INSTALL_DIR/scripts/start_scsynth_alsa.sh"; then
    log "ERROR: start_scsynth_alsa failed"
    tail -40 /tmp/scsynth-alsa-start.log | tee -a "$LOG" || true
    exit 1
  fi
  if ! stack_looks_up; then
    log "ERROR: audio stack not up"
    exit 1
  fi
  ping "Audio stack up: $(pgrep -a jackd | head -1) | $(pgrep -a scsynth | head -1)"
}

do_smoke() {
  export PI_AMBIENT_ROOT="$INSTALL_DIR"
  export SC_HEADLESS_ALSA=1
  export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-hw:0,0}"
  export JACK_NO_START_SERVER=1
  export JACK_NO_AUDIO_RESERVATION=1
  export ENGINE_SMOKE_TIMEOUT="${ENGINE_SMOKE_TIMEOUT:-90}"

  if ! stack_looks_up; then
    ping "Stack not up — starting audio first"
    do_audio
  fi

  ping "Engine smoke (~${ENGINE_SMOKE_TIMEOUT}s, log /tmp/pi-ambient-engine-smoke.log) ..."
  rm -f /tmp/pi-ambient-engine-smoke.log 2>/dev/null || true
  set +e
  "$INSTALL_DIR/scripts/engine_smoke_pi.sh" --reuse-audio &
  local smoke_pid=$!
  set -e
  local n=0
  while kill -0 "$smoke_pid" 2>/dev/null; do
    sleep 5
    n=$((n + 5))
    ping "  smoke running ${n}s — $(grep -c . /tmp/pi-ambient-engine-smoke.log 2>/dev/null || echo 0) log lines"
    if [[ $n -ge $((ENGINE_SMOKE_TIMEOUT + 15)) ]]; then
      kill "$smoke_pid" 2>/dev/null || true
      log "ERROR: smoke timeout"
      exit 1
    fi
  done
  wait "$smoke_pid" || smoke_st=$?
  smoke_st=${smoke_st:-0}
  if [[ "$smoke_st" -ne 0 ]]; then
    log "ERROR: engine smoke exit $smoke_st"
    tail -40 /tmp/pi-ambient-engine-smoke.log | tee -a "$LOG" || true
    exit 1
  fi
  if ! grep -q 'Pi Ambient Synth ENGINE_TEST ok' /tmp/pi-ambient-engine-smoke.log; then
    log "ERROR: ENGINE_TEST ok not in smoke log"
    tail -40 /tmp/pi-ambient-engine-smoke.log | tee -a "$LOG" || true
    exit 1
  fi
  ping "Engine smoke passed"
}

do_services() {
  ping "Restarting supercollider.service ..."
  rm -f "$MARKER_DIR/sc-engine-ready" 2>/dev/null || true
  sudo systemctl restart supercollider.service
  sleep 20
  ping "Restarting pi-ambient-synth.service ..."
  sudo systemctl restart pi-ambient-synth.service
  sleep 3
  ping "Services: SC=$(systemctl is-active supercollider.service 2>/dev/null || echo ?) synth=$(systemctl is-active pi-ambient-synth.service 2>/dev/null || echo ?)"
}

# --- phase dispatch ---
if [[ "${HOTFIX_FETCH_ONLY:-}" == "1" ]]; then
  do_fetch
  ping "FETCH_ONLY done"
  exit 0
fi
if [[ "${HOTFIX_AUDIO_ONLY:-}" == "1" ]]; then
  do_fetch
  do_audio
  ping "AUDIO_ONLY done"
  exit 0
fi
if [[ "${HOTFIX_SMOKE_ONLY:-}" == "1" ]]; then
  do_smoke
  ping "SMOKE_ONLY done"
  exit 0
fi
if [[ "${HOTFIX_SERVICES_ONLY:-}" == "1" ]]; then
  do_services
  ping "SERVICES_ONLY done"
  exit 0
fi

# Full pipeline (skip heavy steps over SSH if set)
do_fetch
do_audio

if [[ "${HOTFIX_SKIP_SMOKE:-}" != "1" ]]; then
  do_smoke
else
  ping "SKIP_SMOKE=1 — run HOTFIX_SMOKE_ONLY=1 in tmux next"
fi

if [[ "${HOTFIX_SKIP_SERVICES:-}" != "1" ]]; then
  do_services
else
  ping "SKIP_SERVICES=1 — run HOTFIX_SERVICES_ONLY=1 after smoke OK"
fi

if [[ "${HOTFIX_RUN_OSC:-}" == "1" && -x "$INSTALL_DIR/.venv/bin/python" ]]; then
  ping "test_osc.py ..."
  "$INSTALL_DIR/.venv/bin/python" "$INSTALL_DIR/scripts/test_osc.py" || true
fi

log "Done"
echo "  jackd:   $(pgrep -a jackd || echo MISSING)"
echo "  scsynth: $(pgrep -a scsynth || echo MISSING)"
echo "  ready:   $(ls -la $MARKER_DIR/sc-engine-ready 2>/dev/null || echo MISSING)"
