#!/usr/bin/env python3
"""Assert Pi monitor /api/status matches what the LAN status page shows (E2E)."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from config_loader import load_config  # noqa: E402
from monitor_server import collect_status  # noqa: E402

MARKER_DIR = Path(os.environ.get("MARKER_DIR", "/var/lib/pi-ambient-synth"))
MIDI_UNIT = "pi-ambient-synth-midi.service"


def _midi_bridge_required() -> bool:
    import subprocess

    try:
        out = subprocess.run(
            ["systemctl", "list-unit-files", MIDI_UNIT, "--no-legend"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return MIDI_UNIT in (out.stdout or "")
    except (subprocess.SubprocessError, FileNotFoundError):
        return False


SNAPSHOT_JSON = MARKER_DIR / "e2e-status-snapshot.json"
SNAPSHOT_TXT = MARKER_DIR / "e2e-status-page.txt"


def _journal_lines(status: dict[str, Any], key: str, *, tail: int = 8) -> list[str]:
    logs = status.get("journal_logs") or {}
    lines = logs.get(key) or []
    if tail > 0:
        return lines[-tail:]
    return lines


def _journal_text(status: dict[str, Any], key: str, *, tail: int = 8) -> str:
    return "\n".join(_journal_lines(status, key, tail=tail))


def format_status_page(status: dict[str, Any]) -> str:
    """Human-readable block matching the monitor UI fields."""
    lines: list[str] = []
    lines.append(f"Snapshot {status.get('collected_at', '?')}")
    svc = status.get("services") or {}
    for name in ("supercollider", "synth", "synth_midi", "monitor", "deploy_timer"):
        if name in svc:
            lines.append(f"{name}: {svc[name]}")
    lines.append(f"Hostname\t{status.get('network', {}).get('hostname', '?')}")
    midi = status.get("midi") or {}
    lines.append(f"MIDI keyboard\t{midi.get('label', '?')}")
    lines.append(f"Current patch\t{status.get('patch_summary', '?')}")
    sha = status.get("deploy_sha") or "unknown"
    src = status.get("deploy_sha_source") or ""
    lines.append(f"Deploy SHA\t{sha}" + (f" ({src})" if src else ""))
    ready = status.get("sc_engine_ready")
    lines.append(
        "SC engine\t"
        + (ready if ready else "not ready (no /var/lib/pi-ambient-synth/sc-engine-ready)")
    )
    bat = status.get("battery") or {}
    if bat.get("available"):
        lines.append(
            f"PiSugar battery\t{bat.get('percent', '?')}%"
            + (" — plugged in" if bat.get("plugged") else "")
        )
    lines.append("")
    for key in ("supercollider", "synth", "synth_midi", "monitor"):
        detail = (status.get("service_details") or {}).get(key) or {}
        if detail:
            lines.append(
                f"{key} detail\t{detail.get('ActiveState', '?')} / "
                f"{detail.get('SubState', '?')} pid={detail.get('MainPID', '?')} "
                f"restarts={detail.get('NRestarts', '?')} result={detail.get('Result', '?')}"
            )
    lines.append("")
    lines.append("--- supercollider journal (tail) ---")
    lines.extend((status.get("journal_logs") or {}).get("supercollider") or ["(empty)"])
    lines.append("--- synth journal (tail) ---")
    lines.extend((status.get("journal_logs") or {}).get("synth") or ["(empty)"])
    midi_j = (status.get("journal_logs") or {}).get("synth_midi")
    if midi_j:
        lines.append("--- synth_midi journal (tail) ---")
        lines.extend(midi_j)
    lines.append("--- deploy log (tail) ---")
    lines.extend(status.get("deploy_log_tail") or ["(empty)"])
    return "\n".join(lines)


def collect_with_retry(timeout: float) -> dict[str, Any]:
    config = load_config()
    deadline = time.time() + timeout
    last: dict[str, Any] | None = None
    while time.time() < deadline:
        last = collect_status(config)
        svc = last.get("services") or {}
        if (
            svc.get("supercollider") == "active"
            and svc.get("synth") == "active"
            and last.get("sc_engine_ready")
        ):
            return last
        time.sleep(2.0)
    assert last is not None
    return last


def assert_status(status: dict[str, Any], *, phase: str) -> list[str]:
    errors: list[str] = []
    svc = status.get("services") or {}
    details = status.get("service_details") or {}

    def need(cond: bool, msg: str) -> None:
        if not cond:
            errors.append(msg)

    need(svc.get("supercollider") == "active", f"supercollider={svc.get('supercollider')!r}")
    need(svc.get("monitor") == "active", f"monitor={svc.get('monitor')!r}")
    need(bool(status.get("sc_engine_ready")), "SC engine not ready")

    synth_state = svc.get("synth")
    if synth_state != "active":
        errors.append(f"synth={synth_state!r} (want active)")

    midi_bridge = _midi_bridge_required()
    midi_svc = svc.get("synth_midi")
    if midi_bridge:
        need(midi_svc == "active", f"synth_midi={midi_svc!r} (want active)")

    sc_j = _journal_text(status, "supercollider", tail=12)
    synth_j = _journal_text(status, "synth", tail=8)
    midi_j = _journal_text(status, "synth_midi", tail=8)

    need("status=7/BUS" not in synth_j, "synth journal shows SIGBUS")
    if midi_bridge and midi_j:
        need("status=7/BUS" not in midi_j, "synth_midi journal shows SIGBUS")
    if "linearRamp" in sc_j and "not understood" in sc_j.lower():
        errors.append("SC journal shows linearRamp not understood")
    if re.search(r"syntax error|command line parse failed", sc_j, re.I):
        errors.append("SC journal shows sclang syntax/parse error")
    if phase != "baseline" and "Engine synths started" not in sc_j:
        errors.append("SC journal missing 'Engine synths started'")

    if phase in ("post-osc", "final"):
        need("pi_test_beep" in sc_j, "SC journal missing pi_test_beep after test_osc")

    if phase == "final":
        need("Reseed:" in sc_j, "SC journal missing Reseed: after simulate_midi_e2e")

    if midi_bridge and midi_svc == "active":
        need("MIDI bridge running" in midi_j, "synth_midi missing 'MIDI bridge running'")

    midi = status.get("midi") or {}
    if not midi.get("device_present"):
        errors.append(f"MIDI device not present: {midi.get('label')}")

    synth_detail = details.get("synth") or {}
    if synth_detail.get("Result") == "signal":
        errors.append(f"synth service Result=signal (restarts={synth_detail.get('NRestarts')})")

    sha = str(status.get("deploy_sha") or "")
    if len(sha) < 7:
        errors.append(f"deploy_sha looks invalid: {sha!r}")

    expect = os.environ.get("PI_EXPECT_DEPLOY_SHA", "").strip()
    if expect and not sha.startswith(expect[:7]):
        errors.append(f"deploy_sha {sha} does not match PI_EXPECT_DEPLOY_SHA {expect[:7]}")

    rsync_sha = MARKER_DIR / "e2e-rsync-sha"
    if rsync_sha.is_file():
        want = rsync_sha.read_text(encoding="utf-8").strip()[:7]
        if want and not sha.startswith(want):
            print(
                f"WARN: deploy_sha {sha} stale vs e2e rsync {want} "
                "(status page may lag; code was rsync'd)",
                file=sys.stderr,
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Assert monitor status page health")
    parser.add_argument(
        "--phase",
        choices=("snapshot", "wait", "baseline", "post-osc", "final"),
        default="final",
    )
    parser.add_argument("--wait-sec", type=float, default=60.0)
    args = parser.parse_args()

    MARKER_DIR.mkdir(parents=True, exist_ok=True)

    if args.phase == "wait":
        status = collect_with_retry(args.wait_sec)
    else:
        status = collect_status(load_config())

    SNAPSHOT_JSON.write_text(json.dumps(status, indent=2), encoding="utf-8")
    page_txt = format_status_page(status)
    SNAPSHOT_TXT.write_text(page_txt, encoding="utf-8")
    print(page_txt)
    print(f"\n(wrote {SNAPSHOT_JSON} and {SNAPSHOT_TXT})")

    if args.phase == "snapshot":
        return 0

    assert_phase = "baseline" if args.phase in ("wait", "baseline") else args.phase
    errors = assert_status(status, phase=assert_phase)
    if errors:
        print("\n--- status page assertion failures ---", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1
    print("\nOK — status page assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
