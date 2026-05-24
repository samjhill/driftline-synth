# shellcheck shell=bash
# Detect install user from /home (first UID >= 1000). No hardcoded pi/sam.

autobringup_detect_user() {
  local u uid best_u="" best_uid=999999
  if [[ -d /home ]]; then
    for u in /home/*; do
      [[ -d "$u" ]] || continue
      u="${u##*/}"
      [[ "$u" == "lost+found" ]] && continue
      uid="$(id -u "$u" 2>/dev/null)" || continue
      if [[ "$uid" -ge 1000 && "$uid" -lt "$best_uid" ]]; then
        best_uid="$uid"
        best_u="$u"
      fi
    done
  fi
  if [[ -n "$best_u" ]]; then
    echo "$best_u"
    return 0
  fi
  # shellcheck source=scripts/lib/pi_install_user.sh
  if [[ -f "${AUTBRINGUP_INSTALL_DIR:-}/scripts/lib/pi_install_user.sh" ]]; then
    # shellcheck disable=SC1091
    source "${AUTBRINGUP_INSTALL_DIR}/scripts/lib/pi_install_user.sh"
    pi_install_user
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

autobringup_write_install_env() {
  local u="${1:?user}"
  local dir="/home/${u}/pi-ambient-synth"
  sudo mkdir -p /etc/pi-ambient-synth
  sudo tee /etc/pi-ambient-synth/install.env >/dev/null <<EOF
PI_USER=$u
INSTALL_USER=$u
INSTALL_HOME=/home/$u
INSTALL_DIR=$dir
EOF
  export PI_USER="$u" INSTALL_USER="$u" INSTALL_HOME="/home/$u" INSTALL_DIR="$dir"
}
