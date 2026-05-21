#!/usr/bin/env bash
# Mac: push repo + run full Pi E2E (audio verify + MIDI/reseed checks). Exit 0 = ~95% confident.
#   ./scripts/run_pi_e2e.sh
#   ./scripts/run_pi_iterate.sh 6   # retry until pass
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/pi_ssh.sh
source "$ROOT/scripts/lib/pi_ssh.sh"

HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE="${PI_REMOTE_ROOT:-/home/pi/pi-ambient-synth}"
REF="${GITHUB_REF:-$(git -C "$ROOT" rev-parse HEAD)}"

export PI_HOST="$HOST"
pi_ssh_setup

echo "==> host: $HOST  ref: ${REF:0:7}  (e2e)"
echo "==> rsync → $REMOTE"
mkdir -p "$ROOT/scripts/lib"
pi_rsync "$ROOT/scripts/pi_verify.sh" "$ROOT/scripts/pi_e2e_verify.sh" \
  "$ROOT/scripts/validate_ambient_engine.py" "$ROOT/scripts/validate_ambient_engine.sh" \
  "$ROOT/scripts/assert_monitor_status.py" \
  "$ROOT/scripts/simulate_midi_e2e.py" "$ROOT/scripts/test_osc.py" \
  "$ROOT/scripts/ensure_jack_playback.sh" "$ROOT/scripts/verify_audible_pi.sh" \
  "$ROOT/scripts/play_headphone_test.py" \
  "$ROOT/scripts/start_scsynth_alsa.sh" "$ROOT/scripts/run_sclang_engine.sh" \
  "$ROOT/scripts/engine_smoke_pi.sh"   "$ROOT/scripts/restart_synth_services.sh" "$ROOT/scripts/recover_pi_audio.sh" \
  "$ROOT/scripts/pi_midi_bridge.py" \
  "$HOST:$REMOTE/scripts/"
pi_rsync "$ROOT/scripts/lib/audio_stack.sh" "$HOST:$REMOTE/scripts/lib/"
pi_rsync "$ROOT/synth/pi_bind_port.scd" "$ROOT/synth/ambient_engine.scd" "$HOST:$REMOTE/synth/"
pi_rsync "$ROOT/systemd/supercollider.service" "$ROOT/systemd/pi-ambient-synth.service" \
  "$ROOT/systemd/pi-ambient-synth-midi.service" "$HOST:$REMOTE/systemd/"
pi_rsync "$ROOT/src/" "$HOST:$REMOTE/src/"
pi_rsync "$ROOT/config/default.yaml" "$HOST:$REMOTE/config/"

pi_ssh "$HOST" "chmod +x $REMOTE/scripts/*.sh; mkdir -p $REMOTE/state $REMOTE/config"

echo "==> validate ambient_engine.scd (static, Mac)"
python3 "$ROOT/scripts/validate_ambient_engine.py" "$ROOT/synth/ambient_engine.scd"

echo "==> pi_verify (audio + engine)"
set +e
pi_ssh "$HOST" "export PI_SKIP_FETCH=1 PI_AMBIENT_ROOT=$REMOTE; $REMOTE/scripts/pi_verify.sh all"
vst=$?
set -e
[[ "$vst" -eq 0 ]] || { echo "==> audio verify failed; aborting e2e"; exit "$vst"; }

echo "==> restart production services"
pi_ssh "$HOST" "export INSTALL_DIR=$REMOTE; $REMOTE/scripts/restart_synth_services.sh"

echo "==> settle production services (post-restart)"
pi_ssh "$HOST" "sleep 5; sudo systemctl reset-failed pi-ambient-synth.service pi-ambient-synth-midi.service 2>/dev/null || true"

echo "==> pi_e2e_verify (OSC + MIDI reseed + note)"
set +e
pi_ssh "$HOST" "echo '${REF}' > /var/lib/pi-ambient-synth/e2e-rsync-sha; echo '${REF:0:12}' | sudo tee /var/lib/pi-ambient-synth/last_deploy_sha >/dev/null"
pi_ssh "$HOST" "export PI_AMBIENT_ROOT=$REMOTE INSTALL_DIR=$REMOTE; $REMOTE/scripts/pi_e2e_verify.sh"
est=$?
set -e

pi_ssh "$HOST" "cat /var/lib/pi-ambient-synth/e2e-last.txt 2>/dev/null || true"

LOCAL_STATUS="${PI_E2E_LOCAL_STATUS:-$ROOT/.pi-e2e-status.json}"
LOCAL_PAGE="${PI_E2E_LOCAL_PAGE:-$ROOT/.pi-e2e-status-page.txt}"
pi_ssh "$HOST" "cat /var/lib/pi-ambient-synth/e2e-status-snapshot.json 2>/dev/null" >"$LOCAL_STATUS" || true
pi_ssh "$HOST" "cat /var/lib/pi-ambient-synth/e2e-status-page.txt 2>/dev/null" >"$LOCAL_PAGE" || true

PI_IP="$(pi_ssh "$HOST" "python3 -c \"
import json
from pathlib import Path
p = Path('/var/lib/pi-ambient-synth/network.json')
if p.is_file():
    print(json.loads(p.read_text()).get('primary_ip', ''), end='')
\" 2>/dev/null" || true)"
if [[ -z "${PI_IP// }" ]]; then
  PI_IP="$(pi_ssh "$HOST" "hostname -I 2>/dev/null | awk '{print \$1}'" || true)"
fi
if [[ -n "${PI_IP// }" ]]; then
  LOCAL_API="${PI_E2E_LOCAL_API:-$ROOT/.pi-e2e-api-status.json}"
  if curl -sf --max-time 8 "http://${PI_IP}:8080/api/status" -o "$LOCAL_API" 2>/dev/null; then
    echo "==> monitor /api/status → $LOCAL_API"
  fi
fi

echo "==> status page snapshot → $LOCAL_PAGE"
[[ -f "$LOCAL_PAGE" ]] && cat "$LOCAL_PAGE" || true

if [[ "$est" -eq 0 ]]; then
  echo "==> E2E PASS"
  exit 0
fi
echo "==> E2E FAIL — status page + journals:"
[[ -f "$LOCAL_PAGE" ]] && cat "$LOCAL_PAGE" || pi_ssh "$HOST" "cat /var/lib/pi-ambient-synth/e2e-status-page.txt 2>/dev/null" || true
pi_ssh "$HOST" "journalctl -u supercollider -n 20 --no-pager; journalctl -u pi-ambient-synth -n 15 --no-pager" || true
exit "$est"
