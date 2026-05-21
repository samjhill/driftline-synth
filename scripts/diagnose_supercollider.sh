#!/usr/bin/env bash
# SuperCollider + OSC diagnostics on the Pi.
set -euo pipefail

ROOT="${ROOT:-/home/pi/pi-ambient-synth}"
SCD="${ROOT}/synth/ambient_engine.scd"

echo "=== supercollider.service ==="
systemctl is-active supercollider.service 2>/dev/null || echo "inactive"
systemctl show supercollider.service -p ActiveState -p SubState -p MainPID --value 2>/dev/null | paste - - - || true

echo ""
echo "=== processes (need BOTH sclang and scsynth) ==="
pgrep -a sclang 2>/dev/null || echo "no sclang"
pgrep -a scsynth 2>/dev/null || echo "no scsynth"

echo ""
echo "=== engine file on disk ==="
if [[ -f "$SCD" ]]; then
  grep -E 'engine script loading|listening on OSC' "$SCD" | head -2 || true
else
  echo "MISSING: $SCD"
fi

echo ""
echo "=== journal markers (last 200 lines) ==="
sudo journalctl -u supercollider -n 200 --no-pager 2>/dev/null \
  | grep -E 'engine script loading|Booting|scsynth running|Engine synths|listening on OSC|test_beep|playNote|ERROR|syntax error|WARN:' \
  || echo "(no markers — show raw tail below)"

echo ""
echo "=== journal tail (raw) ==="
sudo journalctl -u supercollider -n 25 --no-pager 2>/dev/null || true

echo ""
echo "=== OSC smoke (sends test_beep + note) ==="
if [[ -x "${ROOT}/.venv/bin/python" && -f "${ROOT}/scripts/test_osc.py" ]]; then
  "${ROOT}/.venv/bin/python" "${ROOT}/scripts/test_osc.py" || true
  echo "--- after test_osc, journal should show pi_test_beep ---"
  sleep 1
  sudo journalctl -u supercollider -n 30 --no-pager 2>/dev/null \
    | grep -E 'test_beep|playNote|listening|ERROR' || echo "(still no OSC markers in journal)"
else
  echo "Skip: venv or test_osc.py missing"
fi
