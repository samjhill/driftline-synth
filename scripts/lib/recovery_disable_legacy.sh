# shellcheck shell=bash
# Stop, disable, and mask non-recovery systemd units (run on Pi as root).

recovery_disable_legacy_units() {
  local u
  local -a exact=(
    supercollider.service
    pi-flues-synth.service
    pi-ambient-alsa-drone.service
    pi-ambient-jack-playback.service
    pi-ambient-jack-playback.timer
    pi-ambient-boot-validate.service
    pi-ambient-boot-sentinel.service
    pi-ambient-firstboot.service
    pi-ambient-autobringup.service
    pi-ambient-synth.service
    pi-ambient-synth-deploy.service
    pi-ambient-synth-deploy.timer
    pi-ambient-synth-boot-display.service
    pi-ambient-synth-audio-display.service
    pi-ambient-synth-network-announce.service
    pi-ambient-synth-firstboot-light.service
    pi-ambient-synth-firstboot-heavy.service
    pi-ambient-synth-eink.service
    pi-ambient-synth-eink-early.service
    pi-ambient-synth-eink-boot.service
    pi-ambient-synth-eink-prepare.service
    pi-ambient-synth-eink-patch.service
  )

  echo "==> Stopping legacy audio / provisioning / e-ink..."
  pkill -9 -x jackd scsynth sclang fluidsynth 2>/dev/null || true
  pkill -f ghostroll 2>/dev/null || true

  for u in "${exact[@]}"; do
    systemctl stop "$u" 2>/dev/null || true
    systemctl disable "$u" 2>/dev/null || true
    systemctl mask "$u" 2>/dev/null || true
  done

  while read -r u _; do
    [[ "$u" == ghostroll* ]] || continue
    [[ "$u" =~ \.(service|timer|socket|path)$ ]] || continue
    systemctl stop "$u" 2>/dev/null || true
    systemctl disable "$u" 2>/dev/null || true
    systemctl mask "$u" 2>/dev/null || true
    echo "    masked $u"
  done < <(systemctl list-unit-files --no-pager --no-legend 2>/dev/null || true)

  while read -r u _; do
  case "$u" in
    pi-ambient-synth-eink*|pi-ambient-synth-firstboot*)
      systemctl stop "$u" 2>/dev/null || true
      systemctl disable "$u" 2>/dev/null || true
      systemctl mask "$u" 2>/dev/null || true
      ;;
  esac
  done < <(systemctl list-unit-files --no-pager --no-legend 2>/dev/null || true)

  systemctl stop jackd2 2>/dev/null || true
  systemctl disable jackd2 2>/dev/null || true
  systemctl mask jackd2 2>/dev/null || true

  mkdir -p /etc/pi-ambient-synth
  date -Iseconds | tee /etc/pi-ambient-synth/recovery-mode >/dev/null
}
