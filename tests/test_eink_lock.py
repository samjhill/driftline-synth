"""E-ink file lock helpers."""

from __future__ import annotations

import fcntl
import os
from pathlib import Path

import pytest

from eink_lock import eink_exclusive_lock, eink_lock_is_held, eink_lock_path


def test_eink_lock_path_default(tmp_path, monkeypatch):
    monkeypatch.delenv("EINK_LOCK_FILE", raising=False)
    assert eink_lock_path().name == "pi-ambient-synth-eink.lock"


def test_eink_lock_is_held_when_locked(tmp_path, monkeypatch):
    lock = tmp_path / "test.lock"
    monkeypatch.setenv("EINK_LOCK_FILE", str(lock))
    assert not eink_lock_is_held()
    with open(lock, "w", encoding="utf-8") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert eink_lock_is_held()
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    assert not eink_lock_is_held()


def test_eink_exclusive_lock_releases(tmp_path, monkeypatch):
    lock = tmp_path / "test.lock"
    monkeypatch.setenv("EINK_LOCK_FILE", str(lock))
    with eink_exclusive_lock(timeout_seconds=1.0):
        assert eink_lock_is_held()
    assert not eink_lock_is_held()
