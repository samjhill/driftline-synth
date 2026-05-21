"""Lightweight LAN status page for Pi Ambient Synth (stdlib HTTP)."""

from __future__ import annotations

import argparse
import io
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
from osc_client import PATCH_OSC_KEYS, OscClient
from patch_generator import PARAM_RANGES, PatchGenerator
from patch_model import Patch
from patch_resolve import resolve_current_patch
from pisugar_battery import read_battery_snapshot
from state_store import StateStore
from visual_generator import VisualGenerator

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

# Web UI knobs — (key, label, optional log scale for wide numeric ranges)
WEB_KNOBS: tuple[tuple[str, str, bool], ...] = (
    ("oscillator_blend", "Wave blend", False),
    ("filter_cutoff", "Filter", True),
    ("filter_resonance", "Resonance", False),
    ("brightness", "Brightness", False),
    ("reverb_mix", "Reverb", False),
    ("reverb_size", "Room", False),
    ("delay_mix", "Delay", False),
    ("lfo_rate", "LFO rate", False),
    ("lfo_depth", "LFO depth", False),
    ("drift_amount", "Drift", False),
    ("texture_density", "Texture", False),
    ("stereo_width", "Width", False),
    ("sub_level", "Sub", False),
    ("noise_level", "Noise", False),
)

WAVE_SHAPE_PRESETS: tuple[tuple[str, float], ...] = (
    ("Sine", 0.0),
    ("Soft", 0.25),
    ("Blend", 0.5),
    ("Bright", 0.75),
    ("Saw", 1.0),
)

WEB_MORPH_SECONDS = 0.35


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


def _state_store(config: dict[str, Any]) -> StateStore:
    app = config.get("app", {})
    root = install_root()
    return StateStore(
        resolve_data_path(app.get("state_path", "./state/current_patch.json"), root),
        resolve_data_path(app.get("favorites_path", "./state/favorites.json"), root),
    )


def _load_patch(config: dict[str, Any]) -> Patch:
    store = _state_store(config)
    return resolve_current_patch(config, store, PatchGenerator(config))


def _knob_spec(key: str, label: str, log_scale: bool) -> dict[str, Any]:
    lo, hi = PARAM_RANGES.get(key, (0.0, 1.0))
    return {
        "key": key,
        "label": label,
        "min": lo,
        "max": hi,
        "log": log_scale,
        "step": (hi - lo) / 200 if not log_scale else None,
    }


def _controls_payload(config: dict[str, Any]) -> dict[str, Any]:
    patch = _load_patch(config)
    patch_data = patch.to_dict()
    knobs = [_knob_spec(key, label, log_scale) for key, label, log_scale in WEB_KNOBS]
    vol = float(config.get("audio", {}).get("default_volume", 0.65))
    return {
        "patch": patch_data,
        "knobs": knobs,
        "wave_presets": [{"name": n, "blend": v} for n, v in WAVE_SHAPE_PRESETS],
        "master_volume": vol,
        "osc_weights": _osc_weights(patch.oscillator_blend),
    }


def _osc_weights(blend: float) -> dict[str, float]:
    """Match SuperCollider Mix levels in piAmbientVoice."""
    b = max(0.0, min(1.0, blend))
    return {
        "saw": 0.35 * b,
        "sine": 0.4 * (1.0 - b),
        "triangle": 0.25 * b,
    }


def _sigil_png(config: dict[str, Any], patch: Patch | None = None) -> bytes:
    p = patch or _load_patch(config)
    img = VisualGenerator(config).render_patch(p)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _apply_web_param(
    config: dict[str, Any], name: str, value: float, *, persist: bool = True
) -> dict[str, Any]:
    if name == "master_volume":
        OscClient(config).set_param("master_volume", value)
        return {"ok": True, "name": name, "value": value}

    if name not in PATCH_OSC_KEYS:
        return {"ok": False, "error": f"unknown param: {name}"}

    val = float(value)
    lo, hi = PARAM_RANGES.get(name, (None, None))
    if lo is not None and hi is not None:
        val = max(lo, min(hi, val))

    osc = OscClient(config)
    osc._client.send_message("/pi_synth/morph_time", [WEB_MORPH_SECONDS])
    osc.set_param(name, val)

    if persist:
        store = _state_store(config)
        patch = _load_patch(config)
        if hasattr(patch, name):
            setattr(patch, name, val)
            try:
                store.save_current(patch)
            except OSError as e:
                logger.warning("Could not persist patch param %s: %s", name, e)

    return {"ok": True, "name": name, "value": val}


def _parse_post_json(handler: BaseHTTPRequestHandler) -> dict[str, Any] | None:
    length = int(handler.headers.get("Content-Length", 0) or 0)
    if length <= 0:
        return None
    try:
        raw = handler.rfile.read(length)
        return json.loads(raw.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


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

    patch_json = json.dumps(status.get("patch") or {}, separators=(",", ":"))

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{_escape(status.get("app", "Pi Ambient Synth"))} — Monitor</title>
  <style>
    :root {{ font-family: system-ui, sans-serif; background: #0f1419; color: #e7ecef; }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; padding: 1.25rem 1.5rem 2rem; }}
    .layout {{ display: grid; gap: 1.25rem; max-width: 72rem; }}
    @media (min-width: 900px) {{ .layout {{ grid-template-columns: 1fr 22rem; align-items: start; }} }}
    h1 {{ font-size: 1.35rem; font-weight: 600; margin: 0 0 0.25rem; }}
    h2 {{ font-size: 0.95rem; font-weight: 600; color: #9ab; margin: 0 0 0.5rem; }}
    .ip {{ font-size: 1.75rem; letter-spacing: 0.02em; margin: 0.25rem 0 0.75rem; }}
    a {{ color: #7ec8e3; }}
    table {{ border-collapse: collapse; width: 100%; margin: 0.75rem 0; }}
    th, td {{ text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid #2a3540; }}
    th {{ color: #9ab; width: 11rem; font-weight: 500; vertical-align: top; }}
    .ok {{ color: #6ddb8a; }}
    .bad {{ color: #f08080; }}
    .log {{ font-family: ui-monospace, monospace; font-size: 0.72rem; color: #aab; line-height: 1.35; }}
    .muted {{ color: #667; font-size: 0.85rem; }}
    .alert {{ background: #2a1a1a; border: 1px solid #633; color: #f0a0a0; padding: 0.5rem 0.75rem; margin: 0.5rem 0; font-size: 0.85rem; }}
    section {{ margin-top: 1rem; padding: 0.75rem; background: #141a21; border-radius: 6px; }}
    .panel {{ background: #141a21; border-radius: 8px; padding: 1rem; position: sticky; top: 1rem; }}
    .sigil-wrap {{ background: #e8ecef; border-radius: 4px; padding: 4px; margin-bottom: 0.75rem; }}
    .sigil-wrap img {{ display: block; width: 100%; height: auto; image-rendering: pixelated; }}
    #wave-canvas {{ width: 100%; height: 72px; background: #0a0e12; border-radius: 4px; display: block; margin: 0.5rem 0; }}
    .wave-presets {{ display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 0.75rem; }}
    .wave-presets button {{
      flex: 1 1 auto; min-width: 3.2rem; padding: 0.35rem 0.5rem; font-size: 0.72rem;
      background: #1e2830; color: #cde; border: 1px solid #3a4a55; border-radius: 4px; cursor: pointer;
    }}
    .wave-presets button.active {{ background: #2a4a5a; border-color: #7ec8e3; color: #fff; }}
    .knob-grid {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 0.65rem 0.5rem; }}
    .knob-cell {{ text-align: center; }}
    .knob-dial {{
      width: 3.4rem; height: 3.4rem; margin: 0 auto; border-radius: 50%;
      background: conic-gradient(from 225deg, #3a5a6a 0deg, #1a242c 270deg);
      border: 2px solid #2a3540; position: relative; cursor: ns-resize; touch-action: none;
    }}
    .knob-dial::after {{
      content: ''; position: absolute; left: 50%; top: 18%; width: 3px; height: 28%;
      background: #7ec8e3; transform-origin: 50% 100%; transform: translateX(-50%) rotate(0deg);
      border-radius: 2px;
    }}
    .knob-label {{ display: block; font-size: 0.68rem; color: #9ab; margin-top: 0.25rem; }}
    .knob-val {{ display: block; font-size: 0.65rem; color: #667; font-variant-numeric: tabular-nums; }}
    .vol-row {{ margin-top: 0.75rem; }}
    .vol-row input[type=range] {{ width: 100%; accent-color: #7ec8e3; }}
    .status-refresh {{ margin-left: 0.5rem; }}
  </style>
</head>
<body>
  <h1>{_escape(status.get("app", "Pi Ambient Synth"))}</h1>
  <p class="ip">{_escape(ip)}</p>
  <p><a href="{_escape(monitor_url)}">{_escape(monitor_url)}</a> · {_escape(mdns)} · {_escape(all_ips)}</p>
  <p class="muted">Status <span id="status-time">{_escape(collected)}</span>
    <button type="button" class="status-refresh" id="btn-refresh-status">Refresh</button> · LAN only (no auth)</p>
  <div class="layout">
    <div class="main-col">
      <div id="status-alerts">{"".join(alerts)}</div>
      <table id="status-table">
        {row("Hostname", host)}
        {row("SSH", f"ssh pi@{mdns}")}
        {row("MIDI keyboard", midi_label, ok=midi_ok)}
        {row("MIDI inputs", midi_inputs)}
        {row("Current patch", patch_sum, ok=None)}
        {row("Deploy SHA", sha)}
        {row("SC engine", status.get("sc_engine_ready") or "not ready (no /var/lib/pi-ambient-synth/sc-engine-ready)")}
        {bat_row}
        {net_row}
        {svc_rows}
        {detail_rows}
      </table>
      {log_sections}
    </div>
    <aside class="panel" id="controls-panel">
      <h2>Sound controls</h2>
      <p class="muted" id="patch-title">{_escape(patch_sum)}</p>
      <div class="sigil-wrap">
        <img id="sigil" src="/api/sigil.png" alt="Patch sigil visualization" width="234" height="114">
      </div>
      <h2>Wave shape</h2>
      <canvas id="wave-canvas" width="280" height="72" aria-label="Oscillator mix waveform"></canvas>
      <div class="wave-presets" id="wave-presets"></div>
      <div class="knob-grid" id="knob-grid"></div>
      <div class="vol-row">
        <label class="knob-label" for="master-vol">Master volume</label>
        <input type="range" id="master-vol" min="0" max="1" step="0.01">
      </div>
    </aside>
  </div>
  <script type="application/json" id="boot-patch">{patch_json}</script>
  <script>
  (function() {{
    const bootPatch = JSON.parse(document.getElementById('boot-patch').textContent || '{{}}');
    let controls = null;
    let paramValues = {{ ...bootPatch }};
    let knobDrag = null;

    function oscWeights(blend) {{
      const b = Math.max(0, Math.min(1, blend));
      return {{ saw: 0.35 * b, sine: 0.4 * (1 - b), tri: 0.25 * b }};
    }}

    function normVal(spec, v) {{
      const lo = spec.min, hi = spec.max;
      if (spec.log && hi > lo && v > 0) {{
        const ln = Math.log(v / lo) / Math.log(hi / lo);
        return Math.max(0, Math.min(1, ln));
      }}
      return (v - lo) / (hi - lo);
    }}

    function valFromNorm(spec, t) {{
      const lo = spec.min, hi = spec.max;
      t = Math.max(0, Math.min(1, t));
      if (spec.log && hi > lo) return lo * Math.pow(hi / lo, t);
      return lo + t * (hi - lo);
    }}

    function fmtVal(key, v) {{
      if (key === 'filter_cutoff') return Math.round(v) + ' Hz';
      if (key === 'oscillator_blend') return Math.round(v * 100) + '%';
      return v < 0.1 ? v.toFixed(3) : v.toFixed(2);
    }}

    function drawWave(blend) {{
      const c = document.getElementById('wave-canvas');
      const ctx = c.getContext('2d');
      const w = c.width, h = c.height;
      ctx.fillStyle = '#0a0e12';
      ctx.fillRect(0, 0, w, h);
      const wts = oscWeights(blend);
      const pts = 200;
      ctx.beginPath();
      ctx.strokeStyle = '#7ec8e3';
      ctx.lineWidth = 1.5;
      for (let i = 0; i <= pts; i++) {{
        const ph = (i / pts) * Math.PI * 2;
        const saw = 2 * (ph / (Math.PI * 2) - Math.floor(ph / (Math.PI * 2) + 0.5));
        const sine = Math.sin(ph);
        const tri = 2 * Math.abs(2 * (ph / (Math.PI * 2) - Math.floor(ph / (Math.PI * 2) + 0.5))) - 1;
        const y = (saw * wts.saw + sine * wts.sine + tri * wts.tri);
        const px = (i / pts) * w;
        const py = h * 0.5 - y * (h * 0.38);
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }}
      ctx.stroke();
      ctx.fillStyle = '#667';
      ctx.font = '10px system-ui';
      ctx.fillText('saw ' + Math.round(wts.saw * 100) + '% · sine ' + Math.round(wts.sine * 100) + '% · tri ' + Math.round(wts.tri * 100) + '%', 6, h - 6);
    }}

    function refreshSigil() {{
      document.getElementById('sigil').src = '/api/sigil.png?t=' + Date.now();
    }}

    async function setParam(name, value) {{
      const res = await fetch('/api/param', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify({{ name, value }}),
      }});
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'set failed');
      paramValues[name] = data.value;
      if (name === 'oscillator_blend') {{
        drawWave(data.value);
        updateWavePresetActive(data.value);
      }}
      if (name === 'texture_density' || name === 'filter_cutoff' || name === 'reverb_size' || name === 'brightness' || name === 'stereo_width' || name === 'drift_amount')
        refreshSigil();
      return data;
    }}

    function updateWavePresetActive(blend) {{
      document.querySelectorAll('#wave-presets button').forEach(btn => {{
        const t = parseFloat(btn.dataset.blend);
        btn.classList.toggle('active', Math.abs(t - blend) < 0.06);
      }});
    }}

    function buildKnobs() {{
      const grid = document.getElementById('knob-grid');
      grid.innerHTML = '';
      (controls.knobs || []).forEach(spec => {{
        if (spec.key === 'oscillator_blend') return;
        const cell = document.createElement('div');
        cell.className = 'knob-cell';
        const dial = document.createElement('div');
        dial.className = 'knob-dial';
        dial.dataset.key = spec.key;
        const label = document.createElement('span');
        label.className = 'knob-label';
        label.textContent = spec.label;
        const valEl = document.createElement('span');
        valEl.className = 'knob-val';
        const v0 = paramValues[spec.key] ?? spec.min;
        valEl.textContent = fmtVal(spec.key, v0);
        function setDialAngle(norm) {{
          dial.style.setProperty('--angle', (225 + norm * 270) + 'deg');
          dial.querySelector?.('style') || dial.style;
          const after = dial;
          after.style.setProperty('--knob-rot', (225 + norm * 270) + 'deg');
          dial.style.background = 'conic-gradient(from 225deg, #3a5a6a ' + (norm * 270) + 'deg, #1a242c 270deg)';
          const needle = dial;
          needle.style.setProperty('--rot', (225 + norm * 270) + 'deg');
        }}
        const norm = normVal(spec, v0);
        dial.style.background = 'conic-gradient(from 225deg, #3a5a6a ' + (norm * 270) + 'deg, #1a242c 270deg)';
        const style = document.createElement('style');
        style.textContent = '.knob-dial[data-key="' + spec.key + '"]::after {{ transform: translateX(-50%) rotate(' + (225 + norm * 270) + 'deg); }}';
        dial.appendChild(style);
        dial.addEventListener('pointerdown', e => {{
          knobDrag = {{ spec, dial, valEl, startY: e.clientY, startNorm: normVal(spec, paramValues[spec.key] ?? spec.min) }};
          dial.setPointerCapture(e.pointerId);
        }});
        dial.addEventListener('pointermove', e => {{
          if (!knobDrag || knobDrag.spec.key !== spec.key) return;
          const dy = knobDrag.startY - e.clientY;
          const n = Math.max(0, Math.min(1, knobDrag.startNorm + dy / 120));
          const v = valFromNorm(spec, n);
          valEl.textContent = fmtVal(spec.key, v);
          dial.style.background = 'conic-gradient(from 225deg, #3a5a6a ' + (n * 270) + 'deg, #1a242c 270deg)';
          style.textContent = '.knob-dial[data-key="' + spec.key + '"]::after {{ transform: translateX(-50%) rotate(' + (225 + n * 270) + 'deg); }}';
        }});
        dial.addEventListener('pointerup', async e => {{
          if (!knobDrag || knobDrag.spec.key !== spec.key) return;
          const dy = knobDrag.startY - e.clientY;
          const n = Math.max(0, Math.min(1, knobDrag.startNorm + dy / 120));
          knobDrag = null;
          try {{ await setParam(spec.key, valFromNorm(spec, n)); }} catch (err) {{ console.warn(err); }}
        }});
        cell.appendChild(dial);
        cell.appendChild(label);
        cell.appendChild(valEl);
        grid.appendChild(cell);
      }});
      const blendSpec = (controls.knobs || []).find(k => k.key === 'oscillator_blend');
      if (blendSpec) {{
        const cell = document.createElement('div');
        cell.className = 'knob-cell';
        cell.style.gridColumn = '1 / -1';
        const dial = document.createElement('div');
        dial.className = 'knob-dial';
        dial.dataset.key = 'oscillator_blend';
        const label = document.createElement('span');
        label.className = 'knob-label';
        label.textContent = blendSpec.label;
        const valEl = document.createElement('span');
        valEl.className = 'knob-val';
        const v0 = paramValues.oscillator_blend ?? 0.5;
        valEl.textContent = fmtVal('oscillator_blend', v0);
        const norm = normVal(blendSpec, v0);
        const style = document.createElement('style');
        style.textContent = '.knob-dial[data-key="oscillator_blend"]::after {{ transform: translateX(-50%) rotate(' + (225 + norm * 270) + 'deg); }}';
        dial.style.background = 'conic-gradient(from 225deg, #3a5a6a ' + (norm * 270) + 'deg, #1a242c 270deg)';
        dial.appendChild(style);
        dial.addEventListener('pointerdown', e => {{
          knobDrag = {{ spec: blendSpec, dial, valEl, startY: e.clientY, startNorm: norm }};
          dial.setPointerCapture(e.pointerId);
        }});
        dial.addEventListener('pointermove', e => {{
          if (!knobDrag) return;
          const dy = knobDrag.startY - e.clientY;
          const n = Math.max(0, Math.min(1, knobDrag.startNorm + dy / 120));
          const v = valFromNorm(blendSpec, n);
          valEl.textContent = fmtVal('oscillator_blend', v);
          drawWave(v);
          updateWavePresetActive(v);
          dial.style.background = 'conic-gradient(from 225deg, #3a5a6a ' + (n * 270) + 'deg, #1a242c 270deg)';
          style.textContent = '.knob-dial[data-key="oscillator_blend"]::after {{ transform: translateX(-50%) rotate(' + (225 + n * 270) + 'deg); }}';
        }});
        dial.addEventListener('pointerup', async e => {{
          if (!knobDrag) return;
          const dy = knobDrag.startY - e.clientY;
          const n = Math.max(0, Math.min(1, knobDrag.startNorm + dy / 120));
          knobDrag = null;
          try {{ await setParam('oscillator_blend', valFromNorm(blendSpec, n)); }} catch (err) {{ console.warn(err); }}
        }});
        cell.appendChild(dial);
        cell.appendChild(label);
        cell.appendChild(valEl);
        grid.appendChild(cell);
      }}
    }}

    function buildWavePresets() {{
      const wrap = document.getElementById('wave-presets');
      wrap.innerHTML = '';
      (controls.wave_presets || []).forEach(p => {{
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.textContent = p.name;
        btn.dataset.blend = p.blend;
        btn.addEventListener('click', async () => {{
          try {{
            await setParam('oscillator_blend', p.blend);
            document.querySelectorAll('.knob-dial[data-key="oscillator_blend"] + .knob-label + .knob-val')
              .forEach(el => {{ if (el) el.textContent = fmtVal('oscillator_blend', p.blend); }});
          }} catch (err) {{ console.warn(err); }}
        }});
        wrap.appendChild(btn);
      }});
    }}

    async function loadControls() {{
      const res = await fetch('/api/controls');
      controls = await res.json();
      paramValues = {{ ...controls.patch }};
      buildWavePresets();
      buildKnobs();
      const blend = paramValues.oscillator_blend ?? 0.5;
      drawWave(blend);
      updateWavePresetActive(blend);
      const vol = document.getElementById('master-vol');
      vol.value = controls.master_volume ?? 0.65;
      const title = document.getElementById('patch-title');
      if (controls.patch && controls.patch.name)
        title.textContent = controls.patch.name + ' | ' + (controls.patch.scale_name || '') + ' | seed=' + controls.patch.seed;
    }}

    document.getElementById('master-vol').addEventListener('change', async e => {{
      try {{ await setParam('master_volume', parseFloat(e.target.value)); }} catch (err) {{ console.warn(err); }}
    }});

    document.getElementById('btn-refresh-status').addEventListener('click', async () => {{
      const res = await fetch('/api/status');
      const data = await res.json();
      document.getElementById('status-time').textContent = data.collected_at || '';
    }});

    loadControls().catch(err => console.warn('controls load', err));
  }})();
  </script>
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
        elif path == "/api/controls":
            body = json.dumps(_controls_payload(self.config), indent=2).encode("utf-8")
            self._send(200, "application/json", body)
        elif path == "/api/sigil.png":
            try:
                body = _sigil_png(self.config)
            except Exception as e:
                logger.warning("Sigil render failed: %s", e)
                self._send(500, "text/plain", b"sigil render failed\n")
                return
            self._send(200, "image/png", body)
        elif path == "/health":
            self._send(200, "text/plain", b"ok\n")
        else:
            self._send(404, "text/plain", b"not found\n")

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path != "/api/param":
            self._send(404, "text/plain", b"not found\n")
            return
        data = _parse_post_json(self)
        if not data or "name" not in data or "value" not in data:
            body = json.dumps({"ok": False, "error": "expected JSON {name, value}"}).encode(
                "utf-8"
            )
            self._send(400, "application/json", body)
            return
        try:
            result = _apply_web_param(
                self.config, str(data["name"]), float(data["value"])
            )
        except (TypeError, ValueError) as e:
            result = {"ok": False, "error": str(e)}
        code = 200 if result.get("ok") else 400
        self._send(code, "application/json", json.dumps(result).encode("utf-8"))

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
