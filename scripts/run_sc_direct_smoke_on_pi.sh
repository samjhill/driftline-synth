#!/usr/bin/env bash
# Mac → Pi: Phase 1 direct SuperCollider headphone smoke (requires sudo via .pi-ssh-credentials).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/pi_ssh.sh
source "$ROOT/scripts/lib/pi_ssh.sh"

HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE="${PI_REMOTE_ROOT:-/home/pi/pi-ambient-synth}"

pi_ssh_setup
pi_rsync "$ROOT/synth/sc_direct_smoke.scd" "$HOST:$REMOTE/synth/"
pi_rsync "$ROOT/synth/pi_bind_port.scd" "$HOST:$REMOTE/synth/"
pi_rsync "$ROOT/scripts/sc_direct_headphone_smoke_test.sh" "$HOST:$REMOTE/scripts/"
pi_ssh "$HOST" "chmod +x $REMOTE/scripts/sc_direct_headphone_smoke_test.sh"

echo "==> Phase 1: stop/mask production audio (sudo)"
pi_ssh_sudo "$HOST" "systemctl stop pi-ambient-synth pi-ambient-synth-midi pi-ambient-synth-monitor supercollider 2>/dev/null || true; systemctl mask supercollider pi-ambient-synth pi-ambient-synth-midi 2>/dev/null || true; systemctl kill --kill-who=all supercollider.service 2>/dev/null || true; pkill -9 -x sclang scsynth jackd 2>/dev/null || true; sleep 3"
if pi_ssh "$HOST" "systemctl is-active --quiet supercollider.service"; then
  echo "ERROR: supercollider still active — cannot run smoke test" >&2
  exit 1
fi

echo "==> Phase 1: direct SC headphone smoke"
smoke_rc=0
pi_ssh "$HOST" "INSTALL_DIR=$REMOTE bash $REMOTE/scripts/sc_direct_headphone_smoke_test.sh" || smoke_rc=$?

pi_ssh_sudo "$HOST" "systemctl unmask supercollider pi-ambient-synth pi-ambient-synth-midi 2>/dev/null || true"
echo "==> Production units re-enabled but not started. After you confirm audio, run:"
echo "    INSTALL_DIR=$REMOTE $REMOTE/scripts/restart_synth_services.sh"
exit "$smoke_rc"
