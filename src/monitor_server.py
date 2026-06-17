"""Lightweight LAN status page for Pi Ambient Synth (stdlib HTTP)."""

from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from config_loader import load_config
from logging_setup import setup_logging
from network_info import network_snapshot
from patch_model import Patch
from state_store import StateStore

logger = logging.getLogger(__name__)

DEPLOY_LOG = Path("/var/log/pi-ambient-synth-deploy.log")
DEPLOY_SHA_FILE = Path("/home/pi/pi-ambient-synth/.deploy_sha")
NETWORK_FILE = Path("/var/lib/pi-ambient-synth/network.json")


def _service_state(unit: str) -> str:
    try:
        out = subprocess.run(
            ["systemctl", "is-active", unit],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return (out.stdout or out.stderr or "unknown").strip()
    except (subprocess.SubprocessError, FileNotFoundError):
        return "n/a"


def _tail_file(path: Path, lines: int = 40) -> list[str]:
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        return text.splitlines()[-lines:]
    except OSError:
        return []


def collect_status(config: dict[str, Any]) -> dict[str, Any]:
    app = config.get("app", {})
    monitor = config.get("monitor", {})
    port = int(monitor.get("port", 8080))

    store = StateStore(
        Path(app.get("state_path", "./state/current_patch.json")),
        Path(app.get("favorites_path", "./state/favorites.json")),
    )
    patch = store.load_current()
    patch_data = patch.to_dict() if patch else None

    network = network_snapshot(monitor_port=port)
    if NETWORK_FILE.is_file():
        try:
            cached = json.loads(NETWORK_FILE.read_text(encoding="utf-8"))
            if cached.get("primary_ip"):
                network = {**network, **cached}
        except (json.JSONDecodeError, OSError):
            pass

    deploy_sha = ""
    if DEPLOY_SHA_FILE.is_file():
        deploy_sha = DEPLOY_SHA_FILE.read_text(encoding="utf-8").strip()[:12]

    return {
        "app": app.get("name", "Pi Ambient Synth"),
        "uptime_seconds": int(time.time() - ps_boot_time()) if ps_boot_time() else None,
        "network": network,
        "services": {
            "supercollider": _service_state("supercollider.service"),
            "synth": _service_state("pi-ambient-synth.service"),
            "monitor": _service_state("pi-ambient-synth-monitor.service"),
            "deploy_timer": _service_state("pi-ambient-synth-deploy.timer"),
        },
        "patch": patch_data,
        "patch_summary": patch.summary() if patch else None,
        "deploy_sha": deploy_sha,
        "deploy_log_tail": _tail_file(DEPLOY_LOG),
    }


def ps_boot_time() -> float | None:
    try:
        with open("/proc/stat") as f:
            for line in f:
                if line.startswith("btime "):
                    return float(line.split()[1])
    except OSError:
        return None
    return None


def _html_page(status: dict[str, Any]) -> str:
    net = status.get("network") or {}
    ip = net.get("primary_ip") or "—"
    host = net.get("hostname") or "pi"
    mdns = net.get("mdns") or f"{host}.local"
    monitor_url = net.get("monitor_url") or "#"
    all_ips = ", ".join(net.get("all_ips") or []) or ip
    svc = status.get("services") or {}
    patch_sum = status.get("patch_summary") or "No patch loaded"
    sha = status.get("deploy_sha") or "—"
    log_lines = status.get("deploy_log_tail") or []
    log_html = "".join(
        f"<div class='log'>{_escape(line)}</div>" for line in log_lines[-25:]
    ) or "<div class='log muted'>No deploy log yet.</div>"

    def row(label: str, value: str, ok: bool | None = None) -> str:
        td_class = "ok" if ok is True else ("bad" if ok is False else "")
        attr = f' class="{td_class}"' if td_class else ""
        return f"<tr><th>{_escape(label)}</th><td{attr}>{_escape(value)}</td></tr>"

    svc_rows = "".join(
        row(
            name,
            state,
            ok=state == "active",
        )
        for name, state in svc.items()
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="5">
  <title>{_escape(status.get("app", "Pi Ambient Synth"))} — Monitor</title>
  <style>
    :root {{ font-family: system-ui, sans-serif; background: #0f1419; color: #e7ecef; }}
    body {{ margin: 1.5rem; max-width: 52rem; }}
    h1 {{ font-size: 1.35rem; font-weight: 600; }}
    .ip {{ font-size: 1.75rem; letter-spacing: 0.02em; margin: 0.5rem 0 1rem; }}
    a {{ color: #7ec8e3; }}
    table {{ border-collapse: collapse; width: 100%; margin: 1rem 0; }}
    th, td {{ text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid #2a3540; }}
    th {{ color: #9ab; width: 11rem; font-weight: 500; }}
    .ok {{ color: #6ddb8a; }}
    .bad {{ color: #f08080; }}
    .log {{ font-family: ui-monospace, monospace; font-size: 0.78rem; color: #aab; }}
    .muted {{ color: #667; }}
    section {{ margin-top: 1.5rem; }}
  </style>
</head>
<body>
  <h1>{_escape(status.get("app", "Pi Ambient Synth"))}</h1>
  <p class="ip">{_escape(ip)}</p>
  <p><a href="{_escape(monitor_url)}">{_escape(monitor_url)}</a> · {_escape(mdns)} · {_escape(all_ips)}</p>
  <table>
    {row("Hostname", host)}
    {row("SSH", f"ssh pi@{mdns}")}
    {row("Current patch", patch_sum)}
    {row("Deploy SHA", sha)}
    {svc_rows}
  </table>
  <section>
    <h2>Deploy log</h2>
    {log_html}
  </section>
  <p class="muted">Auto-refreshes every 5s · LAN only (no auth)</p>
</body>
</html>"""


def _escape(text: str) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


class MonitorHandler(BaseHTTPRequestHandler):
    config: dict[str, Any]

    def log_message(self, fmt: str, *args: Any) -> None:
        logger.debug("HTTP " + fmt, *args)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            status = collect_status(self.config)
            body = _html_page(status).encode("utf-8")
            self._send(200, "text/html; charset=utf-8", body)
        elif path == "/api/status":
            status = collect_status(self.config)
            body = json.dumps(status, indent=2).encode("utf-8")
            self._send(200, "application/json", body)
        elif path == "/health":
            self._send(200, "text/plain", b"ok\n")
        else:
            self._send(404, "text/plain", b"not found\n")

    def _send(self, code: int, content_type: str, body: bytes) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve(config: dict[str, Any]) -> None:
    monitor = config.get("monitor", {})
    if not monitor.get("enabled", True):
        logger.info("Monitor web server disabled in config")
        return
    host = str(monitor.get("host", "0.0.0.0"))
    port = int(monitor.get("port", 8080))

    snap = network_snapshot(monitor_port=port)
    if snap.get("primary_ip"):
        logger.info(
            "Monitor http://%s:%s/  (LAN %s)",
            snap["primary_ip"],
            port,
            snap.get("mdns"),
        )

    handler = type("BoundMonitorHandler", (MonitorHandler,), {"config": config})
    server = ThreadingHTTPServer((host, port), handler)
    logger.info("Monitor listening on %s:%s", host, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Pi Ambient Synth LAN monitor")
    parser.add_argument("--config", type=Path, default=None)
    args = parser.parse_args()
    config = load_config(args.config)
    setup_logging(config.get("app", {}).get("log_level", "INFO"))
    serve(config)
    return 0


if __name__ == "__main__":
    sys.exit(main())
