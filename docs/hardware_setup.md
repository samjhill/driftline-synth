# Hardware Setup

## Required

| Component | Notes |
|-----------|--------|
| Raspberry Pi 4B or 5 | Pi 3B+ works with lighter settings |
| Arturia KeyStep | USB MIDI controller |
| USB-A to USB-B **data** cable | Power-only cables will not work |
| Audio output | USB interface or 3.5 mm jack |
| Waveshare 2.13" E-Ink HAT V4 | 250×122, SPI |
| PiSugar 2 Pro (optional) | UPS under the Pi; battery % on e-ink |
| Speakers or headphones | |

## Wiring

```text
┌─────────────┐     USB data      ┌──────────────┐
│  KeyStep    │──────────────────▶│ Raspberry Pi │
└─────────────┘                   │              │
                                  │  GPIO header │
┌─────────────┐     SPI/GPIO      │      ▲       │
│ E-Ink HAT   │───────────────────┘      │       │
└─────────────┘                          stacked │
                                  ┌──────┴───────┐
                                  │ USB audio IF │ (optional)
                                  └──────────────┘
```

1. Stack the Waveshare HAT on the Pi GPIO header (power off first).
2. Connect KeyStep USB to any Pi USB port.
3. Connect speakers to the USB interface or Pi headphone jack.

## PiSugar 2 Pro / 2 Plus (battery on e-ink)

PiSugar renamed **2 Pro** → **2 Plus** in docs; pick **PiSugar 2 Pro** or **PiSugar 2 Plus** in the installer (same board — not the old 4-LED PiSugar 2).

Install [PiSugar Power Manager](https://docs.pisugar.com/docs/product-wiki/battery/pisugar-power-manager) and enable the server:

```bash
wget https://cdn.pisugar.com/release/pisugar-power-manager.sh
bash pisugar-power-manager.sh -c release
# When prompted, select PiSugar 2 Pro / 2 Plus (2 charging LEDs on the board)
sudo systemctl enable --now pisugar-server
echo "get battery" | nc -U /tmp/pisugar-server.sock
echo "get model" | nc -U /tmp/pisugar-server.sock
```

**Wrong model** (e.g. generic PiSugar 2 with 4 LEDs) often leaves `battery:` stuck at one value (~26%). Fix without reinstall:

```bash
sudo dpkg-reconfigure pisugar-server
# Choose PiSugar 2 Pro / PiSugar 2 Plus
sudo systemctl restart pisugar-server
echo "get battery" | nc -U /tmp/pisugar-server.sock
```

Web UI: `http://<pi-ip>:8421`. Config file: `/etc/pisugar-server/config.json`.

The synth reads `battery: N` from `/tmp/pisugar-server.sock` (or TCP `127.0.0.1:8423`) and draws a gauge + **NN%** in the top-right of the e-ink (patch sigils and status screens). Toggle in `config/default.yaml` under `pisugar:`.

**Reseed button:** With `pisugar.reseed_on_button: true` (default), deploy/restart registers a **single tap** on the PiSugar’s physical button to queue a new ambient patch (`scripts/pi_pisugar_button_reseed.sh` → `/var/lib/pi-ambient-synth/reseed.request`). See [keystep_reseed.md](keystep_reseed.md). Configure or inspect taps in the web UI (`http://<pi-ip>:8421`) under button actions, or via `get button_shell single` on the socket.

## SPI

Enable SPI before first boot with display:

```bash
sudo raspi-config nonint do_spi 0
sudo reboot
```

## Permissions

Run as user `pi` with gpio/spi group membership (default on Raspberry Pi OS).

## Waveshare Driver

Clone Waveshare library into `vendor/waveshare` or install per [Waveshare wiki](https://www.waveshare.com/wiki/2.13inch_e-Paper_HAT):

```bash
git clone https://github.com/waveshare/e-Paper.git vendor/waveshare-repo
# Symlink or copy waveshare_epd into vendor/waveshare as needed
```
