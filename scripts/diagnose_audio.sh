#!/usr/bin/env bash
# Audio troubleshooting on the Pi — run via SSH.
set -euo pipefail

ROOT="${ROOT:-/home/pi/pi-ambient-synth}"
PY="${ROOT}/.venv/bin/python"

echo "=== SuperCollider ==="
systemctl is-active supercollider.service 2>/dev/null || echo "inactive"
systemctl cat supercollider.service 2>/dev/null | grep -E 'ExecStart|SC_' || true
echo "--- journal (last 20 lines) ---"
sudo journalctl -u supercollider -n 20 --no-pager 2>/dev/null || journalctl -u supercollider -n 20 --no-pager 2>/dev/null || true

echo ""
echo "=== Synth controller ==="
systemctl is-active pi-ambient-synth.service 2>/dev/null || echo "inactive"

echo ""
echo "=== ALSA devices ==="
aplay -l 2>/dev/null || echo "aplay not available"
echo "--- amixer PCM / Headphone ---"
amixer -c 0 sget PCM 2>/dev/null | tail -5 || true
amixer -c 0 sget Headphone 2>/dev/null | tail -5 || true

echo ""
echo "=== jackd2 (should be inactive) ==="
systemctl is-active jackd2 2>/dev/null || echo "inactive"

echo ""
echo "=== OSC test note (needs supercollider active) ==="
if [[ -x "$PY" && -f "$ROOT/scripts/test_osc.py" ]]; then
  "$PY" "$ROOT/scripts/test_osc.py" || echo "test_osc failed"
else
  echo "Skip: venv or test_osc.py missing"
fi

echo ""
echo "KeyStep: play notes ABOVE G3 (MIDI note 55+) for melody; lower keys only move the drone."
echo "Idle drone should be audible when SC is running — run: bash $ROOT/scripts/setup_pi_audio.sh"
