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

from config_loader import install_root, load_config, resolve_data_path
from logging_setup import setup_logging
from midi_controller import midi_status_summary
from network_info import network_snapshot
from patch_generator import PatchGenerator
from patch_resolve import resolve_current_patch
from pisugar_battery import read_battery_snapshot
from state_store import StateStore

logger = logging.getLogger(__name__)

DEPLOY_LOG = Path("/var/log/pi-ambient-synth-deploy.log")
EINK_LOG = Path("/var/log/pi-ambient-synth-eink.log")
EINK_LOG_CANDIDATES = (
    EINK_LOG,
    Path("/boot/firmware/pi-ambient-synth/boot-logs/eink.log"),
    Path("/boot/pi-ambient-synth/boot-logs/eink.log"),
)
DEPLOY_SHA_FILE = Path("/home/pi/pi-ambient-synth/.deploy_sha")
DEPLOY_SHA_PLACEHOLDERS = frozenset({"", "boot", "boot-sd", "latest"})
NETWORK_FILE = Path("/var/lib/pi-ambient-synth/network.json")
MARKER_DIR = Path("/var/lib/pi-ambient-synth")

SERVICE_UNITS = {
    "supercollider": "supercollider.service",
    "synth": "pi-ambient-synth.service",
    "monitor": "pi-ambient-synth-monitor.service",
    "deploy_timer": "pi-ambient-synth-deploy.timer",
}


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


def _service_detail(unit: str) -> dict[str, str]:
    props = (
        "ActiveState",
        "SubState",
        "Result",
        "MainPID",
        "ExecMainStatus",
        "NRestarts",
    )
    try:
        out = subprocess.run(
            ["systemctl", "show", unit, "--property", ",".join(props), "--no-pager"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        detail: dict[str, str] = {}
        for line in (out.stdout or "").splitlines():
            if "=" in line:
                key, val = line.split("=", 1)
                detail[key] = val
        return detail
    except (subprocess.SubprocessError, FileNotFoundError):
        return {}


def _systemctl_status_tail(unit: str, lines: int = 10) -> list[str]:
    try:
        out = subprocess.run(
            ["systemctl", "status", unit, "--no-pager", "-l"],
            capture_output=True,
            text=True,
            timeout=8,
        )
        text = out.stdout or out.stderr or ""
        return [ln for ln in text.splitlines() if ln.strip()][-lines:]
    except (subprocess.SubprocessError, FileNotFoundError):
        return []


def _journal_tail(unit: str, lines: int) -> tuple[list[str], str | None]:
    try:
        out = subprocess.run(
            [
                "journalctl",
                "-u",
                unit,
                "-n",
                str(lines),
                "--no-pager",
                "-o",
                "short-precise",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if out.returncode != 0:
            err = (out.stderr or out.stdout or "journalctl failed").strip()
            return [], err[:200]
        rows = [ln for ln in (out.stdout or "").splitlines() if ln.strip()]
        return rows[-lines:], None
    except (subprocess.SubprocessError, FileNotFoundError) as e:
        return [], str(e)


def _tail_file(path: Path, lines: int = 40) -> list[str]:
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        return text.splitlines()[-lines:]
    except OSError:
        return []


def _resolve_eink_log() -> Path:
    """Prefer /var/log; fall back to SD boot-logs mirror from early boot."""
    for path in EINK_LOG_CANDIDATES:
        try:
            if path.is_file() and path.stat().st_size > 0:
                return path
        except OSError:
            continue
    return EINK_LOG


def _read_deploy_sha() -> tuple[str, str | None]:
    """Return (short_sha_for_display, deploy_source_hint)."""
    candidates: list[tuple[str, Path]] = [
        ("install", DEPLOY_SHA_FILE),
        ("marker", MARKER_DIR / "last_deploy_sha"),
    ]
    placeholder = ""
    for source, path in candidates:
        if not path.is_file():
            continue
        try:
            raw = path.read_text(encoding="utf-8", errors="replace").strip()
        except OSError:
            continue
        if raw.lower() in DEPLOY_SHA_PLACEHOLDERS:
            if not placeholder:
                placeholder = raw[:12]
            continue
        return raw[:12], source
    if placeholder:
        return placeholder, "sd-bootstrap"
    return "", None


def _battery_status(config: dict[str, Any]) -> dict[str, Any]:
    snap = read_battery_snapshot(config)
    return {
        "available": snap.available,
        "percent": snap.display_percent,
        "voltage_v": snap.voltage_v,
        "charging": snap.charging,
        "plugged": snap.plugged,
        "charging_indicator": snap.shows_charging_indicator,
        "label": snap.label,
    }


def _read_marker_file(name: str) -> str | None:
    path = MARKER_DIR / name
    if not path.is_file():
        return None
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()[:500]
    except OSError:
        return None


def collect_status(config: dict[str, Any]) -> dict[str, Any]:
    app = config.get("app", {})
    monitor = config.get("monitor", {})
    port = int(monitor.get("port", 8080))
    journal_lines = int(monitor.get("journal_lines", 22))
    log_tail_lines = int(monitor.get("log_tail_lines", 35))

    root = install_root()
    store = StateStore(
        resolve_data_path(app.get("state_path", "./state/current_patch.json"), root),
        resolve_data_path(app.get("favorites_path", "./state/favorites.json"), root),
    )
    patch = resolve_current_patch(config, store, PatchGenerator(config))
    if not store.state_path.exists():
        try:
            store.save_current(patch)
        except OSError:
            pass
    patch_data = patch.to_dict()

    network = network_snapshot(monitor_port=port)
    if NETWORK_FILE.is_file():
        try:
            cached = json.loads(NETWORK_FILE.read_text(encoding="utf-8"))
            if cached.get("primary_ip"):
                network = {**network, **cached}
        except (json.JSONDecodeError, OSError):
            pass

    deploy_sha, deploy_sha_source = _read_deploy_sha()

    services: dict[str, str] = {}
    service_details: dict[str, dict[str, str]] = {}
    for key, unit in SERVICE_UNITS.items():
        services[key] = _service_state(unit)
        service_details[key] = _service_detail(unit)

    journal_logs: dict[str, list[str]] = {}
    journal_errors: dict[str, str] = {}
    status_snippets: dict[str, list[str]] = {}
    for key, unit in SERVICE_UNITS.items():
        if key == "deploy_timer":
            continue
        lines, err = _journal_tail(unit, journal_lines)
        journal_logs[key] = lines
        if err:
            journal_errors[key] = err
        status_snippets[key] = _systemctl_status_tail(unit, 8)

    sc_ready_path = MARKER_DIR / "sc-engine-ready"
    sc_engine_ready = (
        sc_ready_path.read_text(encoding="utf-8").strip()
        if sc_ready_path.is_file()
        else None
    )

    try:
        midi = midi_status_summary(config)
    except Exception as e:
        logger.warning("MIDI status unavailable: %s", e)
        midi = {
            "label": f"MIDI status unavailable ({e})",
            "ok": None,
            "inputs": [],
            "device_present": False,
        }

    return {
        "app": app.get("name", "Pi Ambient Synth"),
        "collected_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "uptime_seconds": int(time.time() - ps_boot_time()) if ps_boot_time() else None,
        "network": network,
        "midi": midi,
        "services": services,
        "service_details": service_details,
        "patch": patch_data,
        "patch_summary": patch.summary() if patch else None,
        "deploy_sha": deploy_sha,
        "deploy_sha_source": deploy_sha_source,
        "sc_engine_ready": sc_engine_ready,
        "deploy_log_tail": _tail_file(DEPLOY_LOG, log_tail_lines),
        "eink_log_path": str(_resolve_eink_log()),
        "eink_log_tail": _tail_file(_resolve_eink_log(), log_tail_lines),
        "last_eink_status": _read_marker_file("last_eink_status"),
        "battery": _battery_status(config),
        "network_address": _read_marker_file("network-address.txt"),
        "journal_logs": journal_logs,
        "journal_errors": journal_errors,
        "status_snippets": status_snippets,
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


def _escape(text: str) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _log_block(lines: list[str], *, empty: str = "No log lines.") -> str:
    if not lines:
        return f"<div class='log muted'>{_escape(empty)}</div>"
    return "".join(f"<div class='log'>{_escape(line)}</div>" for line in lines)


def _html_page(status: dict[str, Any]) -> str:
    net = status.get("network") or {}
    ip = net.get("primary_ip") or "—"
    host = net.get("hostname") or "pi"
    mdns = net.get("mdns") or f"{host}.local"
    monitor_url = net.get("monitor_url") or "#"
    all_ips = ", ".join(net.get("all_ips") or []) or ip
    svc = status.get("services") or {}
    details = status.get("service_details") or {}
    patch_sum = status.get("patch_summary") or "No patch loaded"
    sha = status.get("deploy_sha") or "—"
    sha_source = status.get("deploy_sha_source")
    if sha_source == "sd-bootstrap" and sha:
        sha = f"{sha} (SD — waiting for GitHub deploy)"
    collected = status.get("collected_at") or ""
    midi = status.get("midi") or {}
    midi_label = midi.get("label") or "Unknown"
    midi_ok = midi.get("ok")
    midi_inputs = ", ".join(midi.get("inputs") or []) or "—"

    def row(label: str, value: str, ok: bool | None = None) -> str:
        td_class = "ok" if ok is True else ("bad" if ok is False else "")
        attr = f' class="{td_class}"' if td_class else ""
        return f"<tr><th>{_escape(label)}</th><td{attr}>{_escape(value)}</td></tr>"

    svc_rows = "".join(
        row(name, state, ok=state == "active") for name, state in svc.items()
    )

    detail_rows = ""
    for name, props in details.items():
        if not props:
            continue
        summary = (
            f"{props.get('ActiveState', '?')} / {props.get('SubState', '?')} "
            f"pid={props.get('MainPID', '0')} restarts={props.get('NRestarts', '?')} "
            f"result={props.get('Result', '?')}"
        )
        ok = svc.get(name) == "active"
        detail_rows += row(f"{name} detail", summary, ok=ok)

    alerts: list[str] = []
    if midi_ok is False:
        alerts.append(
            f"<div class='alert'>MIDI keyboard: <strong>{_escape(midi_label)}</strong></div>"
        )
    for name, state in svc.items():
        if state not in ("active", "inactive"):
            alerts.append(
                f"<div class='alert'>{_escape(name)}: <strong>{_escape(state)}</strong></div>"
            )
    journal_errors = status.get("journal_errors") or {}
    for name, err in journal_errors.items():
        alerts.append(
            f"<div class='alert muted'>{_escape(name)} journal: {_escape(err)}</div>"
        )

    def section(title: str, lines: list[str], *, empty: str) -> str:
        return f"""<section>
    <h2>{_escape(title)}</h2>
    {_log_block(lines, empty=empty)}
  </section>"""

    log_sections = section(
        "Deploy log",
        status.get("deploy_log_tail") or [],
        empty="No deploy log yet.",
    )
    eink_path = status.get("eink_log_path") or str(EINK_LOG)
    eink_empty = f"No e-ink log yet (expected {eink_path})"
    last_eink = status.get("last_eink_status")
    if last_eink:
        eink_empty += f". Last status marker: {_escape(last_eink)}"
    log_sections += section(
        f"E-ink log ({eink_path})",
        status.get("eink_log_tail") or [],
        empty=eink_empty,
    )

    journal_logs = status.get("journal_logs") or {}
    status_snippets = status.get("status_snippets") or {}
    for key in ("supercollider", "synth", "monitor"):
        jlines = journal_logs.get(key) or []
        slog = status_snippets.get(key) or []
        combined = slog + ([""] if slog and jlines else []) + jlines
        log_sections += section(
            f"{key} (systemctl + journal)",
            combined,
            empty=f"No journal for {key}.service (add user pi to group adm?)",
        )

    net_addr = status.get("network_address")
    net_row = ""
    if net_addr:
        net_row = row("network-address.txt", net_addr.replace("\n", " · ")[:120])

    bat = status.get("battery") or {}
    if bat.get("available"):
        bat_label = bat.get("label") or f"{bat.get('percent')}%"
        if bat.get("charging_indicator"):
            bat_label = f"{bat_label} — charging"
        elif bat.get("plugged"):
            bat_label = f"{bat_label} — plugged in"
        bat_row = row("PiSugar battery", bat_label, ok=(bat.get("percent") or 0) > 15)
    else:
        bat_row = row("PiSugar battery", "unavailable (pisugar-server?)", ok=None)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="5">
  <title>{_escape(status.get("app", "Pi Ambient Synth"))} — Monitor</title>
  <style>
    :root {{ font-family: system-ui, sans-serif; background: #0f1419; color: #e7ecef; }}
    body {{ margin: 1.5rem; max-width: 56rem; }}
    h1 {{ font-size: 1.35rem; font-weight: 600; }}
    h2 {{ font-size: 0.95rem; font-weight: 600; color: #9ab; margin: 0 0 0.5rem; }}
    .ip {{ font-size: 1.75rem; letter-spacing: 0.02em; margin: 0.5rem 0 1rem; }}
    a {{ color: #7ec8e3; }}
    table {{ border-collapse: collapse; width: 100%; margin: 1rem 0; }}
    th, td {{ text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid #2a3540; }}
    th {{ color: #9ab; width: 11rem; font-weight: 500; vertical-align: top; }}
    .ok {{ color: #6ddb8a; }}
    .bad {{ color: #f08080; }}
    .log {{ font-family: ui-monospace, monospace; font-size: 0.72rem; color: #aab; line-height: 1.35; }}
    .muted {{ color: #667; }}
    .alert {{ background: #2a1a1a; border: 1px solid #633; color: #f0a0a0; padding: 0.5rem 0.75rem; margin: 0.5rem 0; font-size: 0.85rem; }}
    section {{ margin-top: 1.25rem; padding: 0.75rem; background: #141a21; border-radius: 6px; }}
  </style>
</head>
<body>
  <h1>{_escape(status.get("app", "Pi Ambient Synth"))}</h1>
  <p class="ip">{_escape(ip)}</p>
  <p><a href="{_escape(monitor_url)}">{_escape(monitor_url)}</a> · {_escape(mdns)} · {_escape(all_ips)}</p>
  <p class="muted">Snapshot {_escape(collected)} · auto-refresh 5s · LAN only (no auth)</p>
  {"".join(alerts)}
  <table>
    {row("Hostname", host)}
    {row("SSH", f"ssh pi@{mdns}")}
    {row("MIDI keyboard", midi_label, ok=midi_ok)}
    {row("MIDI inputs", midi_inputs)}
    {row("Current patch", patch_sum)}
    {row("Deploy SHA", sha)}
    {row("SC engine", status.get("sc_engine_ready") or "not ready (no /var/lib/pi-ambient-synth/sc-engine-ready)")}
    {bat_row}
    {net_row}
    {svc_rows}
    {detail_rows}
  </table>
  {log_sections}
</body>
</html>"""


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
