"""show_status helpers (no hardware / numpy required)."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from show_status import _skip_numpy_sigil  # noqa: E402


def test_skip_numpy_sigil_from_monitor_config() -> None:
    assert _skip_numpy_sigil({"monitor": {"skip_sigil": True}}) is True
    assert _skip_numpy_sigil({"monitor": {"skip_sigil": False}}) is False


def test_skip_numpy_sigil_from_eink_config() -> None:
    assert _skip_numpy_sigil({"eink": {"skip_numpy_sigil": True}}) is True


def test_skip_numpy_sigil_env(monkeypatch) -> None:
    monkeypatch.setenv("PI_EINK_SKIP_NUMPY", "1")
    assert _skip_numpy_sigil({}) is True
