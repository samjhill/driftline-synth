"""Tests for network_info."""

from __future__ import annotations

from unittest.mock import patch

from network_info import get_primary_ipv4, network_snapshot, save_network_info


def test_network_snapshot_shape():
    with patch("network_info.get_hostname", return_value="raspberrypi"):
        with patch("network_info.get_primary_ipv4", return_value="192.168.1.42"):
            with patch("network_info.get_all_ipv4", return_value=["192.168.1.42"]):
                snap = network_snapshot(monitor_port=8080)
    assert snap["primary_ip"] == "192.168.1.42"
    assert snap["monitor_url"] == "http://192.168.1.42:8080/"
    assert snap["mdns"] == "raspberrypi.local"


def test_save_network_info(tmp_path):
    snap = {"hostname": "pi", "primary_ip": "10.0.0.2", "monitor_url": "http://10.0.0.2:8080/"}
    out = save_network_info(snap, marker_dir=tmp_path, boot_log_dir=tmp_path / "boot-logs")
    assert out.is_file()
    assert (tmp_path / "network-address.txt").read_text().startswith("hostname=pi")
    assert (tmp_path / "boot-logs" / "network-address.txt").read_text().startswith("hostname=pi")


def test_get_primary_ipv4_from_hostname_i():
    with patch("network_info.subprocess.check_output", return_value="192.168.1.99  "):
        assert get_primary_ipv4() == "192.168.1.99"
