#!/usr/bin/env bash
# Deprecated — use ./scripts/run_pi_verify.sh
exec "$(cd "$(dirname "$0")" && pwd)/run_pi_verify.sh" "${@:-all}"
