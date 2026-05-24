"""Boot e-ink scripts must not disable synth display units (legacy purge is separate)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_prepare_boot_leaves_ambient_display_enabled():
    text = (ROOT / "scripts/eink_prepare_boot.sh").read_text(encoding="utf-8")
    assert "systemctl disable" not in text
    assert "systemctl stop pi-ambient" not in text


def test_enable_boot_units_lists_systemd_services():
    text = (ROOT / "scripts/eink_enable_boot_units.sh").read_text(encoding="utf-8")
    assert "pi-ambient-synth-eink-prepare.service" in text
    assert "pi-ambient-synth-eink-boot.service" in text
    assert "pi-ambient-synth-boot-display.service" in text
    assert "mask" in text


def test_purge_default_skips_ambient_boot_disable():
    text = (ROOT / "scripts/eink_purge_legacy_projects.sh").read_text(encoding="utf-8")
    assert "AGGRESSIVE" in text
    default_block = text.split('if [[ "$AGGRESSIVE" == "1" ]]; then', 1)[0]
    assert "pi-ambient-synth-boot-display" not in default_block
    aggressive_block = text.split('if [[ "$AGGRESSIVE" == "1" ]]; then', 1)[1]
    assert "pi-ambient-synth-boot-display" in aggressive_block
