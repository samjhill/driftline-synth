"""Visual generator determinism tests."""

from __future__ import annotations

from pathlib import Path

import pytest
from PIL import Image

from config_loader import load_config
from patch_generator import PatchGenerator
from visual_generator import VisualGenerator


@pytest.fixture
def visual():
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    return VisualGenerator(config)


@pytest.fixture
def patch():
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    return PatchGenerator(config).generate(seed=4242)


def test_same_patch_same_image(visual, patch):
    a = visual.render_patch(patch)
    b = visual.render_patch(patch)
    assert list(a.getdata()) == list(b.getdata())


def test_different_seed_different_image(visual):
    config = load_config(Path(__file__).resolve().parent.parent / "config" / "default.yaml")
    gen = PatchGenerator(config)
    p1 = gen.generate(seed=1)
    p2 = gen.generate(seed=2)
    img1 = visual.render_patch(p1)
    img2 = visual.render_patch(p2)
    assert list(img1.getdata()) != list(img2.getdata())


def test_image_dimensions(visual, patch):
    img = visual.render_patch(patch)
    assert isinstance(img, Image.Image)
    assert img.size == (250, 122)
    assert img.mode == "1"
