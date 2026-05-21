#!/usr/bin/env bash
# One-shot Pi audio + engine verify. Fetch → jackd/scsynth (retries) → sclang smoke → PASS/FAIL.
#
# On the Pi (uses latest main unless GITHUB_REF is set):
#   curl -fsSL https://raw.githubusercontent.com/samjhill/driftline-synth/main/scripts/pi_verify.sh | bash
#
# From your Mac (preferred — no CDN lag, uses this repo):
#   ./scripts/run_pi_verify.sh
#
# Phases: all (default) | sync | audio | engine | services
set -euo pipefail

PHASE="${1:-all}"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
REPO="${GITHUB_REPO:-samjhill/driftline-synth}"
# Tree to fetch; default main tip (avoids stale PINNED_SHA 404s). Override: GITHUB_REF=abc1234
REF="${GITHUB_REF:-main}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
RESULT_FILE="${PI_VERIFY_RESULT:-$MARKER_DIR/verify-last.txt}"
LOG="${PI_VERIFY_LOG:-/var/log/pi-ambient-verify.log}"
AUDIO_RETRIES="${PI_AUDIO_RETRIES:-3}"
ENGINE_TIMEOUT="${ENGINE_SMOKE_TIMEOUT:-180}"

export SC_HEADLESS_ALSA=1
export SC_AUDIO_DEVICE="${SC_AUDIO_DEVICE:-hw:0,0}"
export JACK_NO_START_SERVER=1
export JACK_NO_AUDIO_RESERVATION=1
export SC_JACK_NPERIODS="${SC_JACK_NPERIODS:-3}"

fail() {
  local msg="$1"
  echo "FAIL: $msg" | tee -a "$LOG" >&2
  echo "status=fail phase=$PHASE at=$(date -Iseconds) msg=$msg" >"$RESULT_FILE"
  echo "--- audio log (last 20) ---" >&2
  tail -20 /tmp/scsynth-alsa-start.log 2>/dev/null >&2 || true
  echo "--- engine log (last 25) ---" >&2
  tail -25 /tmp/pi-ambient-engine-smoke.log 2>/dev/null >&2 || true
  exit 1
}

pass() {
  echo "PASS: Pi audio + engine verify OK" | tee -a "$LOG"
  echo "status=pass at=$(date -Iseconds) ref=${TREE_SHORT:-unknown}" >"$RESULT_FILE"
}

log() { echo "$(date -Iseconds) [pi-verify] $*" | tee -a "$LOG"; }

if [[ "$(id -un)" != "pi" && "$(id -un)" != "root" ]]; then
  echo "Run as pi (curl ... | sudo -u pi bash)" >&2
  exit 1
fi

sudo mkdir -p "$(dirname "$LOG")" "$MARKER_DIR"
sudo touch "$LOG" 2>/dev/null || true
sudo chown pi:pi "$LOG" "$MARKER_DIR" 2>/dev/null || true

resolve_ref() {
  if [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "$REF"
    return
  fi
  curl -fsSL --connect-timeout 15 --max-time 60 \
    "https://api.github.com/repos/${REPO}/commits/${REF}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])"
}

stop_audio_stack() {
  local port="${SC_SYNTH_PORT:-57110}"
  pkill -x scsynth 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
  pkill -9 -x scsynth 2>/dev/null || true
  pkill -9 -x jackd 2>/dev/null || true
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${port}/udp" 2>/dev/null || true
  fi
  sleep 1.0
  rm -f /dev/shm/jack-* /dev/shm/jackdmp* /dev/shm/sem.jack* 2>/dev/null || true
}

free_alsa() {
  for svc in pipewire pipewire-pulse wireplumber pulseaudio jackd2; do
    sudo systemctl stop "$svc" 2>/dev/null || true
  done
  pkill -x sclang 2>/dev/null || true
  stop_audio_stack
  sleep 1.0
}

stack_up() {
  pgrep -x jackd >/dev/null && pgrep -x scsynth >/dev/null || return 1
  ls /dev/shm/jack* 1>/dev/null 2>&1 || return 1
  if command -v ss >/dev/null && ss -uln 2>/dev/null | grep -qE ':57110[[:space:]]'; then
    return 0
  fi
  command -v nc >/dev/null && nc -u -z -w1 127.0.0.1 57110 2>/dev/null
}

do_sync() {
  if [[ "${PI_SKIP_FETCH:-}" == "1" ]]; then
    log "skip fetch (PI_SKIP_FETCH=1)"
    return 0
  fi
  local sha base
  sha="$(resolve_ref)"
  TREE_SHORT="${sha:0:7}"
  base="https://raw.githubusercontent.com/${REPO}/${sha}"
  log "sync ${TREE_SHORT} from ${REPO}"

  mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/synth" "$INSTALL_DIR/systemd"
  for rel in \
    scripts/pi_verify.sh \
    scripts/start_scsynth_alsa.sh \
    scripts/run_sclang_engine.sh \
    scripts/engine_smoke_pi.sh \
    scripts/diagnose_scsynth_audio.sh \
    synth/pi_bind_port.scd \
    synth/ambient_engine.scd \
    systemd/supercollider.service; do
    curl -fsSL --connect-timeout 20 --max-time 120 "${base}/${rel}" -o "$INSTALL_DIR/$rel"
  done
  chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
  grep -qE 'sc313-(selectKr|bindPort|sclangBoot|langPort|jackAttach|jackLink)' "$INSTALL_DIR/synth/ambient_engine.scd" \
    || fail "ambient_engine.scd missing sc313-selectKr marker"
}

install_units() {
  sudo cp "$INSTALL_DIR/systemd/supercollider.service" /etc/systemd/system/supercollider.service
  if [[ -f "$INSTALL_DIR/systemd/pi-ambient-synth.service" ]]; then
    sudo cp "$INSTALL_DIR/systemd/pi-ambient-synth.service" /etc/systemd/system/pi-ambient-synth.service
  fi
  sudo mkdir -p /etc/systemd/system/supercollider.service.d
  sudo tee /etc/systemd/system/supercollider.service.d/audio.conf >/dev/null <<EOF
[Service]
LimitMEMLOCK=infinity
Environment=JACK_NO_START_SERVER=1
Environment=JACK_NO_AUDIO_RESERVATION=1
Environment=SC_HEADLESS_ALSA=1
Environment=SC_AUDIO_DEVICE=hw:0,0
Environment=SC_JACK_PERIOD=4096
Environment=SC_JACK_NPERIODS=3
EOF
  sudo systemctl daemon-reload
}

# Period sizes to try (headless Pi: larger = fewer XRuns).
audio_period_for_attempt() {
  case "$1" in
    1) echo 4096 ;;
    2) echo 4096 ;;
    3) echo 8192 ;;
    4) echo 8192 ;;
    *) echo 8192 ;;
  esac
}

do_audio() {
  install_units
  local n period
  for n in $(seq 1 "$AUDIO_RETRIES"); do
    period="$(audio_period_for_attempt "$n")"
    log "audio attempt $n/$AUDIO_RETRIES (period=$period)"
    free_alsa
    export SC_JACK_PERIOD="$period"
    if "$INSTALL_DIR/scripts/start_scsynth_alsa.sh" && stack_up; then
      log "audio up: $(pgrep -a jackd | head -1) | $(pgrep -a scsynth | head -1)"
      return 0
    fi
    log "audio attempt $n failed — teardown"
    stop_audio_stack 2>/dev/null || free_alsa
    sleep 2.0
  done
  fail "jackd+scsynth failed after $AUDIO_RETRIES attempts"
}

do_engine() {
  export PI_AMBIENT_ROOT="$INSTALL_DIR"
  export ENGINE_SMOKE_TIMEOUT="$ENGINE_TIMEOUT"
  if stack_up; then
    export PI_SMOKE_NO_AUDIO=1
  else
    unset PI_SMOKE_NO_AUDIO || true
    do_audio
  fi
  log "engine smoke (timeout ${ENGINE_TIMEOUT}s)"
  if ! stack_up; then
    log "WARN: audio stack dropped before smoke — restarting audio"
    unset PI_SMOKE_NO_AUDIO
    do_audio
    export PI_SMOKE_NO_AUDIO=1
  fi
  if ! "$INSTALL_DIR/scripts/engine_smoke_pi.sh"; then
    fail "engine smoke failed"
  fi
  grep -q 'Pi Ambient Synth ENGINE_TEST ok' /tmp/pi-ambient-engine-smoke.log \
    || fail "ENGINE_TEST ok not in smoke log"
}

do_services() {
  log "restart supercollider + pi-ambient-synth (clean teardown first)"
  sudo systemctl stop pi-ambient-synth-deploy.timer 2>/dev/null || true
  sudo systemctl stop pi-ambient-synth.service 2>/dev/null || true
  sudo systemctl stop supercollider.service 2>/dev/null || true
  pkill -x sclang 2>/dev/null || true
  free_alsa
  sleep 2.0
  install_units
  sudo systemctl daemon-reload
  sudo systemctl reset-failed supercollider.service pi-ambient-synth.service 2>/dev/null || true
  rm -f "$MARKER_DIR/sc-engine-ready" 2>/dev/null || true
  sudo systemctl start supercollider.service
  local i
  for i in $(seq 1 60); do
    if [[ -f "$MARKER_DIR/sc-engine-ready" ]] && systemctl is-active --quiet supercollider.service; then
      log "supercollider active + sc-engine-ready"
      break
    fi
    sleep 1
  done
  sudo systemctl start pi-ambient-synth.service 2>/dev/null || true
  sleep 5
  systemctl is-active supercollider.service pi-ambient-synth.service 2>/dev/null | tee -a "$LOG" || true
  sudo systemctl start pi-ambient-synth-deploy.timer 2>/dev/null || true
  if ! systemctl is-active --quiet supercollider.service; then
    fail "supercollider.service not active after restart"
  fi
}

case "$PHASE" in
  all)
    do_sync
    do_audio
    do_engine
    pass
    ;;
  sync|fetch) do_sync; log "sync done" ;;
  audio) do_sync; do_audio; log "audio done" ;;
  engine) do_engine; log "engine done" ;;
  services) do_services; log "services done" ;;
  full)
    do_sync
    do_audio
    do_engine
    do_services
    pass
    ;;
  *)
    echo "usage: pi_verify.sh [all|sync|audio|engine|services|full]" >&2
    exit 2
    ;;
esac
