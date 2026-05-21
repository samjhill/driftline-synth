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
