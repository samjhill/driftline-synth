"""E-ink command queue (no hardware)."""

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from eink_queue import enqueue, enqueue_patch, enqueue_status, queue_depth  # noqa: E402


@pytest.fixture
def queue_tmp(tmp_path, monkeypatch):
    q = tmp_path / "q"
    monkeypatch.setenv("EINK_QUEUE_DIR", str(q))
    return q


def test_enqueue_status(queue_tmp):
    p = enqueue_status("boot", "Hello", "sub", "det")
    assert p is not None
    data = json.loads(p.read_text())
    assert data["type"] == "status"
    assert data["title"] == "Hello"
    assert queue_depth() == 1


def test_enqueue_patch_from_state(queue_tmp):
    p = enqueue_patch(from_state=True)
    assert p is not None
    assert json.loads(p.read_text())["type"] == "patch"


def test_enqueue_requires_type(queue_tmp):
    assert enqueue({}) is None
