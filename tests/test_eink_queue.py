"""E-ink status PNG writes (ingest-style; no hardware)."""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from eink_queue import enqueue, enqueue_patch, enqueue_status  # noqa: E402


@pytest.fixture
def png_tmp(tmp_path, monkeypatch):
    png = tmp_path / "eink-status.png"
    monkeypatch.setenv("PI_EINK_STATUS_IMAGE_PATH", str(png))
    return png


def test_enqueue_status(png_tmp):
    p = enqueue_status("boot", "Hello", "sub", "det")
    assert p == png_tmp
    assert png_tmp.is_file()
    assert png_tmp.stat().st_size > 100


def test_enqueue_patch_explicit(png_tmp):
    p = enqueue_patch(name="Fog Bank", subtitle="Dorian", detail="seed 1")
    assert p == png_tmp
    assert png_tmp.is_file()


def test_enqueue_startup_maps_to_status(png_tmp):
    from eink_queue import enqueue_startup

    p = enqueue_startup()
    assert p == png_tmp


def test_enqueue_requires_type():
    assert enqueue({}) is None
