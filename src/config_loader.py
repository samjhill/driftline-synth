"""Load YAML configuration."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def load_config(path: Path | None = None) -> dict[str, Any]:
    if path is None:
        path = Path(__file__).resolve().parent.parent / "config" / "default.yaml"
    with open(path) as f:
        return yaml.safe_load(f)
