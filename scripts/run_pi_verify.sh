#!/usr/bin/env bash
# Mac/Linux: push this repo to the Pi and run pi_verify (one command, clear PASS/FAIL).
#   ./scripts/run_pi_verify.sh
#   PI_HOST=pi@192.168.1.64 ./scripts/run_pi_verify.sh
#   ./scripts/run_pi_verify.sh --full   # also restart systemd services on Pi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE="${PI_REMOTE_ROOT:-/home/pi/pi-ambient-synth}"
case "${1:-all}" in
  --full) PHASE=full ;;
  *) PHASE="${1:-all}" ;;
esac
REF="${GITHUB_REF:-$(git -C "$ROOT" rev-parse HEAD)}"

try_host() {
  local h="$1"
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" 'echo ok' 2>/dev/null
}

if ! try_host "$HOST"; then
  for alt in pi@192.168.1.64 pi@raspberrypi.local; do
    [[ "$alt" == "$HOST" ]] && continue
    if try_host "$alt"; then
      HOST="$alt"
      break
    fi
  done
fi

echo "==> host: $HOST  ref: ${REF:0:7}  phase: $PHASE"
echo "==> rsync scripts + synth -> $REMOTE"
rsync -az "$ROOT/scripts/pi_verify.sh" "$ROOT/scripts/start_scsynth_alsa.sh" \
  "$ROOT/scripts/run_sclang_engine.sh" "$ROOT/scripts/engine_smoke_pi.sh" \
  "$ROOT/scripts/diagnose_scsynth_audio.sh" "$HOST:$REMOTE/scripts/"
rsync -az "$ROOT/synth/ambient_engine.scd" "$HOST:$REMOTE/synth/"
rsync -az "$ROOT/systemd/supercollider.service" "$HOST:$REMOTE/systemd/"

ssh "$HOST" "chmod +x $REMOTE/scripts/*.sh"

echo "==> remote verify"
set +e
ssh "$HOST" "export PI_SKIP_FETCH=1 PI_AMBIENT_ROOT=$REMOTE GITHUB_REF=$REF; $REMOTE/scripts/pi_verify.sh $PHASE"
st=$?
set -e

ssh "$HOST" "cat ${PI_VERIFY_RESULT:-/var/lib/pi-ambient-synth/verify-last.txt} 2>/dev/null || true"

if [[ "$st" -eq 0 ]]; then
  echo "==> PASS"
  exit 0
fi
echo "==> FAIL (exit $st) — logs on Pi:"
echo "    ssh $HOST tail -30 /tmp/scsynth-alsa-start.log /tmp/pi-ambient-engine-smoke.log"
exit "$st"
