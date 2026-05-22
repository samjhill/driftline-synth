#!/usr/bin/env bash
# Step 1: prove Pi 3.5 mm jack with direct ALSA (no JACK, no SuperCollider).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
# shellcheck source=scripts/lib/audio_isolation.sh
source "$INSTALL_DIR/scripts/lib/audio_isolation.sh"

log() { echo "$(date -Iseconds) [alsa-headphone] $*"; }

log "stop project services"
audio_iso_stop_project_services || exit 1

log "kill jackd / scsynth / sclang"
audio_iso_kill_audio_processes

log "force headphone output + mixer"
audio_iso_force_headphone_mixer

run_speaker_test() {
  local dev="$1"
  log "speaker-test device=$dev (440 Hz sine, ~5 s)"
  if ! command -v speaker-test >/dev/null 2>&1; then
    log "ERROR: speaker-test not installed (alsa-utils)"
    return 1
  fi
  timeout 12 speaker-test -D "$dev" -c 2 -t sine -f 440 -l 1 2>&1 || true
}

PRIMARY_DEV="${ALSA_TEST_DEVICE:-plughw:0,0}"
log "primary ALSA test: $PRIMARY_DEV"
run_speaker_test "$PRIMARY_DEV"

for extra in hw:0,0 default; do
  if [[ "$extra" != "$PRIMARY_DEV" ]]; then
    log "optional ALSA test: $extra"
    run_speaker_test "$extra" || true
  fi
done

echo ""
echo "ALSA_HEADPHONE_TEST_DONE_USER_MUST_CONFIRM"
echo "Listen on the Pi 3.5 mm headphone jack."
echo "  Heard 440 Hz tone from speaker-test?"
echo "  Silence?"
echo ""
echo "Reply: heard / silence"
echo ""
echo "If silence: STOP — fix Pi routing, cable, headphones, or card 0 mixer before JACK or SuperCollider."
echo "If heard: run scripts/audio_device_report.sh then scripts/jack_headphone_smoke_test.sh"
