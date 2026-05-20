# Hardware Setup

## Required

| Component | Notes |
|-----------|--------|
| Raspberry Pi 4B or 5 | Pi 3B+ works with lighter settings |
| Arturia KeyStep | USB MIDI controller |
| USB-A to USB-B **data** cable | Power-only cables will not work |
| Audio output | USB interface or 3.5 mm jack |
| Waveshare 2.13" E-Ink HAT V4 | 250×122, SPI |
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
