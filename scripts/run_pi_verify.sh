#!/usr/bin/env bash
# Mac/Linux: push this repo to the Pi and run pi_verify (one command, clear PASS/FAIL).
#   ./scripts/run_pi_verify.sh
#   ./scripts/run_pi_verify.sh --save-password   # store Pi password (gitignored file)
#   PI_HOST=pi@192.168.1.64 ./scripts/run_pi_verify.sh
#   ./scripts/run_pi_verify.sh --full            # also restart systemd on Pi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/pi_ssh.sh
source "$ROOT/scripts/lib/pi_ssh.sh"

HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE="${PI_REMOTE_ROOT:-/home/pi/pi-ambient-synth}"
PHASE="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --save-password) pi_ssh_save_password; exit 0 ;;
    --full) PHASE=full ;;
    -h|--help)
      echo "usage: $0 [--save-password] [--full|all|sync|audio|engine|services]"
      exit 0
      ;;
    *) PHASE="$1" ;;
  esac
  shift
done

REF="${GITHUB_REF:-$(git -C "$ROOT" rev-parse HEAD)}"
export PI_HOST="$HOST"
pi_ssh_setup

try_host() {
  pi_ssh_try_batch "$1"
}

if ! try_host "$HOST"; then
  for alt in pi@192.168.1.64 pi@raspberrypi.local; do
    [[ "$alt" == "$HOST" ]] && continue
    if try_host "$alt"; then
      HOST="$alt"
      export PI_HOST="$HOST"
      break
    fi
  done
fi

if [[ "${PI_SSH_HAS_SAVED_PASS:-0}" == "1" ]]; then
  echo "==> host: $HOST  ref: ${REF:0:7}  phase: $PHASE  (saved password)"
else
  echo "==> host: $HOST  ref: ${REF:0:7}  phase: $PHASE"
  echo "    tip: $0 --save-password  (one prompt next time; needs: brew install hudochenkov/sshpass/sshpass)"
fi

echo "==> rsync scripts + synth -> $REMOTE"
pi_rsync "$ROOT/scripts/pi_verify.sh" "$ROOT/scripts/start_scsynth_alsa.sh" \
  "$ROOT/scripts/run_sclang_engine.sh" "$ROOT/scripts/engine_smoke_pi.sh" \
  "$ROOT/scripts/diagnose_scsynth_audio.sh" "$HOST:$REMOTE/scripts/"
pi_rsync "$ROOT/synth/pi_bind_port.scd" "$ROOT/synth/ambient_engine.scd" "$HOST:$REMOTE/synth/"
pi_rsync "$ROOT/systemd/supercollider.service" "$ROOT/systemd/pi-ambient-synth.service" "$HOST:$REMOTE/systemd/"

pi_ssh "$HOST" "chmod +x $REMOTE/scripts/*.sh"

echo "==> remote verify"
set +e
pi_ssh "$HOST" "export PI_SKIP_FETCH=1 PI_AMBIENT_ROOT=$REMOTE GITHUB_REF=$REF; $REMOTE/scripts/pi_verify.sh $PHASE"
st=$?
set -e

pi_ssh "$HOST" "cat ${PI_VERIFY_RESULT:-/var/lib/pi-ambient-synth/verify-last.txt} 2>/dev/null || true"

if [[ "$st" -eq 0 ]]; then
  echo "==> PASS"
  exit 0
fi
echo "==> FAIL (exit $st) — fetching Pi logs ..."
pi_ssh "$HOST" "tail -35 /tmp/scsynth-alsa-start.log /tmp/pi-ambient-engine-smoke.log 2>/dev/null; $REMOTE/scripts/diagnose_scsynth_audio.sh 2>/dev/null | tail -25" || true
exit "$st"
