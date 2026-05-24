# shellcheck shell=bash
# Resolve Imager username (sam) vs legacy pi.

pi_install_user() {
  if [[ -n "${PI_USER:-}" ]] && id -u "$PI_USER" &>/dev/null; then
    echo "$PI_USER"
    return 0
  fi
  for u in sam pi; do
    if id -u "$u" &>/dev/null; then
      echo "$u"
      return 0
    fi
  done
  echo "pi"
}

pi_install_dir() {
  local u
  u="$(pi_install_user)"
  echo "/home/${u}/pi-ambient-synth"
}

pi_write_install_env() {
  local u dir
  u="$(pi_install_user)"
  dir="$(pi_install_dir)"
  sudo mkdir -p /etc/pi-ambient-synth
  sudo tee /etc/pi-ambient-synth/install.env >/dev/null <<EOF
PI_USER=$u
INSTALL_DIR=$dir
EOF
}
