#!/usr/bin/env bash
# Query pisugar-server once (closes socket cleanly; nc -U often hangs).
set -euo pipefail

CMD="${*:-get battery}"
SOCK="${PISUGAR_SOCK:-/tmp/pisugar-server.sock}"
TIMEOUT="${PISUGAR_QUERY_TIMEOUT:-2.0}"

python3 - "$CMD" "$SOCK" "$TIMEOUT" <<'PY'
import socket
import sys

cmd, sock_path, timeout_s = sys.argv[1:4]
timeout = float(timeout_s)
payload = (cmd.strip() + "\n").encode()
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
    sock.settimeout(timeout)
    sock.connect(sock_path)
    sock.sendall(payload)
    sock.shutdown(socket.SHUT_WR)
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        sys.stdout.write(chunk.decode(errors="replace"))
PY
