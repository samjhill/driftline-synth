#!/usr/bin/env bash
# Step 3: prove JACK → ALSA → headphone jack (no SuperCollider, no sclang).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
# shellcheck source=scripts/lib/audio_isolation.sh
source "$INSTALL_DIR/scripts/lib/audio_isolation.sh"

JACK_ALSA_DEV="${JACK_ALSA_DEV:-plughw:0,0}"
JACK_RATE="${JACK_RATE:-48000}"
JACK_PERIOD="${JACK_PERIOD:-4096}"
JACK_NPERIODS="${JACK_NPERIODS:-3}"
PLAY_SEC="${JACK_SMOKE_PLAY_SEC:-8}"
LOG="/tmp/jack-headphone-smoke.log"
MARKER="$(audio_iso_marker_dir)/jack-known-good.env"

log() { echo "$(date -Iseconds) [jack-headphone] $*"; }

log "stop project services"
audio_iso_stop_project_services || exit 1
audio_iso_kill_audio_processes
audio_iso_force_headphone_mixer

: >"$LOG"
log "start jackd alsa dev=$JACK_ALSA_DEV rate=$JACK_RATE period=$JACK_PERIOD"
nohup jackd -dalsa -d"$JACK_ALSA_DEV" -r"$JACK_RATE" -p"$JACK_PERIOD" -n"$JACK_NPERIODS" -i0 -o2 >>"$LOG" 2>&1 &
JACK_PID=$!
for _ in $(seq 1 40); do
  pgrep -x jackd >/dev/null && break
  sleep 0.25
done
pgrep -x jackd >/dev/null || { log "FAIL: jackd did not start"; tail -30 "$LOG"; exit 1; }
sleep 2

jack_connect_playback() {
  local src="$1"
  [[ -n "$src" ]] || return 1
  jack_connect "$src" system:playback_1 2>/dev/null || true
  jack_connect "$src" system:playback_2 2>/dev/null || true
}

signal_started=0
cleanup() {
  pkill -x jack_metro 2>/dev/null || true
  kill "$JACK_PID" 2>/dev/null || true
  pkill -x jackd 2>/dev/null || true
}
trap cleanup EXIT

try_jack_metro() {
  command -v jack_metro >/dev/null 2>&1 || return 1
  log "signal: jack_metro (~${PLAY_SEC}s)"
  jack_metro -b 120 >>"$LOG" 2>&1 &
  sleep 1
  local port
  port="$(jack_lsp 2>/dev/null | grep -E '^metro:' | head -1 || true)"
  if [[ -z "$port" ]]; then
    port="$(jack_lsp 2>/dev/null | grep -i metro | head -1 || true)"
  fi
  if [[ -n "$port" ]]; then
    jack_connect_playback "$port"
    signal_started=1
    sleep "$PLAY_SEC"
    return 0
  fi
  log "WARN: jack_metro running but no metro port found"
  return 1
}

try_jack_play_wav() {
  local wav="/tmp/jack-headphone-smoke.wav"
  command -v sox >/dev/null 2>&1 || return 1
  sox -n -r "$JACK_RATE" -c 2 "$wav" synth 2 sine 440 fade 0.05 0 repeat 3 2>/dev/null || return 1
  if command -v jack-play >/dev/null 2>&1; then
    log "signal: jack-play $wav"
    timeout "$((PLAY_SEC + 4))" jack-play "$wav" >>"$LOG" 2>&1 &
    sleep 1
    local port
    port="$(jack_lsp 2>/dev/null | grep -E 'jack-play|playback' | grep -v system | head -1 || true)"
    [[ -n "$port" ]] && jack_connect_playback "$port"
    signal_started=1
    sleep "$PLAY_SEC"
    return 0
  fi
  if command -v jack_play >/dev/null 2>&1; then
    log "signal: jack_play $wav"
    timeout "$((PLAY_SEC + 4))" jack_play "$wav" >>"$LOG" 2>&1 &
    sleep 1
    signal_started=1
    sleep "$PLAY_SEC"
    return 0
  fi
  return 1
}

try_sox_jack() {
  command -v play >/dev/null 2>&1 || return 1
  if play --help 2>&1 | grep -qi jack; then
    log "signal: sox play → JACK (~${PLAY_SEC}s)"
    timeout "$((PLAY_SEC + 4))" play -n -t jack synth sine 440 fade 0 0 "$PLAY_SEC" >>"$LOG" 2>&1 &
    sleep 1
    local port
    port="$(jack_lsp 2>/dev/null | grep -v system | grep -E 'out|play' | head -1 || true)"
    [[ -n "$port" ]] && jack_connect_playback "$port"
    signal_started=1
    sleep "$PLAY_SEC"
    return 0
  fi
  return 1
}

if ! try_jack_metro; then
  if ! try_jack_play_wav; then
    if ! try_sox_jack; then
      log "ERROR: no JACK signal tool (install: sudo apt-get install -y jack-tools sox)"
      echo "  sudo apt-get install -y jack-tools sox libsox-fmt-all" >&2
      exit 1
    fi
  fi
fi

if [[ "$signal_started" != "1" ]]; then
  log "ERROR: could not start a JACK audio source"
  exit 1
fi

mkdir -p "$(dirname "$MARKER")"
{
  echo "JACK_ALSA_DEV=$JACK_ALSA_DEV"
  echo "JACK_RATE=$JACK_RATE"
  echo "JACK_PERIOD=$JACK_PERIOD"
  echo "JACK_NPERIODS=$JACK_NPERIODS"
  echo "JACK_SMOKE_TS=$(date -Iseconds)"
} | sudo tee "$MARKER" >/dev/null 2>&1 || {
  mkdir -p "$(dirname "$MARKER")" 2>/dev/null || true
  {
    echo "JACK_ALSA_DEV=$JACK_ALSA_DEV"
    echo "JACK_RATE=$JACK_RATE"
    echo "JACK_PERIOD=$JACK_PERIOD"
    echo "JACK_NPERIODS=$JACK_NPERIODS"
    echo "JACK_SMOKE_TS=$(date -Iseconds)"
  } >"$MARKER"
}

log "jack graph:"
jack_lsp -c 2>/dev/null | head -30 || true

echo ""
echo "JACK_HEADPHONE_TEST_DONE_USER_MUST_CONFIRM"
echo "Listen on the Pi 3.5 mm headphone jack."
echo "  Heard clicks/metro or tone via JACK (~${PLAY_SEC} s)?"
echo "  Silence?"
echo ""
echo "Reply: heard / silence"
echo "Settings saved: $MARKER"
echo "Log: $LOG"
echo ""
echo "If heard: run scripts/sc_jack_known_good_test.sh (SuperCollider, same JACK device)."
echo "If silence: do NOT run SuperCollider — fix JACK routing or ALSA device first."
