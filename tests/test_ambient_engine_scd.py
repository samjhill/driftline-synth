"""Static validation for synth/ambient_engine.scd."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "validate_ambient_engine.py"
SCD = ROOT / "synth" / "ambient_engine.scd"


def test_ambient_engine_scd_static():
    proc = subprocess.run(
        [sys.executable, str(VALIDATOR), str(SCD)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr or proc.stdout


def _run_validator(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(path)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_rejects_python_ternary(tmp_path: Path):
    bad = tmp_path / "bad.scd"
    bad.write_text(
        '(\nvar x = getenv("PI_AMBIENT_ROOT") ? getenv("PI_AMBIENT_ROOT") : "/home/pi";\n)\n',
        encoding="utf-8",
    )
    proc = _run_validator(bad)
    assert proc.returncode != 0
    assert "ternary" in (proc.stderr or proc.stdout).lower()


def test_rejects_if_with_and_colon(tmp_path: Path):
    bad = tmp_path / "bad.scd"
    bad.write_text(
        "(\nif(~x.notNil and: { ~y.notNil }, { 1.postln });\n)\n",
        encoding="utf-8",
    )
    proc = _run_validator(bad)
    assert proc.returncode != 0
    assert "and:" in (proc.stderr or proc.stdout)
