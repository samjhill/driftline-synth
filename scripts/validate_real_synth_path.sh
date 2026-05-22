#!/usr/bin/env bash
# Prove the real SuperCollider → JACK → headphone path (no ALSA blips / speaker-test).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
MARKER_DIR="${MARKER_DIR:-/var/lib/pi-ambient-synth}"
PY="${ROOT}/.venv/bin/python"
FAIL_LAYER=""

fail() {
  FAIL_LAYER="$1"
  echo "VALIDATE_FAIL: $FAIL_LAYER"
  echo "$2" >&2
  exit 1
}

log() { echo "$(date -Iseconds) [validate-real-synth] $*"; }

log "=== Real synth path validation (ALSA fallback must be OFF) ==="

if pgrep -x flues-synth >/dev/null 2>&1; then
  fail "flues_running" "flues-synth is running — stop and disable it"
fi

if aconnect -l 2>/dev/null | grep -qiE 'Flues.*Connected From.*KeyStep|KeyStep.*Connecting To:.*Flues'; then
  fail "flues_midi_wired" "KeyStep is still connected to Flues via aconnect"
fi

systemctl is-active --quiet supercollider.service \
  || fail "supercollider_inactive" "supercollider.service not active"

systemctl is-active --quiet pi-ambient-synth-midi.service \
  || fail "midi_bridge_inactive" "pi-ambient-synth-midi.service not active"

pgrep -x jackd >/dev/null || fail "jackd_missing" "jackd not running"
pgrep -x scsynth >/dev/null || fail "scsynth_missing" "scsynth not running"

midi_env="$(systemctl show pi-ambient-synth-midi.service -p Environment --value 2>/dev/null || true)"
if echo "$midi_env" | grep -qE 'PI_ALSA_KEY_TONE=(1|true|yes)'; then
  fail "alsa_fallback_enabled" "PI_ALSA_KEY_TONE must be 0 for real synth validation"
fi

if ! echo "$midi_env" | grep -q 'KeyStep\|keystep\|Arturia'; then
  log "WARN: KeyStep name not in midi-status (check USB)"
fi
if [[ -f "$MARKER_DIR/midi-status.json" ]]; then
  grep -q '"listening": true' "$MARKER_DIR/midi-status.json" 2>/dev/null \
    || fail "midi_not_listening" "midi bridge not listening (midi-status.json)"
fi

[[ -f "$MARKER_DIR/sc-engine-ready" ]] \
  || fail "sc_engine_not_ready" "sc-engine-ready marker missing (engine not booted)"

[[ -x "$ROOT/scripts/ensure_jack_playback.sh" ]] \
  || fail "ensure_jack_missing" "ensure_jack_playback.sh not found"

JACK_CONNECT_RETRY_SEC=12 "$ROOT/scripts/ensure_jack_playback.sh" \
  || fail "jack_playback_unlinked" "SuperCollider:out not linked to system:playback"

[[ -f "$MARKER_DIR/jack-playback-linked" ]] \
  || fail "jack_marker_missing" "jack-playback-linked not written after ensure"

log "JACK connections:"
jack_lsp -c 2>/dev/null | grep -E 'SuperCollider|playback' | head -14 || true

[[ -x "$PY" ]] || fail "venv_missing" "$PY not found"

log "OSC proof_note (2s ambient chord, piAmbientVoice only — listen on Pi headphones)"
"$PY" "$ROOT/scripts/send_real_synth_proof.py" proof_note --wait 2.2

sleep 0.5
j1="$(journalctl -u supercollider -n 30 --no-pager --since "30 sec ago" 2>/dev/null || true)"
echo "$j1" | grep -q 'proof_note' \
  || fail "proof_note_not_logged" "journal missing proof_note (SC did not receive OSC)"

log "OSC proof_patch_a (dark warm pad — listen)"
"$PY" "$ROOT/scripts/send_real_synth_proof.py" proof_patch_a --wait 2.5

log "OSC proof_patch_b (bright plucky pad — must sound different)"
"$PY" "$ROOT/scripts/send_real_synth_proof.py" proof_patch_b --wait 2.5

log "OSC single note (same path as KeyStep)"
"$PY" "$ROOT/scripts/send_real_synth_proof.py" note_on --note 64 --velocity 110
sleep 1.2
"$PY" "$ROOT/scripts/send_real_synth_proof.py" note_off --note 64

echo ""
echo "AUDIBLE_CHECK (human on Pi 3.5mm jack):"
echo "  - You should hear SuperCollider ambient PAD (piAmbientVoice), not ALSA blips."
echo "  - proof_patch_a vs proof_patch_b must be obviously different timbres."
echo "  - If silent: JACK link or bus routing still broken (logs above are not audible success)."
echo ""
echo "REAL_SYNTH_PATH_READY"
