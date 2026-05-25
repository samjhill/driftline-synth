#!/usr/bin/env bash
# Detect PiSugar board model by probing I2C via pisugar-server, then persist in /etc/default.
# Run on the Pi (sudo). Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() { echo "$(date -Iseconds) [pisugar-detect] $*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: run on the Raspberry Pi." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

PREFERRED="${PISUGAR_MODEL:-}"
MODELS=(
  "PiSugar 2 Pro"
  "PiSugar 2 (2-LEDs)"
  "PiSugar 3"
  "PiSugar 2 (4-LEDs)"
)

if [[ -n "$PREFERRED" ]]; then
  MODELS=("$PREFERRED" "${MODELS[@]}")
fi

PY="${ROOT}/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  PY=python3
fi

query_battery() {
  PI_AMBIENT_ROOT="$ROOT" PYTHONPATH="${ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" "$PY" - <<'PY'
import sys
from config_loader import load_config
from pisugar_battery import query_pisugar

data = query_pisugar("get battery", load_config())
bat = data.get("battery")
if isinstance(bat, (int, float)):
    print(int(bat))
    sys.exit(0)
print("fail")
sys.exit(1)
PY
}

set_model() {
  local model="$1"
  local esc="${model//\'/\'\\\'\'}"
  if [[ -f /etc/default/pisugar-server ]]; then
    sed -i "s|--model '[^']*'|--model '${esc}'|" /etc/default/pisugar-server
  fi
  if [[ -f /etc/default/pisugar-poweroff ]]; then
    sed -i "s|--model '[^']*'|--model '${esc}'|" /etc/default/pisugar-poweroff 2>/dev/null || true
  fi
  debconf-set-selections <<EOF 2>/dev/null || true
pisugar-server pisugar-server/model select ${model}
pisugar-poweroff pisugar-poweroff/model select ${model}
EOF
}

restart_server() {
  systemctl restart pisugar-server
  for _ in $(seq 1 15); do
  if [[ -S /tmp/pisugar-server.sock ]]; then
      sleep 1
      return 0
    fi
    sleep 1
  done
  return 1
}

CURRENT=""
if [[ -f /etc/default/pisugar-server ]]; then
  CURRENT="$(sed -n "s/.*--model '\\([^']*\\)'.*/\\1/p" /etc/default/pisugar-server | head -1)"
fi
log "Current model: ${CURRENT:-unknown}"

BEST=""
BEST_BAT=""
for model in "${MODELS[@]}"; do
  [[ "$model" == "$CURRENT" && -n "$BEST" ]] && continue
  log "Trying model: $model"
  set_model "$model"
  if ! restart_server; then
    log "  socket not ready"
    continue
  fi
  if bat="$(query_battery 2>/dev/null)"; then
    log "  battery: ${bat}%"
    BEST="$model"
    BEST_BAT="$bat"
    break
  fi
  log "  no I2C / battery read failed"
done

if [[ -z "$BEST" ]]; then
  log "ERROR: no PiSugar model responded on I2C."
  log "Check: Pi seated on GPIO, I2C enabled (raspi-config), no address conflict."
  exit 1
fi

set_model "$BEST"
restart_server
log "Using model: $BEST (battery ${BEST_BAT}%)"
echo ""
echo "OK: pisugar-server model=$BEST battery=${BEST_BAT}%"
echo "Next: cd ${ROOT} && ./scripts/setup_recovery_pisugar_button.sh"
