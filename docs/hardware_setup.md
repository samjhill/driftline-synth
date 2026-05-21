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

## PiSugar 2 Pro (battery on e-ink)

Install [PiSugar Power Manager](https://docs.pisugar.com/docs/product-wiki/battery/pisugar-power-manager) and enable the server:

```bash
wget https://cdn.pisugar.com/release/pisugar-power-manager.sh
bash pisugar-power-manager.sh -c release
sudo systemctl enable --now pisugar-server
echo "get battery" | nc -U /tmp/pisugar-server.sock
```

The synth reads `battery: N` from `/tmp/pisugar-server.sock` (or TCP `127.0.0.1:8423`) and draws a gauge + **NN%** in the top-right of the e-ink (patch sigils and status screens). Toggle in `config/default.yaml` under `pisugar:`.

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
