"""Load YAML configuration."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def install_root() -> Path:
    return Path(__file__).resolve().parent.parent


def resolve_data_path(path: str | Path, root: Path | None = None) -> Path:
    """Resolve app-relative paths (e.g. ./state) under the install tree."""
    p = Path(path)
    if p.is_absolute():
        return p
    base = root or install_root()
    return (base / p).resolve()


def load_config(path: Path | None = None) -> dict[str, Any]:
    if path is None:
        path = install_root() / "config" / "default.yaml"
    with open(path) as f:
        return yaml.safe_load(f)
