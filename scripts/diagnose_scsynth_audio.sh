#!/usr/bin/env bash
# Print Pi audio + scsynth driver info (run on the Pi).
set -euo pipefail

echo "==> scsynth"
command -v scsynth || true
scsynth -v 2>&1 | head -3 || true
echo "--- scsynth --help (grep -H/-R/-a) ---"
scsynth --help 2>&1 | grep -E '^-|^  -' | head -40 || true
echo "(Pi SC 3.13 typically has -H and -R only, not -a audio driver)"

echo "==> ALSA"
aplay -l 2>/dev/null || true
echo "--- aplay -L (head) ---"
aplay -L 2>/dev/null | head -20 || true

echo "==> processes"
pgrep -a scsynth || echo "(no scsynth)"
pgrep -a jackd || echo "(no jackd)"

echo "==> logs"
for f in /tmp/scsynth-alsa-start.log /tmp/pi-ambient-engine-smoke.log; do
  if [[ -f "$f" ]]; then
    echo "--- $f (last 20) ---"
    tail -20 "$f"
  fi
done

echo "==> try start"
ROOT="${PI_AMBIENT_ROOT:-/home/pi/pi-ambient-synth}"
if [[ -x "$ROOT/scripts/start_scsynth_alsa.sh" ]]; then
  "$ROOT/scripts/start_scsynth_alsa.sh" && pgrep -a scsynth
fi
