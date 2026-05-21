#!/usr/bin/env bash
# Mac: loop run_pi_e2e until PASS or max attempts (agent-friendly autonomous iteration).
#   ./scripts/run_pi_iterate.sh
#   ./scripts/run_pi_iterate.sh 10
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAX="${1:-8}"

for n in $(seq 1 "$MAX"); do
  echo ""
  echo "########################################"
  echo "# Pi E2E attempt $n / $MAX"
  echo "########################################"
  if "$ROOT/scripts/run_pi_e2e.sh"; then
    echo ""
    echo "==> Iteration succeeded on attempt $n"
    exit 0
  fi
  echo "==> attempt $n failed; waiting 8s..."
  sleep 8
done

echo "==> All $MAX attempts failed"
exit 1
