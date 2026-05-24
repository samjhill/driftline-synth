#!/usr/bin/env bash
# Legacy entry — delegates to pi_ambient_firstboot.sh (systemd canonical).
exec "$(dirname "$0")/pi_ambient_firstboot.sh" "$@"
