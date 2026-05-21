# Shared SSH/rsync helpers for Mac → Pi scripts.
# Password file (gitignored): .pi-ssh-credentials in repo root
#   ./scripts/run_pi_verify.sh --save-password
# Requires: brew install hudochenkov/sshpass/sshpass  (if using saved password)
pi_ssh_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pi_ssh_repo_root() {
  cd "$pi_ssh_lib_dir/../.." && pwd
}

pi_ssh_creds_file() {
  local root="${PI_SSH_CREDS_FILE:-$(pi_ssh_repo_root)/.pi-ssh-credentials}"
  echo "$root"
}

pi_ssh_load_password() {
  local f key host user h
  f="$(pi_ssh_creds_file)"
  [[ -f "$f" ]] || return 1
  # shellcheck disable=SC1090
  key="$(grep -E '^PASSWORD=' "$f" | head -1 | cut -d= -f2- || true)"
  if [[ -z "$key" ]]; then
    key="$(head -1 "$f" | tr -d '\r\n')"
  fi
  host="${PI_HOST:-$(grep -E '^HOST=' "$f" | head -1 | cut -d= -f2- || true)}"
  if [[ -n "${PI_SSH_HOST:-}" && -n "$host" ]]; then
    user="${PI_HOST%%@*}"
    h="${PI_HOST#*@}"
    if [[ "$PI_HOST" != "$host" && "${host#*@}" != "${h}" ]]; then
      return 1
    fi
  fi
  [[ -n "$key" ]] || return 1
  printf '%s' "$key"
}

pi_ssh_use_sshpass() {
  [[ -n "${PI_SSH_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1
}

pi_ssh_setup() {
  local root pw
  root="$(pi_ssh_repo_root)"
  mkdir -p "${HOME}/.cache/driftline-synth"
  PI_SSH_CONTROL_PATH="${PI_SSH_CONTROL_PATH:-${HOME}/.cache/driftline-synth/ssh-%C}"
  PI_SSH_COMMON_OPTS=(
    -o StrictHostKeyChecking=accept-new
    -o ControlMaster=auto
    -o "ControlPath=${PI_SSH_CONTROL_PATH}"
    -o ControlPersist=600
  )
  if [[ -n "${PI_SSH_PASSWORD:-}" ]]; then
    :
  elif pw="$(pi_ssh_load_password 2>/dev/null)"; then
    export SSHPASS="$pw"
    export PI_SSH_PASSWORD="$pw"
  fi
  if pi_ssh_use_sshpass; then
    PI_SSH_HAS_SAVED_PASS=1
  else
    PI_SSH_HAS_SAVED_PASS=0
    if [[ -f "$(pi_ssh_creds_file)" ]] && ! command -v sshpass >/dev/null 2>&1; then
      echo "WARN: .pi-ssh-credentials exists but sshpass not installed — you will be prompted." >&2
      echo "      brew install hudochenkov/sshpass/sshpass" >&2
    fi
  fi
}

pi_ssh_save_password() {
  local f root host pw
  root="$(pi_ssh_repo_root)"
  f="$(pi_ssh_creds_file)"
  host="${PI_HOST:-pi@raspberrypi.local}"
  read -rsp "SSH password for ${host}: " pw
  echo
  umask 077
  printf 'HOST=%s\nPASSWORD=%s\n' "$host" "$pw" >"$f"
  echo "Saved to $f (chmod 600, gitignored)."
}

pi_ssh() {
  if [[ "${PI_SSH_HAS_SAVED_PASS:-0}" == "1" ]]; then
    sshpass -e ssh "${PI_SSH_COMMON_OPTS[@]}" "$@"
  else
    ssh "${PI_SSH_COMMON_OPTS[@]}" "$@"
  fi
}

pi_scp() {
  if [[ "${PI_SSH_HAS_SAVED_PASS:-0}" == "1" ]]; then
    sshpass -e scp "${PI_SSH_COMMON_OPTS[@]}" "$@"
  else
    scp "${PI_SSH_COMMON_OPTS[@]}" "$@"
  fi
}

pi_rsync() {
  local rsh
  if [[ "${PI_SSH_HAS_SAVED_PASS:-0}" == "1" ]]; then
    rsh="sshpass -e ssh"
    for o in "${PI_SSH_COMMON_OPTS[@]}"; do
      rsh+=" $(printf '%q' "$o")"
    done
  else
    rsh="ssh"
    for o in "${PI_SSH_COMMON_OPTS[@]}"; do
      rsh+=" $(printf '%q' "$o")"
    done
  fi
  rsync -az -e "$rsh" "$@"
}

pi_ssh_try_batch() {
  pi_ssh -o BatchMode=yes -o ConnectTimeout=8 "$@" 'echo ok' 2>/dev/null
}
