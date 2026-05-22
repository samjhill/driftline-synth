#!/usr/bin/env bash
# Phase 2: send /pi_synth/proof_note — user must confirm audible pad on headphone jack.
# Does not stop production services (non-destructive).
set -euo pipefail

ROOT="${INSTALL_DIR:-/home/pi/pi-ambient-synth}"
export INSTALL_DIR="$ROOT"

if ! systemctl is-active supercollider.service &>/dev/null; then
  echo "ERROR: supercollider.service not active — start stack first" >&2
  exit 1
fi

"$ROOT/.venv/bin/python" "$ROOT/scripts/send_real_synth_proof.py" proof_note

echo ""
echo "MINIMAL_PROOF_NOTE_HEARD_QUESTION"
echo "Listen on the Pi 3.5 mm jack."
echo "  Heard warm pad chord (~2.5 s)?"
echo "  Silence?"
echo "Reply: pad / silence"
echo "Do not enable KeyStep MIDI until pad is confirmed."
