#!/usr/bin/env bash
# Recovery install — run on the Pi after manual SSH (no cloud-init, no Mac rootfs surgery).
# Usage: cd ~/pi-ambient-synth && ./scripts/install_recovery_mode.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/pi_install_user.sh
source "$ROOT/scripts/lib/pi_install_user.sh"
# shellcheck source=scripts/lib/recovery_disable_legacy.sh
source "$ROOT/scripts/lib/recovery_disable_legacy.sh"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: run this script on the Raspberry Pi (Linux), not macOS." >&2
  exit 1
fi

PI_USER="$(pi_install_user)"
INSTALL_DIR="${INSTALL_DIR:-$(pi_install_dir)}"
if [[ "$ROOT" != "$INSTALL_DIR" ]] && [[ -d "$INSTALL_DIR" ]]; then
  echo "NOTE: using INSTALL_DIR=$INSTALL_DIR (run from clone: $ROOT)"
fi

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(
  -o Dpkg::Options::="--force-confdef"
  -o Dpkg::Options::="--force-confold"
)

echo "=============================================="
echo " Pi Ambient Synth — RECOVERY install"
echo " User: $PI_USER  Dir: $ROOT"
echo "=============================================="

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo INSTALL_DIR="$ROOT" PI_USER="$PI_USER" bash "$ROOT/scripts/install_recovery_mode.sh"
fi

recovery_disable_legacy_units

if [[ -f "$ROOT/scripts/lib_disable_ghostroll.sh" ]]; then
  # shellcheck source=scripts/lib_disable_ghostroll.sh
  source "$ROOT/scripts/lib_disable_ghostroll.sh"
  disable_ghostroll_autostart || true
fi

echo "==> Apt packages (recovery list only)..."
apt-get update -qq
mapfile -t _pkgs < <(grep -v '^#' "$ROOT/deploy/pi-recovery-apt.list" | grep -v '^[[:space:]]*$' || true)
apt-get install -y "${APT_OPTS[@]}" "${_pkgs[@]}"

if [[ -x "$ROOT/scripts/setup_pi_audio.sh" ]]; then
  echo "==> Headphone ALSA setup..."
  INSTALL_DIR="$ROOT" bash "$ROOT/scripts/setup_pi_audio.sh" || echo "WARN: setup_pi_audio.sh failed"
fi

echo "==> Python venv..."
if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
  sudo -u "$PI_USER" python3 -m venv "$ROOT/.venv"
fi
sudo -u "$PI_USER" "$ROOT/.venv/bin/pip" install -q --upgrade pip
sudo -u "$PI_USER" "$ROOT/.venv/bin/pip" install -q -r "$ROOT/requirements-recovery.txt"

echo "==> Recovery config (e-ink off, PiSugar reseed on)..."
sudo -u "$PI_USER" env HOME="/home/$PI_USER" "$ROOT/.venv/bin/python" -c "
from pathlib import Path
import yaml
p = Path('$ROOT/config/default.yaml')
data = yaml.safe_load(p.read_text())
data.setdefault('eink', {})['enabled'] = False
data['eink']['update_on_reseed'] = False
data.setdefault('pisugar', {})['enabled'] = True
data['pisugar']['reseed_on_button'] = True
data['pisugar']['show_on_display'] = False
data.setdefault('audio', {})['backend'] = 'fluidsynth'
p.write_text(yaml.dump(data, default_flow_style=False, sort_keys=False))
print('    config/default.yaml: eink off, pisugar reseed on, audio=fluidsynth')
"

mkdir -p "$ROOT/state"
chown -R "$PI_USER:$PI_USER" "$ROOT/state" "$ROOT/.venv" 2>/dev/null || true

mkdir -p /var/lib/pi-ambient-synth /etc/pi-ambient-synth
chown "$PI_USER:$PI_USER" /var/lib/pi-ambient-synth
chmod 775 /var/lib/pi-ambient-synth

if [[ -f "$ROOT/deploy/pi-audio-mode-fluidsynth.conf" ]]; then
  cp "$ROOT/deploy/pi-audio-mode-fluidsynth.conf" /etc/pi-ambient-synth/audio-mode.conf
else
  echo "AUDIO_MODE=fluidsynth" >/etc/pi-ambient-synth/audio-mode.conf
fi
PI_USER="$PI_USER" INSTALL_DIR="$ROOT" pi_write_install_env

usermod -aG audio,dialout,adm "$PI_USER" 2>/dev/null || usermod -aG audio,dialout "$PI_USER" 2>/dev/null || true

echo "==> Recovery systemd (midi + monitor only)..."
cp "$ROOT/systemd/pi-ambient-synth-midi.service" /etc/systemd/system/
cp "$ROOT/systemd/pi-ambient-synth-monitor.service" /etc/systemd/system/

mkdir -p /etc/systemd/system/pi-ambient-synth-midi.service.d \
  /etc/systemd/system/pi-ambient-synth-monitor.service.d
rm -f /etc/systemd/system/pi-ambient-synth-midi.service.d/*.conf \
  /etc/systemd/system/pi-ambient-synth-monitor.service.d/*.conf 2>/dev/null || true

tee /etc/systemd/system/pi-ambient-synth-midi.service.d/recovery.conf >/dev/null <<EOF
[Unit]
Conflicts=supercollider.service pi-flues-synth.service
After=sound.target

[Service]
User=$PI_USER
Group=$PI_USER
WorkingDirectory=$ROOT
Environment=HOME=/home/$PI_USER
Environment=PI_MIDI_BACKEND=fluidsynth
Environment=PI_DIRECT_ALSA_KEYS=0
Environment=PI_RECOVERY_MODE=1
EOF

if [[ -f "$ROOT/deploy/systemd/pi-ambient-synth-midi.fluidsynth.conf" ]]; then
  cp "$ROOT/deploy/systemd/pi-ambient-synth-midi.fluidsynth.conf" \
    /etc/systemd/system/pi-ambient-synth-midi.service.d/fluidsynth.conf
fi

tee /etc/systemd/system/pi-ambient-synth-monitor.service.d/recovery.conf >/dev/null <<EOF
[Service]
User=$PI_USER
Group=$PI_USER
WorkingDirectory=$ROOT
Environment=HOME=/home/$PI_USER
Environment=PI_MONITOR_SKIP_SIGIL=1
Environment=PI_RECOVERY_MODE=1
EOF

systemctl daemon-reload
systemctl enable pi-ambient-synth-midi.service pi-ambient-synth-monitor.service
systemctl restart pi-ambient-synth-midi.service pi-ambient-synth-monitor.service

echo "==> PiSugar reseed button (if pisugar-server installed)..."
bash "$ROOT/scripts/setup_recovery_pisugar_button.sh" || true

sleep 2
echo ""
echo "=============================================="
echo " Recovery install complete"
echo "=============================================="
systemctl --no-pager is-active pi-ambient-synth-midi.service pi-ambient-synth-monitor.service || true
echo ""
echo "Next:"
echo "  sudo reboot   # recommended once"
echo "  ./scripts/recovery_validation.sh"
echo "  ./scripts/start_recovery_synth.sh"
echo ""
echo "Optional manual start: ./scripts/start_recovery_synth.sh"
